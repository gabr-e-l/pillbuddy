// lib/services/notification_service.dart
//
// Patient notification flow (three-stage alarm):
//
//   Stage 0 — First Reminder  (at scheduled time)
//     • Sound: alarm_sound.wav, DND bypass, fullScreenIntent
//     • "Mark as Taken" is the ONLY active action in-app.
//
//   Stage 1 — Snooze Alert    (+10 min)
//     • Same sound / channel.
//     • "Mark as Taken Late" is the ONLY active action in-app.
//
//   Stage 2 — Final Alert     (+20 min)
//     • Same sound / channel.
//     • Dose is automatically written to Firestore as 'skipped'.
//     • Patient may still change it to 'taken_late' later that day;
//       'taken' is greyed-out in-app (see patient_home.dart).
//
// Alert stage is persisted in SharedPreferences as
//   notif_stage_{medId} → 0 | 1 | 2
// so patient_home.dart can read it to decide which buttons to enable.
//
// Caregiver:
//   Instant notification when a patient marks a dose (unchanged).
//
// ── Timezone fix ──────────────────────────────────────────────────────────
//
// flutter_timezone v5.x changed its return type: getLocalTimezone() now
// returns a plain String, not an object with an .identifier field.
// Calling .identifier on a String is a runtime error that silently falls
// through to the catch block, which previously computed UTC offset in hours
// (an int) but compared it against zone.offset in milliseconds — so the
// fallback always matched UTC, making every alarm fire at the wrong time.
//
// Fix: replace flutter_timezone entirely with a native MethodChannel call
// to MainActivity ("getTimezone") which returns TimeZone.getDefault().id —
// the correct IANA string on every Android version without any plugin.
//
// ── DND / Full-screen alarm notes ─────────────────────────────────────────
//
// Android layers that together guarantee the alarm sounds through DND:
//
//   1. AndroidManifest.xml permissions:
//        USE_FULL_SCREEN_INTENT  — show alarm UI over lock screen (API 34+)
//        WAKE_LOCK               — wake CPU+screen from deep sleep
//        ACCESS_NOTIFICATION_POLICY — white-list this app with DND policy
//
//   2. Notification channel (created once in init()):
//        importance = Importance.max
//        audioAttributesUsage = AudioAttributesUsage.alarm
//        ↳ Android treats this like a clock alarm — exempt from DND.
//
//   3. Individual notification (every _alarmDetails() call):
//        category   = alarm        → Android treats this as a clock alarm
//        fullScreenIntent = true   ← pops alarm UI even on lock screen
//        visibility = public       → content visible on secure lock screen
//        audioAttributesUsage = alarm → alarm audio stream, bypasses DND
//        timeoutAfter = 30 000 ms  ← auto-dismiss after the WAV ends
//
//   4. alarm_sound.wav in android/app/src/main/res/raw/
//
//   5. MainActivity — android:showWhenLocked="true"
//                     android:turnScreenOn="true"
//      Forces the screen on so the alarm is visible even when locked.
//
// ── Multi-intake-time fix ───────────────────────────────────────────────
//
// Medications can have more than one scheduled time per day ("every 8
// hours", "2 times a day", etc.) stored in MedicationModel.intakeTimes.
// Previously only the medication's primary (first) hour/minute/period was
// ever scheduled, so doses later in the day never alarmed.
// scheduleMedicationReminders() now schedules a full 3-stage alarm set for
// EVERY entry in intakeTimes, each addressed by a unique notification ID
// (see _stageId, which now also encodes a timeIndex).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io';

import 'intake_service.dart'; // needed to auto-record 'skipped' at final alert

