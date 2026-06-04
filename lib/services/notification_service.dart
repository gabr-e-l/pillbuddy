// lib/services/notification_service.dart
//
// Patient notification flow (three-stage alarm):
//
//   Stage 0 — First Reminder  (at scheduled time)
//     • Sound: alarm_sound.wav (30 s), DND bypass, fullScreenIntent
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

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'intake_service.dart'; // needed to auto-record 'skipped' at final alert

class NotificationService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

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

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // ── Alarm channel — max importance + alarm audio attributes ──────────
    // audioAttributesUsage: AudioAttributesUsage.alarm is the correct way
    // to request DND bypass in flutter_local_notifications v18.x.
    // (bypassDnd was added in a later release and is not available in v18.0.1.)
    // Combined with category: AndroidNotificationCategory.alarm on each
    // individual notification, Android treats these as alarms and will
    // ring through Do Not Disturb on most devices.
    const alarmChannel = AndroidNotificationChannel(
      _alarmChannelId,
      'Medication Alarms',
      description: 'Urgent alerts for scheduled medication doses',
      importance: Importance.max,
      playSound: true,
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

  // Called when the user taps the notification itself (not an action button).
  // We just use this to advance the stage tracking if needed in future.
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
    }
    if (ios != null) {
      final result = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = result ?? false;
    }
    return granted;
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

  /// Returns the current notification stage for [medId]:
  ///   0 = first reminder not yet fired (or reset)
  ///   1 = snooze alert fired (10 min past)
  ///   2 = final alert fired (20 min past) — dose auto-skipped
  Future<int> getAlertStage(String medId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_stagePrefix$medId') ?? 0;
  }

  Future<void> _setAlertStage(String medId, int stage) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_stagePrefix$medId', stage);
  }

  Future<void> resetAlertStage(String medId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_stagePrefix$medId');
  }

  // ── Notification details helpers ──────────────────────────────────────────

  /// High-priority alarm notification that bypasses DND.
  /// Uses alarm_sound.wav from res/raw.
  NotificationDetails _alarmDetails({
    required int stage,
    required String medName,
  }) {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _alarmChannelId,
        'Medication Alarms',
        channelDescription: 'Urgent alerts for scheduled medication doses',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
        sound: RawResourceAndroidNotificationSound('alarm_sound'),
        playSound: true,
        enableVibration: true,
        // Bypass DND at the notification level as well
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'alarm_sound.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  NotificationDetails _caregiverDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _caregiverChannelId,
        'Patient Intake Updates',
        channelDescription: 'Notifications when a patient marks a dose',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  // ── ID helpers ────────────────────────────────────────────────────────────

  int _stageId(String medId, int stage) =>
      ((stage + 1) * 1000000) + medId.hashCode.abs() % 999000;

  int _caregiverId(String patientUid, String medId) =>
      4000000 + (patientUid + medId).hashCode.abs() % 999000;

  // ── Patient: schedule all three alarms for one medication ────────────────

  /// Schedules three daily alarms (repeating via matchDateTimeComponents.time):
  ///   • Stage 0 — at [hour]:[minute]
  ///   • Stage 1 — +10 min  (snooze prompt)
  ///   • Stage 2 — +20 min  (final, then auto-skips)
  Future<void> schedulePatientReminder({
    required String medId,
    required String medName,
    required double dose,
    required String unit,
    required int hour,    // 1-12
    required int minute,
    required String period, // 'AM' | 'PM'
  }) async {
    await init();
    if (!await isPatientEnabled()) return;

    // Convert 12 h → 24 h
    final h24 = hour % 12 + (period == 'PM' ? 12 : 0);

    final now = tz.TZDateTime.now(tz.local);
    var base = tz.TZDateTime(tz.local, now.year, now.month, now.day, h24, minute);
    if (base.isBefore(now)) base = base.add(const Duration(days: 1));

    final timeLabel =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    final doseLabel = '${dose % 1 == 0 ? dose.toInt() : dose} $unit';

    // Stage 0 — First Reminder
    await _plugin.zonedSchedule(
      _stageId(medId, 0),
      '💊 Time for $medName',
      '$doseLabel — scheduled at $timeLabel',
      base,
      _alarmDetails(stage: 0, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'stage:0:$medId',
    );

    // Stage 1 — Snooze Alert (+10 min)
    await _plugin.zonedSchedule(
      _stageId(medId, 1),
      '⏰ Reminder: $medName',
      "You haven't marked $medName as taken yet.",
      base.add(const Duration(minutes: 10)),
      _alarmDetails(stage: 1, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'stage:1:$medId',
    );

    // Stage 2 — Final Alert (+20 min)
    await _plugin.zonedSchedule(
      _stageId(medId, 2),
      '⚠️ Final Alert: $medName',
      '$medName ($doseLabel) has been recorded as a missed dose.',
      base.add(const Duration(minutes: 20)),
      _alarmDetails(stage: 2, medName: medName),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'stage:2:$medId',
    );

    // Reset stage counter so the UI shows "Taken" as active until first alarm.
    await resetAlertStage(medId);

    debugPrint(
        '[NotificationService] Scheduled 3-stage alarms for $medName at $timeLabel');
  }

  /// Called by patient_home.dart when each notification fires (via a
  /// background isolate handler or when the app is foregrounded).
  /// Updates stage tracking and auto-records 'skipped' at stage 2.
  Future<void> onAlarmFired({
    required String medId,
    required String medName,
    required int stage,
  }) async {
    await _setAlertStage(medId, stage);
    debugPrint('[NotificationService] Stage $stage fired for $medId');

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

  /// Cancel all three alarm slots for a given medication.
  Future<void> cancelPatientReminder(String medId) async {
    for (int s = 0; s < 3; s++) {
      await _plugin.cancel(_stageId(medId, s));
    }
    await resetAlertStage(medId);
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
      _caregiverDetails(),
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