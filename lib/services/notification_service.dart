// lib/services/notification_service.dart
//
// Patient notification flow (three-stage alarm):
//
//   Stage 0 — First Reminder  (at scheduled time, repeats daily via matchDateTimeComponents)
//     • Sound: alarm_sound.wav, DND bypass, fullScreenIntent
//     • Only "Taken" is the active action in-app.
//     • When it fires → schedules Stage 1 as a ONE-SHOT alarm (+10 min).
//
//   Stage 1 — Follow-Up Alarm (+10 min, ONE-SHOT — only if dose still unmarked)
//     • Scheduled by onAlarmFired(stage:0) at the moment stage 0 fires.
//     • Same sound / channel.
//     • Only "Taken Late" is the active action in-app.
//     • When it fires → schedules Stage 2 as a ONE-SHOT alarm (+10 more min).
//
//   Stage 2 — Final Alarm (+20 min total, ONE-SHOT)
//     • Dose is automatically written to Firestore as 'skipped' ONLY IF it
//       hasn't already been marked 'taken' or 'taken_late'.
//     • Patient may still change it to 'taken_late' later that day.
//
// Why one-shot for stages 1 & 2?
//   Using matchDateTimeComponents: DateTimeComponents.time for all three
//   stages caused two problems:
//     1. Cancellation unreliability — Android's AlarmManager sometimes fails
//        to cancel an exact repeating alarm that is actively firing.
//     2. Stage 1/2 would fire EVERY day, not just the day the dose was missed.
//   Scheduling stages 1 & 2 as one-shot alarms triggered by the previous
//   stage firing means they are created fresh each time, cancel reliably
//   (they are brand new alarms at creation time), and automatically stop
//   when the patient marks the dose.
//
// How stage escalation works:
//   onAlarmFired(stage: 0) → scheduleNextStage(1, +10 min)
//   onAlarmFired(stage: 1) → scheduleNextStage(2, +10 more min)
//   onAlarmFired(stage: 2) → check Firestore; if unmarked → write 'skipped'
//
// When patient marks taken/taken_late:
//   cancelSlotStages() cancels all three IDs for that slot. Since stages 1 & 2
//   are one-shot and were just recently created, cancel() is guaranteed to
//   remove them before they fire.
//
// Alert stage is persisted in SharedPreferences as
//   notif_stage_{medId}_{timeIndex} → 0 | 1 | 2
// so patient_home.dart can read it to decide which buttons to enable.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io';

import 'intake_service.dart';