class NotificationService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Native MethodChannel defined in MainActivity.kt
  static const _systemChannel = MethodChannel('com.example.pillbuddy/system');

  bool _initialized = false;

  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const _keyPatientEnabled   = 'notif_patient_enabled';
  static const _keyCaregiverEnabled = 'notif_caregiver_enabled';
  // Stage per medication: 'notif_stage_{medId}' → int (0 | 1 | 2)
  static const _stagePrefix         = 'notif_stage_';

  // ── Notification channel IDs ───────────────────────────────────────────────
  static const _alarmChannelId     = 'pillbuddy_alarm';       // DND bypass
  static const _caregiverChannelId = 'pillbuddy_caregiver_updates';

  // ── Notification ID ranges ─────────────────────────────────────────────────
  // Stage-0 first reminder : 1_000_000 + hash
  // Stage-1 snooze alert   : 2_000_000 + hash
  // Stage-2 final alert    : 3_000_000 + hash
  // Caregiver update       : 4_000_000 + hash

  // ── Initialise ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    // ── Set the device's local timezone so zonedSchedule fires on time ──────
    //
    // We ask MainActivity for the IANA timezone ID via a MethodChannel instead
    // of using flutter_timezone, whose v5.x API changed and caused a runtime
    // error that left tz.local pointing at UTC.
    await _resolveLocalTimezone();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // ── Alarm channel — max importance + custom alarm_sound.wav ──────────────
    //
    // IMPORTANT: Android reads the channel's sound and audioAttributesUsage
    // ONLY when the channel is first created. If you need to change the sound
    // you must uninstall the app or clear app data first.
    //
    // audioAttributesUsage = AudioAttributesUsage.alarm tells the Android
    // audio subsystem to treat this channel's audio as an alarm stream,
    // which is exempt from Do Not Disturb by default on all Android versions.
    const alarmChannel = AndroidNotificationChannel(
      _alarmChannelId,
      'Medication Alarms',
      description: 'Urgent alerts for scheduled medication doses',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
      // Alarm stream → exempt from DND at the OS audio-routing level.
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    const caregiverChannel = AndroidNotificationChannel(
      _caregiverChannelId,
      'Patient Intake Updates',
      description: 'Notifications when a patient marks a dose',
      importance: Importance.defaultImportance,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(alarmChannel);
    await androidPlugin?.createNotificationChannel(caregiverChannel);

    _initialized = true;
  }

  /// Resolves the device's IANA timezone via the native MethodChannel and
  /// sets tz.local.  Falls back to matching by UTC offset if the channel
  /// call fails (e.g. on non-Android platforms or during tests).
  Future<void> _resolveLocalTimezone() async {
    try {
      final tzId = await _systemChannel.invokeMethod<String>('getTimezone');
      if (tzId != null && tzId.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(tzId));
        debugPrint('[NotificationService] Timezone set to $tzId');
        return;
      }
    } catch (e) {
      debugPrint('[NotificationService] Native getTimezone failed: $e');
    }

    // ── Fallback: match on UTC offset in milliseconds (not hours!) ──────────
    // The previous fallback compared zone.offset (milliseconds since epoch)
    // against offsetHours * Duration.millisecondsPerHour, which was a unit
    // mismatch that always resolved to UTC.  Fixed below.
    try {
      final offsetMs = DateTime.now().timeZoneOffset.inMilliseconds;
      final fallback = tz.timeZoneDatabase.locations.values.firstWhere(
        (loc) {
          if (loc.zones.isEmpty) return false;
          return loc.currentTimeZone.offset == offsetMs;
        },
        orElse: () => tz.UTC,
      );
      tz.setLocalLocation(fallback);
      debugPrint(
          '[NotificationService] Timezone fallback: ${fallback.name}');
    } catch (e) {
      debugPrint('[NotificationService] Timezone fallback failed, using UTC: $e');
      tz.setLocalLocation(tz.UTC);
    }
  }

  // Called when the user taps the notification itself (not an action button).
  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('[NotificationService] tapped id=${response.id} '
        'payload=${response.payload}');
  }

  // ── Permission request ─────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    bool granted = true;
    if (android != null) {
      final result = await android.requestNotificationsPermission();
      granted = result ?? false;
      // Request exact alarm permission (Android 12+).
      // If the user hasn't granted it the alarms will not fire on time.
      await android.requestExactAlarmsPermission();
    }
    if (ios != null) {
      final result = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );
      granted = result ?? false;
    }
    return granted;
  }

  /// Opens the system exact-alarm settings page so the user can grant
  /// SCHEDULE_EXACT_ALARM on Android 12+.  Call this from the UI when
  /// isExactAlarmPermitted() returns false.
  Future<void> openExactAlarmSettings() async {
    try {
      await _systemChannel.invokeMethod('openExactAlarmSettings');
    } catch (e) {
      debugPrint('[NotificationService] openExactAlarmSettings failed: $e');
    }
  }

  /// Returns true if the app can schedule exact alarms (Android 12+).
  /// Always returns true below Android 12.
  Future<bool> isExactAlarmPermitted() async {
    try {
      final result = await _systemChannel
          .invokeMethod<bool>('isExactAlarmPermitted');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  // ── Preferences getters / setters ─────────────────────────────────────────

  Future<bool> isPatientEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPatientEnabled) ?? true;
  }

  Future<void> setPatientEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPatientEnabled, value);
    if (!value) await cancelAllPatientReminders();
  }

  Future<bool> isCaregiverEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyCaregiverEnabled) ?? true;
  }

  Future<void> setCaregiverEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCaregiverEnabled, value);
    if (!value) await cancelAllCaregiverNotifications();
  }

  // ── Alert-stage helpers ────────────────────────────────────────────────────

  /// Returns the current notification stage for [medId] / [timeIndex]:
  ///   0 = first reminder not yet fired (or reset)
  ///   1 = snooze alert fired (10 min past)
  ///   2 = final alert fired (20 min past) — dose auto-skipped
  ///
  /// [timeIndex] defaults to 0 so existing single-time callers (and the
  /// primary-time lookup in patient_home.dart) keep working unchanged.
  Future<int> getAlertStage(String medId, {int timeIndex = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_stageKey(medId, timeIndex)) ?? 0;
  }

  Future<void> _setAlertStage(String medId, int stage,
      {int timeIndex = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stageKey(medId, timeIndex), stage);
  }

  Future<void> resetAlertStage(String medId, {int timeIndex = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stageKey(medId, timeIndex));
  }

  String _stageKey(String medId, int timeIndex) =>
      timeIndex == 0 ? '$_stagePrefix$medId' : '$_stagePrefix${medId}_$timeIndex';

  // ── Notification details helpers ──────────────────────────────────────────

  Future<String> _writeAppIconToTempFile() async {
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      final bytes = data.buffer.asUint8List();
      final dir = await Directory.systemTemp.createTemp('pillbuddy_icons_');
      final file = File('${dir.path}/app_icon.png');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint(
          '[NotificationService] Failed to write app icon to temp file: $e');
      rethrow;
    }
  }

  /// High-priority alarm notification that bypasses DND.
  ///
  /// Key DND-bypass flags:
  ///   • category = alarm              → treated as a system clock alarm
  ///   • audioAttributesUsage = alarm  → alarm audio stream, exempt from DND
  ///   • fullScreenIntent = true       → pops alarm UI over lock screen
  ///   • visibility = public           → content shown on secure lock screen
  ///   • timeoutAfter = 30 000 ms      → auto-dismiss after WAV ends
  Future<NotificationDetails> _alarmDetails({
    required int stage,
    required String medName,
  }) async {
    final iconPath = await _writeAppIconToTempFile();
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _alarmChannelId,
        'Medication Alarms',
        channelDescription: 'Urgent alerts for scheduled medication doses',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@drawable/ic_stat_notify',
        largeIcon: FilePathAndroidBitmap(iconPath),

        // ── Sound ────────────────────────────────────────────────────────────
        // Must match the channel's sound exactly (alarm_sound in res/raw).
        sound: const RawResourceAndroidNotificationSound('alarm_sound'),
        playSound: true,
        enableVibration: true,

        // ── DND bypass ───────────────────────────────────────────────────────
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,

        // ── Auto-dismiss after sound ends ────────────────────────────────────
        timeoutAfter: 30000,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'alarm_sound.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  Future<NotificationDetails> _caregiverDetails() async {
    final iconPath = await _writeAppIconToTempFile();
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _caregiverChannelId,
        'Patient Intake Updates',
        channelDescription: 'Notifications when a patient marks a dose',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@drawable/ic_stat_notify',
        largeIcon: FilePathAndroidBitmap(iconPath),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  // ── ID helpers ────────────────────────────────────────────────────────────
  //
  // Notification IDs now encode (stage, medId, timeIndex) so a medication
  // with multiple daily intake times (e.g. "every 8 hours" → 3 times/day)
  // gets a distinct set of alarm IDs per intake time instead of every extra
  // time silently overwriting slot 0's pending alarm.
  //
  //   id = (stage + 1) * 1,000,000            (existing stage banding)
  //        + timeIndex * 100,000               (new: up to 9 times/med)
  //        + hash(medId) % 99,000               (existing per-med spread,
  //                                              shrunk so it fits inside a
  //                                              single 100,000-wide band)
  //
  // maxTimesPerMed bounds how many intake-time slots we will ever
  // schedule/cancel for a single medication — comfortably above any realistic
  // frequency while keeping IDs safely below the caregiver ID range
  // (4,000,000+).
  static const int maxTimesPerMed = 9;

  int _stageId(String medId, int stage, [int timeIndex = 0]) =>
      ((stage + 1) * 1000000) +
      (timeIndex * 100000) +
      (medId.hashCode.abs() % 99000);

  int _caregiverId(String patientUid, String medId) =>
      4000000 + (patientUid + medId).hashCode.abs() % 999000;

  // ── Patient: schedule reminders for every intake time on a medication ────

  /// Schedules reminders for EVERY intake time configured on a medication.
  ///
  /// [intakeTimes] should be the medication's full list of intake times
  /// (each a {'hour','minute','period'} map). If empty, falls back to a
  /// single occurrence built from [hour]/[minute]/[period] (the legacy
  /// single-time fields), so medications without an intakeTimes list still
  /// get scheduled exactly as before.
  ///
  /// This is the fix for medications with multiple daily intake times (e.g.
  /// "every 8 hours" or "2 times a day"): previously only the primary
  /// (first) time was ever scheduled, so doses later in the day never
  /// alarmed. Now every configured time gets its own 3-stage alarm set,
  /// each addressed by a unique notification ID (see _stageId).
  Future<void> scheduleMedicationReminders({
    required String medId,
    required String medName,
    required double dose,
    required String unit,
    required List<Map<String, dynamic>> intakeTimes,
    required int hour,
    required int minute,
    required String period,
  }) async {
    final times = intakeTimes.isNotEmpty
        ? intakeTimes
        : [
            {'hour': hour, 'minute': minute, 'period': period}
          ];

    // Cancel any previously scheduled slots first, in case the medication's
    // intake-time count shrank since the last schedule call.
    await cancelPatientReminder(medId);

    final cappedTimes = times.length > maxTimesPerMed
        ? times.sublist(0, maxTimesPerMed)
        : times;

    for (int i = 0; i < cappedTimes.length; i++) {
      final t = cappedTimes[i];
      // Defensive: Firestore can deserialize whole numbers as either int or
      // num depending on path, so coerce rather than assume `int`.
      final tHour = (t['hour'] as num?)?.toInt() ?? hour;
      final tMinute = (t['minute'] as num?)?.toInt() ?? minute;
      final tPeriod = t['period'] as String? ?? period;
      await schedulePatientReminder(
        medId: medId,
        medName: medName,
        dose: dose,
        unit: unit,
        hour: tHour,
        minute: tMinute,
        period: tPeriod,
        timeIndex: i,
      );
    }
  }

  /// Schedules three daily alarms (repeating via matchDateTimeComponents.time):
  ///   • Stage 0 — at [hour]:[minute]
  ///   • Stage 1 — +10 min  (snooze prompt)
  ///   • Stage 2 — +20 min  (final, then auto-skips)
  ///
  /// [timeIndex] identifies which of a medication's (possibly multiple)
  /// daily intake times this call is scheduling, so each occurrence gets its
  /// own non-colliding set of notification IDs. Defaults to 0 for
  /// single-time medications / existing callers.
  Future<void> schedulePatientReminder({
    required String medId,
    required String medName,
    required double dose,
    required String unit,
    required int hour,    // 1-12
    required int minute,
    required String period, // 'AM' | 'PM'
    int timeIndex = 0,
  }) async {
    await init();
    if (!await isPatientEnabled()) return;

    // Convert 12 h → 24 h
    final h24 = hour % 12 + (period == 'PM' ? 12 : 0);

    final now = tz.TZDateTime.now(tz.local);
    var base = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, h24, minute);
    if (base.isBefore(now)) base = base.add(const Duration(days: 1));

    final timeLabel =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    final doseLabel = '${dose % 1 == 0 ? dose.toInt() : dose} $unit';

    // Stage 0 — First Reminder
    await _plugin.zonedSchedule(
      _stageId(medId, 0, timeIndex),
      '💊 Time for $medName',
      '$doseLabel — scheduled at $timeLabel',
      base,
      await _alarmDetails(stage: 0, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'stage:0:$medId:$timeIndex',
    );

    // Stage 1 — Snooze Alert (+10 min)
    await _plugin.zonedSchedule(
      _stageId(medId, 1, timeIndex),
      '⏰ Reminder: $medName',
      "You haven't marked $medName as taken yet.",
      base.add(const Duration(minutes: 10)),
      await _alarmDetails(stage: 1, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'stage:1:$medId:$timeIndex',
    );

    // Stage 2 — Final Alert (+20 min)
    await _plugin.zonedSchedule(
      _stageId(medId, 2, timeIndex),
      '⚠️ Final Alert: $medName',
      '$medName ($doseLabel) has been recorded as a missed dose.',
      base.add(const Duration(minutes: 20)),
      await _alarmDetails(stage: 2, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'stage:2:$medId:$timeIndex',
    );

    // Reset stage counter so the UI shows "Taken" as active until first alarm.
    await resetAlertStage(medId, timeIndex: timeIndex);

    debugPrint(
        '[NotificationService] Scheduled 3-stage alarms for $medName '
        '(slot $timeIndex) at $timeLabel');
  }

  /// Called by patient_home.dart when each notification fires (via a
  /// background isolate handler or when the app is foregrounded).
  /// Updates stage tracking and auto-records 'skipped' at stage 2.
  Future<void> onAlarmFired({
    required String medId,
    required String medName,
    required int stage,
    int timeIndex = 0,
  }) async {
    await _setAlertStage(medId, stage, timeIndex: timeIndex);
    debugPrint('[NotificationService] Stage $stage fired for $medId (slot $timeIndex)');

    if (stage == 2) {
      // Auto-record 'skipped' — patient can still change to 'taken_late'
      try {
        await IntakeService().recordIntake(
          medId:   medId,
          medName: medName,
          status:  'skipped',
          date:    DateTime.now(),
        );
        debugPrint('[NotificationService] Auto-skipped $medName');
      } catch (e) {
        debugPrint('[NotificationService] Auto-skip error: $e');
      }
    }
  }

  /// Cancel all three alarm slots, across every intake-time slot, for a
  /// given medication.
  Future<void> cancelPatientReminder(String medId) async {
    for (int t = 0; t < maxTimesPerMed; t++) {
      for (int s = 0; s < 3; s++) {
        await _plugin.cancel(_stageId(medId, s, t));
      }
      await resetAlertStage(medId, timeIndex: t);
    }
  }

  Future<void> cancelAllPatientReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.id >= 1000000 && n.id < 4000000) {
        await _plugin.cancel(n.id);
      }
    }
  }

  // ── Caregiver: fire an immediate notification ─────────────────────────────

  Future<void> notifyCaregiverIntakeUpdate({
    required String patientUid,
    required String patientName,
    required String medName,
    required String status,
    required DateTime timestamp,
  }) async {
    await init();
    if (!await isCaregiverEnabled()) return;

    final label = _statusLabel(status);
    final emoji = _statusEmoji(status);
    final timeStr = _formatTime(timestamp);

    await _plugin.show(
      _caregiverId(patientUid, medName),
      '$emoji $patientName — $medName',
      '$label at $timeStr',
      await _caregiverDetails(),
    );
  }

  Future<void> cancelAllCaregiverNotifications() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.id >= 4000000) await _plugin.cancel(n.id);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _statusLabel(String status) {
    switch (status) {
      case 'taken':      return 'Taken ✓';
      case 'taken_late': return 'Taken Late';
      case 'skipped':    return 'Missed / Skipped';
      default:           return status;
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'taken':      return '✅';
      case 'taken_late': return '🕐';
      case 'skipped':    return '❌';
      default:           return '💊';
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }
}