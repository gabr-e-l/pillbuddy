// lib/services/notification_service.dart
//
// Patient notification flow (three-stage alarm):
//
//   Stage 0 — First Reminder  (at scheduled time, repeats daily via matchDateTimeComponents)
//     • Sound: alarm_sound.wav, DND bypass, fullScreenIntent
//     • Only "Taken" is the active action in-app.
//
//   Stage 1 — Follow-Up Alarm (+10 min, ONE-SHOT — only if dose still unmarked)
//     • Pre-scheduled at the same time as Stage 0 (see "Why pre-schedule"
//       below) — NOT chained from onAlarmFired, since that callback only
//       fires when a notification is TAPPED, not when it's delivered.
//     • Same sound / channel.
//     • Only "Taken Late" is the active action in-app.
//
//   Stage 2 — Final Alarm (+20 min total, ONE-SHOT)
//     • Dose is automatically written to Firestore as 'skipped' ONLY IF it
//       hasn't already been marked 'taken' or 'taken_late'. (patient_home.dart
//       also independently auto-records 'skipped' purely from wall-clock time
//       once the window closes, so this happens even if the OS notification
//       itself was never tapped.)
//     • Patient may still change it to 'taken_late' later that day.
//
// Why one-shot for stages 1 & 2?
//   Using matchDateTimeComponents: DateTimeComponents.time for all three
//   stages caused two problems:
//     1. Cancellation unreliability — Android's AlarmManager sometimes fails
//        to cancel an exact repeating alarm that is actively firing.
//     2. Stage 1/2 would fire EVERY day, not just the day the dose was missed.
//   Scheduling stages 1 & 2 as one-shot alarms tied to the same base
//   occurrence as Stage 0 means they cancel reliably and automatically stop
//   firing once the patient marks the dose.
//
// ── Bug fix: Follow-Up (+10) and Final (+20) alarms silently disappearing ──
//
//   _scheduleAllStages() is re-invoked far more often than once: every time
//   the app cold-starts, _scheduleRemindersIfChanged()'s in-memory signature
//   guard resets to null, so it re-schedules on the very next Firestore
//   snapshot even though nothing about the medication changed. The OLD logic
//   computed the "next occurrence" of a dose's time-of-day by simply checking
//   "has today's wall-clock time already passed?" — and if so, rolled the
//   anchor straight to TOMORROW. That's correct for Stage 0 (which only cares
//   about time-of-day via matchDateTimeComponents), but it was also being
//   used as the anchor for Stage 1 (+10) and Stage 2 (+20), which are
//   absolute one-shot alarms. The result: re-opening the app at any point
//   after the scheduled time — even 1 minute after, i.e. while today's
//   Follow-Up/Final window was still legitimately running — rolled the Stage
//   1/2 anchor to tomorrow and silently overwrote today's still-pending
//   Follow-Up and Final one-shots with tomorrow's times. Today's alarms then
//   simply never fired.
//
//   Fix: the anchor only rolls to tomorrow once today's full 20-minute alarm
//   window (scheduled time → scheduled time + 20 min) has actually elapsed.
//   Re-invoking this method while inside that window now recomputes the SAME
//   today's Stage 1/2 times (idempotent), instead of clobbering them. Each
//   stage is additionally only (re)scheduled if its target time is still in
//   the future, so a re-invocation mid-window can't accidentally re-fire a
//   stage whose moment has already passed.
//
//   The one exception is cancelSlotStages() (called the moment the patient
//   marks a dose taken/taken_late): there we WANT to jump straight to
//   tomorrow's occurrence regardless of whether today's window has elapsed,
//   since today's dose is already resolved. That call passes
//   forceNextDay: true to bypass the window check.
//
//   This fix applies per intake-time slot independently, so it also covers
//   medications with multiple intake times per day (each slot gets its own
//   correctly-anchored Stage 0/1/2 trio).
//
// Alert stage is persisted in SharedPreferences as
//   notif_stage_{medId}_{timeIndex} → 0 | 1 | 2
// via onAlarmFired(), but that only updates when a notification is TAPPED.
// patient_home.dart therefore also derives an equivalent stage purely from
// wall-clock time and takes the max of the two, so the Mark-As sheet shows
// the right buttons even if the patient never taps the alarm.

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
  ///
  /// [forceNextDay] — when true, skips the "is today's window still open"
  /// check and anchors straight to tomorrow's occurrence. Used exclusively by
  /// cancelSlotStages() right after the patient marks a dose, since at that
  /// point today's dose is resolved and we explicitly want tomorrow's alarms
  /// queued up. All other callers should leave this false so that
  /// re-invoking this method while today's 20-minute window is still open
  /// (e.g. on app cold start) recomputes the SAME today's Stage 1/2 times
  /// instead of clobbering them with tomorrow's.
  Future<void> _scheduleAllStages({
    required String medId,
    required String medName,
    required double dose,
    required String unit,
    required int    hour,
    required int    minute,
    required String period,
    int  timeIndex = 0,
    bool forceNextDay = false,
  }) async {
    await init();
    if (!await isPatientEnabled()) return;

    final h24 = hour % 12 + (period == 'PM' ? 12 : 0);
    final now = tz.TZDateTime.now(tz.local);
    final todayBase =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, h24, minute);

    // Stage 0's anchor: unchanged from the original (already-working) logic
    // — always the next future occurrence of the time-of-day. This is only
    // used as a seed for matchDateTimeComponents.time (a daily repeat), so
    // it must stay in the future; the plugin resolves the actual next match
    // from it regardless of which date we pass.
    final stage0Base =
        todayBase.isBefore(now) ? todayBase.add(const Duration(days: 1)) : todayBase;

    // Stage 1/2's anchor: anchor to TODAY as long as today's full 20-minute
    // alarm window (scheduled time → scheduled time + 20 min) hasn't elapsed
    // yet — see the file-header "Bug fix" note for why this matters. Once
    // that window has closed (or when explicitly forced via [forceNextDay]),
    // roll forward to tomorrow's occurrence instead.
    final todayWindowEnd = todayBase.add(const Duration(minutes: 20));
    final rollToTomorrow = forceNextDay || now.isAfter(todayWindowEnd);
    final base = rollToTomorrow
        ? todayBase.add(const Duration(days: 1))
        : todayBase;

    // ── Bug fix: Stage 1/2 firing even after the dose was already marked ──
    //
    //   _scheduleAllStages() can be re-invoked while still anchored to TODAY
    //   (rollToTomorrow == false) for reasons that have nothing to do with
    //   today's dose actually being unresolved — most notably, app cold
    //   start resets patient_home's in-memory signature guard, so this
    //   method runs again even though the patient already marked today's
    //   dose as 'taken' a moment (or hours) earlier, well inside today's
    //   20-minute window. Without this check, that re-invocation would
    //   blindly re-schedule fresh Stage 1 (+10) and Stage 2 (+20) one-shots
    //   for today, undoing the cancellation cancelSlotStages() already
    //   performed when the dose was marked.
    //
    //   Fix: whenever we're anchored to TODAY, check Firestore first. If
    //   today's slot is already 'taken' or 'taken_late', skip scheduling
    //   Stage 1/2 entirely for today — only Stage 0 (the daily repeat,
    //   already-idempotent) gets (re)scheduled. We don't need to do this
    //   check when rollToTomorrow is true, since tomorrow's dose can't have
    //   been marked yet.
    bool alreadyResolvedToday = false;
    if (!rollToTomorrow) {
      try {
        final existing = await IntakeService().getIntakeStatus(
          medId:     medId,
          timeIndex: timeIndex,
          date:      DateTime.now(),
        );
        alreadyResolvedToday = existing == 'taken' || existing == 'taken_late';
      } catch (e) {
        debugPrint('[NotificationService] Pre-schedule status check failed '
            'for $medId slot $timeIndex: $e');
      }
      if (alreadyResolvedToday) {
        // Defensive: make sure no stale one-shots are left pending for
        // today even if a prior cancellation somehow missed them.
        await _plugin.cancel(_stageId(medId, 1, timeIndex));
        await _plugin.cancel(_stageId(medId, 2, timeIndex));
        debugPrint('[NotificationService] $medId slot $timeIndex already '
            'resolved today — skipping Stage 1/2 (re)scheduling.');
      }
    }

    final timeLabel =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    final doseLabel = '${dose % 1 == 0 ? dose.toInt() : dose} $unit';

    // ── Stage 0: daily repeating alarm ───────────────────────────────────
    await _plugin.zonedSchedule(
      _stageId(medId, 0, timeIndex),
      '💊 Time for $medName',
      '$doseLabel — scheduled at $timeLabel',
      stage0Base,
      await _alarmDetails(stage: 0, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeats daily
      payload: 'stage:0:$medId:$timeIndex:${dose.toString()}:$unit',
    );

    // ── Stage 1: one-shot +10 min ─────────────────────────────────────────
    // [base] (the window-aware anchor, see above) stays pinned to TODAY for
    // as long as today's 20-minute window is still open, so re-invoking this
    // method mid-window (e.g. app re-opened after the alarm already fired)
    // recomputes the SAME today's stage1Time instead of pushing it to
    // tomorrow. We additionally only actually (re)schedule it if the target
    // is still in the future — if stage1Time has already passed (we're
    // currently inside the +10..+20 min window), there's nothing useful to
    // (re)schedule; it already fired (or should have) and we must not
    // re-trigger it or throw scheduling a past time.
    final stage1Time = base.add(const Duration(minutes: 10));
    if (!alreadyResolvedToday && stage1Time.isAfter(now)) {
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
    } else {
      debugPrint('[NotificationService] Stage 1 target for $medId slot '
          '$timeIndex already passed ($stage1Time) — leaving as-is, not '
          're-scheduling.');
    }

    // ── Stage 2: one-shot +20 min ─────────────────────────────────────────
    // Same future-only guard as Stage 1 above.
    final stage2Time = base.add(const Duration(minutes: 20));
    if (!alreadyResolvedToday && stage2Time.isAfter(now)) {
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
    } else {
      debugPrint('[NotificationService] Stage 2 target for $medId slot '
          '$timeIndex already passed ($stage2Time) — leaving as-is, not '
          're-scheduling.');
    }

    // Only reset the persisted alert stage when we're actually anchoring to
    // a FRESH occurrence (tomorrow, or an explicit force). If we're simply
    // re-invoked mid-window while still anchored to today, resetting here
    // would wipe out a tap-recorded stage (from onAlarmFired) even though
    // the dose's alarm cycle for today hasn't actually restarted.
    if (rollToTomorrow) {
      await resetAlertStage(medId, timeIndex: timeIndex);
    }

    debugPrint('[NotificationService] Stages scheduled for $medName '
        '(slot $timeIndex) — base=$base, stage1=$stage1Time, '
        'stage2=$stage2Time, forceNextDay=$forceNextDay');
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
  /// automatically. Stage 1 and Stage 2 are re-created fresh here, anchored
  /// explicitly to TOMORROW's occurrence via forceNextDay: true — since the
  /// patient just resolved today's dose, we always want the next cycle
  /// queued up for tomorrow regardless of how much of today's 20-minute
  /// window has elapsed (which is what _scheduleAllStages would otherwise
  /// use to decide whether to stay anchored to today).
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
        medId:        medId,
        medName:      medName,
        dose:         dose,
        unit:         unit,
        hour:         hour,
        minute:       minute,
        period:       period,
        timeIndex:    timeIndex,
        forceNextDay: true,
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