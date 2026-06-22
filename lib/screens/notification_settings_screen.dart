// lib/screens/notification_settings_screen.dart
//
// Notification & Alert Settings screen — shown to both Patient and Caregiver.
//
// Patient side:
//   • Toggle all medication reminders on / off
//   • Explains the three-stage alarm flow (matching patient_home.dart behaviour)
//     Stage 0 — First Reminder  → only "Taken" is active
//     Stage 1 — Follow-up (+10 min) → only "Taken Late" is active
//     Stage 2 — Final Alert (+20 min) → dose auto-recorded as Skipped;
//                                        "Taken Late" still available to correct
//
// Caregiver side:
//   • Toggle intake-update notifications on / off
//   • Explains that they get notified for Taken / Taken Late / Missed
//
// ── Exact alarm permission fix ───────────────────────────────────────────
//
// NotificationService already exposed isExactAlarmPermitted() and
// openExactAlarmSettings(), but this screen never called them, so a patient
// on Android 12+ who hadn't granted SCHEDULE_EXACT_ALARM had no way of
// knowing their reminders could silently fail. This screen now checks the
// permission on load and on app resume (in case the user grants it from
// system Settings and comes back), and shows a warning card with a button
// to jump straight to the relevant settings page when it's missing.
//
// UPDATED: "Snoozed" removed throughout. Step descriptions updated to reflect
// the stage-aware Mark-As sheet in patient_home.dart.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/accessibility_provider.dart';
import '../providers/caregiver_accessibility_provider.dart';
import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final bool isCaregiverMode;

  const NotificationSettingsScreen({
    super.key,
    this.isCaregiverMode = false,
  });

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> with WidgetsBindingObserver {
  final _svc = NotificationService();

  bool _enabled = true;
  bool _loading = true;

  // Exact-alarm permission (Android 12+ / API 31+). Irrelevant on iOS and on
  // older Android versions, where isExactAlarmPermitted() always reports true.
  bool _exactAlarmPermitted = true;
  bool _checkingExactAlarm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the user granting the permission in system Settings and then
    // returning to the app (Settings opens as a separate Activity, so this
    // screen merely pauses/resumes rather than being recreated).
    if (state == AppLifecycleState.resumed) {
      _checkExactAlarmPermission();
    }
  }

  Future<void> _load() async {
    final enabled = widget.isCaregiverMode
        ? await _svc.isCaregiverEnabled()
        : await _svc.isPatientEnabled();
    if (mounted) setState(() { _enabled = enabled; _loading = false; });
    if (!widget.isCaregiverMode) await _checkExactAlarmPermission();
  }

  /// Re-checks SCHEDULE_EXACT_ALARM status. Safe to call repeatedly (e.g. on
  /// resume after the user visits system Settings) since it just reads the
  /// current OS state.
  Future<void> _checkExactAlarmPermission() async {
    if (widget.isCaregiverMode) return;
    if (mounted) setState(() => _checkingExactAlarm = true);
    final permitted = await _svc.isExactAlarmPermitted();
    if (mounted) {
      setState(() {
        _exactAlarmPermitted = permitted;
        _checkingExactAlarm = false;
      });
    }
  }

  Future<void> _openExactAlarmSettings() async {
    await _svc.openExactAlarmSettings();
    // The user may grant the permission and return to the app — re-check
    // once they're back on this screen rather than leaving a stale
    // "not permitted" banner up indefinitely.
    if (mounted) await _checkExactAlarmPermission();
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      final granted = await _svc.requestPermission();
      if (!granted && mounted) { _showPermissionDenied(); return; }
    }
    if (widget.isCaregiverMode) {
      await _svc.setCaregiverEnabled(value);
    } else {
      await _svc.setPatientEnabled(value);
    }
    if (mounted) setState(() => _enabled = value);
    if (value && !widget.isCaregiverMode) await _checkExactAlarmPermission();
  }

  void _showPermissionDenied() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Permission Required'),
        content: const Text(
          'Notification permission was denied. '
          'Please enable it in your device Settings → App → PillBuddy → Notifications.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return widget.isCaregiverMode
        ? _buildWithCaregiverTheme()
        : _buildWithPatientTheme();
  }

  Widget _buildWithPatientTheme() {
    final acc  = context.watch<AccessibilityProvider>();
    final isDark = acc.themeMode == AppThemeMode.dark;
    final theme  = isDark ? acc.buildDarkTheme() : acc.buildLightTheme();
    final mq     = MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(acc.fontScaleFactor));

    return Theme(
      data: theme,
      child: MediaQuery(data: mq,
          child: Builder(builder: (ctx) => _buildContent(ctx))),
    );
  }

  Widget _buildWithCaregiverTheme() {
    final acc = context.watch<CaregiverAccessibilityProvider>();
    final mq  = MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(acc.fontScaleFactor));

    return Theme(
      data: acc.theme,
      child: MediaQuery(data: mq,
          child: Builder(builder: (ctx) => _buildContent(ctx))),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bgColor   = isDark ? const Color(0xFF121212) : const Color(0xFFF4F7FF);
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final onSurface = cs.onSurface;
    final accent    = widget.isCaregiverMode ? const Color(0xFF2BC8A7) : cs.primary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notification Settings',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: onSurface),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Master toggle ────────────────────────────────────────
                _SectionCard(
                  cardColor: cardColor,
                  isDark: isDark,
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.isCaregiverMode
                              ? Icons.notifications_active_outlined
                              : Icons.medication_outlined,
                          color: accent, size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isCaregiverMode
                                  ? 'Patient Intake Alerts'
                                  : 'Medication Reminders',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: onSurface),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.isCaregiverMode
                                  ? 'Get notified when a patient takes or misses a dose'
                                  : 'Receive alarms for each scheduled dose',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: onSurface.withValues(alpha: 0.5)),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        onChanged: _toggle,
                        activeColor: accent,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Exact alarm permission warning (patient only, Android 12+) ──
                //
                // NotificationService already exposes isExactAlarmPermitted()
                // and openExactAlarmSettings(); this surfaces that state to
                // the patient instead of letting alarms silently fail.
                if (!widget.isCaregiverMode &&
                    !_loading &&
                    !_checkingExactAlarm &&
                    !_exactAlarmPermitted) ...[
                  _ExactAlarmWarningCard(
                    cardColor: cardColor,
                    isDark: isDark,
                    onSurface: onSurface,
                    onFix: _openExactAlarmSettings,
                  ),
                  const SizedBox(height: 20),
                ],

                // ── How it works ─────────────────────────────────────────
                Text(
                  'HOW IT WORKS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 10),

                _SectionCard(
                  cardColor: cardColor,
                  isDark: isDark,
                  child: Column(
                    children: widget.isCaregiverMode
                        ? _caregiverSteps(onSurface)
                        : _patientSteps(onSurface),
                  ),
                ),

                const SizedBox(height: 20),

                // ── DND bypass note (patient only) ───────────────────────
                if (!widget.isCaregiverMode) ...[
                  _SectionCard(
                    cardColor: cardColor,
                    isDark: isDark,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.do_not_disturb_off_outlined,
                            color: accent, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bypasses Do Not Disturb',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: onSurface),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Medication alarms will ring even when your '
                                'phone is set to Do Not Disturb, ensuring you '
                                "never miss a dose.",
                                style: TextStyle(
                                    fontSize: 12,
                                    color: onSurface.withValues(alpha: 0.55),
                                    height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Info banner ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: accent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.isCaregiverMode
                              ? 'Notifications appear when you have the app '
                                'installed and are signed in. They are delivered '
                                'locally on your device.'
                              : 'Alarms are delivered locally on your device. '
                                'Make sure notification permission is granted '
                                'and the app is installed.',
                          style: TextStyle(
                              fontSize: 12, color: accent, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ── Step lists ─────────────────────────────────────────────────────────────

  List<Widget> _patientSteps(Color onSurface) {
    final steps = [
      _StepData(
        icon:     Icons.notifications_outlined,
        color:    const Color(0xFF1A6BFF),
        title:    'First Alarm (scheduled time)',
        subtitle: 'Alarm sounds with medicine name, dosage, and time. '
            'Only "Taken" is available to mark.',
      ),
      _StepData(
        icon:     Icons.access_time_outlined,
        color:    const Color(0xFFFFA726),
        title:    'Follow-Up Alarm (+10 min)',
        subtitle: 'A second alarm fires if the dose is still unmarked. '
            'Only "Taken Late" is available to mark.',
      ),
      _StepData(
        icon:     Icons.warning_amber_rounded,
        color:    const Color(0xFFEF5350),
        title:    'Final Alarm (+20 min)',
        subtitle: 'Dose is automatically recorded as Skipped. '
            'You may still correct it to "Taken Late" later that day.',
        isLast:   true,
      ),
    ];
    return steps.map((s) => _StepRow(data: s, onSurface: onSurface)).toList();
  }

  List<Widget> _caregiverSteps(Color onSurface) {
    final steps = [
      _StepData(
        icon:     Icons.check_circle_outline,
        color:    const Color(0xFF2BC8A7),
        title:    'Dose Taken / Taken Late',
        subtitle: 'You receive a notification when a patient marks a '
            'dose as Taken or Taken Late.',
      ),
      _StepData(
        icon:     Icons.cancel_outlined,
        color:    const Color(0xFFEF5350),
        title:    'Dose Missed',
        subtitle: 'You are alerted when a dose is recorded as Skipped '
            'or automatically marked as Missed after the final alarm.',
      ),
      _StepData(
        icon:     Icons.history_rounded,
        color:    const Color(0xFF3B71FE),
        title:    'Aligned with Intake Updates',
        subtitle: 'Every alert matches the Intake Updates timeline — '
            'both include a timestamp.',
        isLast:   true,
      ),
    ];
    return steps.map((s) => _StepRow(data: s, onSurface: onSurface)).toList();
  }
}

// ── Exact alarm permission warning ───────────────────────────────────────────
//
// Shown only on Android 12+ when SCHEDULE_EXACT_ALARM has not been granted.
// Without this permission, zonedSchedule(... exactAllowWhileIdle) silently
// degrades to an inexact alarm (or fails to fire at all on some OEM skins),
// so medication reminders can be late or missed without any visible error.
class _ExactAlarmWarningCard extends StatelessWidget {
  final Color cardColor;
  final bool isDark;
  final Color onSurface;
  final VoidCallback onFix;

  const _ExactAlarmWarningCard({
    required this.cardColor,
    required this.isDark,
    required this.onSurface,
    required this.onFix,
  });

  @override
  Widget build(BuildContext context) {
    const warningColor = Color(0xFFEF5350);
    return _SectionCard(
      cardColor: cardColor,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: warningColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.alarm_off_rounded,
                    color: warningColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exact Alarms Not Allowed',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your device is blocking precisely-timed alarms for '
                      'PillBuddy. Medication reminders may be delayed or '
                      'may not ring at all until this is allowed.',
                      style: TextStyle(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.55),
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onFix,
              style: ElevatedButton.styleFrom(
                backgroundColor: warningColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Allow Exact Alarms',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _StepData {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   subtitle;
  final bool     isLast;

  const _StepData({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });
}

class _StepRow extends StatelessWidget {
  final _StepData data;
  final Color     onSurface;
  const _StepRow({required this.data, required this.onSurface});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: data.isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: data.color, size: 20),
              ),
              if (!data.isLast)
                Container(
                  width: 2, height: 28,
                  color: data.color.withValues(alpha: 0.2),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: onSurface)),
                  const SizedBox(height: 3),
                  Text(data.subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.5),
                          height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final Color  cardColor;
  final bool   isDark;

  const _SectionCard({
    required this.child,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}