class NotificationService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _systemChannel = MethodChannel('com.example.pillbuddy/system');

  bool _initialized = false;

  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const _keyPatientEnabled   = 'notif_patient_enabled';
  static const _keyCaregiverEnabled = 'notif_caregiver_enabled';
  static const _stagePrefix         = 'notif_stage_';

  // ── Notification channel IDs ───────────────────────────────────────────────
  static const _alarmChannelId     = 'pillbuddy_alarm';
  static const _caregiverChannelId = 'pillbuddy_caregiver_updates';

  // ── Notification ID layout ─────────────────────────────────────────────────
  // Stage-0 (daily repeat) : 1_000_000 + timeIndex*100_000 + hash(medId)%99_000
  // Stage-1 (one-shot)     : 2_000_000 + timeIndex*100_000 + hash(medId)%99_000
  // Stage-2 (one-shot)     : 3_000_000 + timeIndex*100_000 + hash(medId)%99_000
  // Caregiver              : 4_000_000 + hash
  static const int maxTimesPerMed = 24; // Hour freq can have up to 24 slots

  int _stageId(String medId, int stage, [int timeIndex = 0]) =>
      ((stage + 1) * 1000000) +
      (timeIndex * 100000) +
      (medId.hashCode.abs() % 99000);

  int _caregiverId(String patientUid, String medId) =>
      4000000 + (patientUid + medId).hashCode.abs() % 999000;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
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
      onDidReceiveNotificationResponse:           _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: handleBackground,
    );

    const alarmChannel = AndroidNotificationChannel(
      _alarmChannelId,
      'Medication Alarms',
      description: 'Urgent alerts for scheduled medication doses',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
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
      debugPrint('[NotificationService] Timezone fallback: ${fallback.name}');
    } catch (e) {
      debugPrint('[NotificationService] Timezone fallback failed, using UTC: $e');
      tz.setLocalLocation(tz.UTC);
    }
  }

  /// Called when a notification fires (foreground) or is tapped.
  /// Parses the payload to drive stage escalation.
  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    debugPrint('[NotificationService] response id=${response.id} payload=$payload');
    _handlePayload(payload);
  }

  /// Parse 'stage:N:medId:timeIndex:dose:unit' and call [onAlarmFired].
  void _handlePayload(String payload) {
    if (payload.isEmpty) return;
    final parts = payload.split(':');
    if (parts.length < 4 || parts[0] != 'stage') return;
    final stage     = int.tryParse(parts[1]) ?? 0;
    final medId     = parts[2];
    final timeIndex = int.tryParse(parts[3]) ?? 0;
    final dose      = parts.length > 4 ? double.tryParse(parts[4]) ?? 1.0 : 1.0;
    final unit      = parts.length > 5 ? parts[5] : 'mg';

    // Fire and forget — we are in a sync callback.
    onAlarmFired(
      medId:     medId,
      medName:   medId,
      stage:     stage,
      timeIndex: timeIndex,
      dose:      dose,
      unit:      unit,
    );
  }

  /// Register as onDidReceiveBackgroundNotificationResponse in main.dart so
  /// stage escalation works even when the app is terminated.
  @pragma('vm:entry-point')
  static void handleBackground(NotificationResponse response) {
    NotificationService()._handlePayload(response.payload ?? '');
  }

  // ── Permissions ────────────────────────────────────────────────────────────

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

  Future<void> openExactAlarmSettings() async {
    try {
      await _systemChannel.invokeMethod('openExactAlarmSettings');
    } catch (e) {
      debugPrint('[NotificationService] openExactAlarmSettings failed: $e');
    }
  }

  Future<bool> isExactAlarmPermitted() async {
    try {
      final result =
          await _systemChannel.invokeMethod<bool>('isExactAlarmPermitted');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  // ── Preferences ────────────────────────────────────────────────────────────

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

  // ── Alert-stage tracking ───────────────────────────────────────────────────

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

  // ── Notification details ───────────────────────────────────────────────────

  Future<String> _writeAppIconToTempFile() async {
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      final bytes = data.buffer.asUint8List();
      final dir = await Directory.systemTemp.createTemp('pillbuddy_icons_');
      final file = File('${dir.path}/app_icon.png');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[NotificationService] Failed to write app icon: $e');
      rethrow;
    }
  }

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
        sound: const RawResourceAndroidNotificationSound('alarm_sound'),
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
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

  // ── Patient: schedule reminders ────────────────────────────────────────────

  /// Schedules Stage 0 (daily repeat) for every intake time on the medication.
  /// Stages 1 and 2 are one-shot and will be scheduled by [onAlarmFired]
  /// at the moment the previous stage fires.
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

    await cancelPatientReminder(medId);

    final cappedTimes =
        times.length > maxTimesPerMed ? times.sublist(0, maxTimesPerMed) : times;

    for (int i = 0; i < cappedTimes.length; i++) {
      final t = cappedTimes[i];
      // For Hour frequency the list contains slotIndex-keyed entries.
      // The timeIndex stored in the notification ID must match what
      // patient_home uses as the intake doc's timeIndex.
      // intakeTimes for Hour frequency is not stored per-day — alarms are
      // scheduled once per day from patient_home when the app opens.
      // For Hour meds we pass the today-specific list and use slot i as index.
      final tHour   = (t['hour']   as num?)?.toInt() ?? hour;
      final tMinute = (t['minute'] as num?)?.toInt() ?? minute;
      final tPeriod = t['period']  as String? ?? period;
      // slotIndex is the global step index used as the Firestore timeIndex
      final slotIndex = (t['slotIndex'] as num?)?.toInt() ?? i;
      await _scheduleAllStages(
        medId:     medId,
        medName:   medName,
        dose:      dose,
        unit:      unit,
        hour:      tHour,
        minute:    tMinute,
        period:    tPeriod,
        timeIndex: slotIndex,
      );
    }
  }

  /// Schedules all three alarm stages for one intake-time slot.
  ///
  /// Why pre-schedule instead of chaining via onAlarmFired?
  /// -------------------------------------------------------
  /// flutter_local_notifications' onDidReceiveNotificationResponse and
  /// onDidReceiveBackgroundNotificationResponse only fire when the USER TAPS
  /// a notification — NOT when it is delivered passively. There is no
  /// Dart-side callback for silent delivery on Android without a native
  /// WorkManager plugin. Pre-scheduling all three stages upfront is the only
  /// approach that works reliably without adding a native plugin.
  ///
  /// Schedule layout (all times are absolute, one-shot except stage 0):
  ///   Stage 0 → exact scheduled time, daily repeat (matchDateTimeComponents)
  ///   Stage 1 → scheduled time + 10 min, one-shot (no matchDateTimeComponents)
  ///   Stage 2 → scheduled time + 20 min, one-shot (no matchDateTimeComponents)
  ///
  /// Stages 1 and 2 are cancelled immediately when the patient marks the dose.
  /// Stage 0 is cancelled to prevent next-day re-firing after the medication
  /// reaches its stop date (handled by _scheduleRemindersIfChanged).
  Future<void> _scheduleAllStages({
    required String medId,
    required String medName,
    required double dose,
    required String unit,
    required int    hour,
    required int    minute,
    required String period,
    int timeIndex = 0,
  }) async {
    await init();
    if (!await isPatientEnabled()) return;

    final h24 = hour % 12 + (period == 'PM' ? 12 : 0);
    final now  = tz.TZDateTime.now(tz.local);
    var base   = tz.TZDateTime(tz.local, now.year, now.month, now.day, h24, minute);
    if (base.isBefore(now)) base = base.add(const Duration(days: 1));

    final timeLabel =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    final doseLabel = '${dose % 1 == 0 ? dose.toInt() : dose} $unit';

    // ── Stage 0: daily repeating alarm ───────────────────────────────────
    await _plugin.zonedSchedule(
      _stageId(medId, 0, timeIndex),
      '💊 Time for $medName',
      '$doseLabel — scheduled at $timeLabel',
      base,
      await _alarmDetails(stage: 0, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeats daily
      payload: 'stage:0:$medId:$timeIndex:${dose.toString()}:$unit',
    );

    // ── Stage 1: one-shot +10 min ─────────────────────────────────────────
    // base here is already the NEXT future occurrence (today or tomorrow).
    // Stage 1 fires +10 min after that exact fire, so it is also one-shot
    // from the same base + 10 min. It does NOT use matchDateTimeComponents
    // so it fires exactly once. After a patient marks the dose, this alarm
    // is cancelled — it will not fire again until the patient opens the app
    // again on the next day and _scheduleRemindersIfChanged re-creates it.
    final stage1Time = base.add(const Duration(minutes: 10));
    await _plugin.zonedSchedule(
      _stageId(medId, 1, timeIndex),
      '⏰ Reminder: $medName',
      "You haven't marked $medName as taken yet.",
      stage1Time,
      await _alarmDetails(stage: 1, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // NO matchDateTimeComponents — one-shot only.
      payload: 'stage:1:$medId:$timeIndex:${dose.toString()}:$unit',
    );

    // ── Stage 2: one-shot +20 min ─────────────────────────────────────────
    final stage2Time = base.add(const Duration(minutes: 20));
    await _plugin.zonedSchedule(
      _stageId(medId, 2, timeIndex),
      '⚠️ Final Alert: $medName',
      '$medName ($doseLabel) has been recorded as a missed dose.',
      stage2Time,
      await _alarmDetails(stage: 2, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // NO matchDateTimeComponents — one-shot only.
      payload: 'stage:2:$medId:$timeIndex:${dose.toString()}:$unit',
    );

    await resetAlertStage(medId, timeIndex: timeIndex);

    debugPrint('[NotificationService] All 3 stages scheduled for $medName '
        '(slot $timeIndex) at $timeLabel, +10min, +20min');
  }

  /// Called when an alarm fires (via notification tap or background handler).
  ///
  /// Now that all three stages are pre-scheduled upfront, this method's only
  /// jobs are:
  ///  1. Persist the current alert stage to SharedPreferences so the
  ///     patient_home Mark-As sheet shows the right enabled/disabled buttons.
  ///  2. At stage 2: check Firestore and auto-record 'skipped' if the dose
  ///     hasn't already been marked by the patient.
  ///
  /// It no longer needs to chain-schedule later stages (that was the old
  /// approach which failed because notification response callbacks only fire
  /// on tap, not on delivery).
  Future<void> onAlarmFired({
    required String medId,
    required String medName,
    required int    stage,
    int    timeIndex = 0,
    double dose      = 1.0,
    String unit      = 'mg',
  }) async {
    await _setAlertStage(medId, stage, timeIndex: timeIndex);
    debugPrint(
        '[NotificationService] Stage $stage fired for $medId (slot $timeIndex)');

    if (stage == 2) {
      // Auto-record 'skipped' only if not already marked by the patient.
      try {
        final existing = await IntakeService().getIntakeStatus(
          medId:     medId,
          timeIndex: timeIndex,
          date:      DateTime.now(),
        );
        if (existing == 'taken' || existing == 'taken_late') {
          debugPrint('[NotificationService] Dose already marked ($existing) '
              '— skipping auto-skip for $medId slot $timeIndex');
          return;
        }
        await IntakeService().recordIntake(
          medId:     medId,
          medName:   medName,
          status:    'skipped',
          timeIndex: timeIndex,
          date:      DateTime.now(),
        );
        debugPrint(
            '[NotificationService] Auto-skipped $medName (slot $timeIndex)');
      } catch (e) {
        debugPrint('[NotificationService] Auto-skip error: $e');
      }
    }
  }

  /// Called when the patient actively marks a dose as taken or taken_late.
  ///
  /// Cancels Stage 1 (+10 min) and Stage 2 (+20 min) one-shots for this slot
  /// so they don't fire after the patient has already acted.
  ///
  /// Stage 0 (daily repeat) is left running so next-day scheduling continues
  /// automatically. Stage 1 and Stage 2 will be re-created fresh by
  /// _scheduleAllStages() the next time the signature guard in
  /// _scheduleRemindersIfChanged() detects a new day's schedule.
  ///
  /// However, since Stage 1 and Stage 2 are one-shot alarms tied to TODAY'S
  /// base time, we need to re-schedule them for TOMORROW's base time right
  /// now — otherwise next day's +10/+20 min alarms won't exist.
  /// We do this by calling _scheduleAllStages() with the known hour/minute
  /// so it computes tomorrow as the next future base and creates fresh alarms.
  Future<void> cancelSlotStages(String medId, int timeIndex,
      {String medName = '',
      double dose = 1.0,
      String unit = 'mg',
      int hour = 8,
      int minute = 0,
      String period = 'AM'}) async {
    // Cancel only the one-shot stages (1 & 2). Stage 0 repeats and is managed
    // separately (cancelled by cancelPatientReminder when med is removed).
    await _plugin.cancel(_stageId(medId, 1, timeIndex));
    await _plugin.cancel(_stageId(medId, 2, timeIndex));

    debugPrint(
        '[NotificationService] Cancelled stages 1-2 for $medId slot $timeIndex');

    // Re-schedule all three stages for the next occurrence (tomorrow's base).
    // Stage 0 is already running as a daily repeat but we need fresh Stage 1
    // and Stage 2 one-shots pointing at tomorrow's base + 10/20 min.
    if (medName.isNotEmpty) {
      await _scheduleAllStages(
        medId:     medId,
        medName:   medName,
        dose:      dose,
        unit:      unit,
        hour:      hour,
        minute:    minute,
        period:    period,
        timeIndex: timeIndex,
      );
      debugPrint('[NotificationService] Rescheduled all stages for next occurrence '
          '$medId slot $timeIndex');
    }
  }

  // ── Legacy single-slot entry point (kept for callers that pass one time) ──

  /// Schedules all three alarm stages for a single intake-time slot.
  Future<void> schedulePatientReminder({
    required String medId,
    required String medName,
    required double dose,
    required String unit,
    required int    hour,
    required int    minute,
    required String period,
    int timeIndex = 0,
  }) async {
    await _scheduleAllStages(
      medId:     medId,
      medName:   medName,
      dose:      dose,
      unit:      unit,
      hour:      hour,
      minute:    minute,
      period:    period,
      timeIndex: timeIndex,
    );
  }

  /// Cancel all stages across every possible intake slot for a medication.
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

  // ── Caregiver notifications ────────────────────────────────────────────────

  Future<void> notifyCaregiverIntakeUpdate({
    required String   patientUid,
    required String   patientName,
    required String   medName,
    required String   status,
    required DateTime timestamp,
  }) async {
    await init();
    if (!await isCaregiverEnabled()) return;

    final label   = _statusLabel(status);
    final emoji   = _statusEmoji(status);
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

  // ── Helpers ────────────────────────────────────────────────────────────────

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