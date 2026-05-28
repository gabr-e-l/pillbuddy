// lib/services/notification_service.dart
//
// Handles all local notification scheduling for PillBuddy.
//
// Patient side:
//   • First reminder  — at the scheduled intake time
//   • Snooze reminder — 10 min after the first reminder
//   • Final alert     — 20 min after the first reminder (then saved as "Missed")
//
// Caregiver side:
//   • Intake update   — fired when the patient marks a dose taken / missed
//
// Uses flutter_local_notifications only (no Firebase Cloud Messaging / Cloud
// Functions), so it is fully compatible with the Firebase Spark free plan.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const _keyPatientEnabled  = 'notif_patient_enabled';
  static const _keyCaregiverEnabled = 'notif_caregiver_enabled';

  // ── Notification channel IDs ───────────────────────────────────────────────
  static const _patientChannelId   = 'pillbuddy_patient_reminders';
  static const _caregiverChannelId = 'pillbuddy_caregiver_updates';

  // ── Notification ID ranges ─────────────────────────────────────────────────
  // Patient first reminder:  1_000_000 + med hash
  // Patient snooze:          2_000_000 + med hash
  // Patient final alert:     3_000_000 + med hash
  // Caregiver intake update: 4_000_000 + (patientUid hash + medId hash)

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

    await _plugin.initialize(settings);

    // Create notification channels (Android 8+)
    const patientChannel = AndroidNotificationChannel(
      _patientChannelId,
      'Medication Reminders',
      description: 'Alerts for scheduled medication doses',
      importance: Importance.high,
    );
    const caregiverChannel = AndroidNotificationChannel(
      _caregiverChannelId,
      'Patient Intake Updates',
      description: 'Notifications when a patient marks a dose',
      importance: Importance.defaultImportance,
    );

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(patientChannel);
    await androidPlugin?.createNotificationChannel(caregiverChannel);

    _initialized = true;
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

  // ── Notification details helpers ──────────────────────────────────────────

  NotificationDetails _patientDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _patientChannelId,
        'Medication Reminders',
        channelDescription: 'Alerts for scheduled medication doses',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
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

  int _patientFirstId(String medId)  => (1000000 + medId.hashCode.abs() % 999000);
  int _patientSnoozeId(String medId) => (2000000 + medId.hashCode.abs() % 999000);
  int _patientFinalId(String medId)  => (3000000 + medId.hashCode.abs() % 999000);
  int _caregiverId(String patientUid, String medId) =>
      (4000000 + (patientUid + medId).hashCode.abs() % 999000);

  // ── Patient: schedule reminders for one medication ────────────────────────

  /// Call this whenever the patient's medication list changes.
  /// Schedules three notifications per active medication (today & beyond):
  ///   • First reminder at scheduled time
  ///   • Snooze prompt 10 min later
  ///   • Missed-dose final alert 20 min later
  Future<void> schedulePatientReminder({
    required String medId,
    required String medName,
    required double dose,
    required String unit,
    required int hour,   // 1–12
    required int minute,
    required String period, // 'AM' | 'PM'
  }) async {
    await init();
    if (!await isPatientEnabled()) return;

    // Convert 12h → 24h
    int h24 = hour % 12 + (period == 'PM' ? 12 : 0);

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year, now.month, now.day,
      h24, minute,
    );
    // If the time already passed today, schedule for tomorrow
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final timeLabel =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    final doseLabel = '${dose % 1 == 0 ? dose.toInt() : dose} $unit';

    // 1. First reminder
    await _plugin.zonedSchedule(
      _patientFirstId(medId),
      '💊 Time for $medName',
      '$doseLabel — scheduled at $timeLabel',
      scheduled,
      _patientDetails(),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // 2. Snooze reminder (+10 min)
    await _plugin.zonedSchedule(
      _patientSnoozeId(medId),
      '⏰ Reminder: $medName',
      'You haven\'t marked $medName as taken yet.',
      scheduled.add(const Duration(minutes: 10)),
      _patientDetails(),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // 3. Final alert (+20 min)
    await _plugin.zonedSchedule(
      _patientFinalId(medId),
      '⚠️ Missed Dose: $medName',
      '$medName ($doseLabel) was not marked as taken. It will be recorded as a missed dose.',
      scheduled.add(const Duration(minutes: 20)),
      _patientDetails(),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    debugPrint('[NotificationService] Scheduled reminders for $medName at $timeLabel');
  }

  /// Cancel all three reminder slots for a given medication.
  Future<void> cancelPatientReminder(String medId) async {
    await _plugin.cancel(_patientFirstId(medId));
    await _plugin.cancel(_patientSnoozeId(medId));
    await _plugin.cancel(_patientFinalId(medId));
  }

  Future<void> cancelAllPatientReminders() async {
    // Cancel IDs in ranges 1M–3.999M
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.id >= 1000000 && n.id < 4000000) {
        await _plugin.cancel(n.id);
      }
    }
  }

  // ── Caregiver: fire an immediate notification ─────────────────────────────

  /// Call this when IntakeService.recordIntake() completes on the patient side,
  /// or from the caregiver side when it detects a new intake record.
  Future<void> notifyCaregiverIntakeUpdate({
    required String patientUid,
    required String patientName,
    required String medName,
    required String status,    // 'taken' | 'taken_late' | 'skipped' | 'snoozed'
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

    debugPrint('[NotificationService] Caregiver notified: $patientName $medName $status');
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
      case 'snoozed':    return 'Snoozed';
      default:           return status;
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'taken':      return '✅';
      case 'taken_late': return '🕐';
      case 'skipped':    return '❌';
      case 'snoozed':    return '💤';
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
