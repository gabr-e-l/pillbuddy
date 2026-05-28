// lib/screens/notification_settings_screen.dart
//
// Notification & Alert Settings screen — shown to both Patient and Caregiver.
//
// Patient side:
//   • Toggle all medication reminders on / off
//   • Explains the three-alert flow (first reminder → snooze → final/missed)
//
// Caregiver side:
//   • Toggle intake-update notifications on / off
//   • Explains that they get notified when a patient marks taken / missed
//
// No Firebase Cloud Functions or Blaze plan features are used.
// All notifications are local (flutter_local_notifications).

import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  /// Pass true when opened from the caregiver side.
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
    extends State<NotificationSettingsScreen> {
  final _svc = NotificationService();

  bool _enabled = true;
  bool _loading = true;

  // Colour palette — matches each side's accent
  Color get _accent =>
      widget.isCaregiverMode ? const Color(0xFF2BC8A7) : const Color(0xFF1A6BFF);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = widget.isCaregiverMode
        ? await _svc.isCaregiverEnabled()
        : await _svc.isPatientEnabled();
    if (mounted) setState(() { _enabled = enabled; _loading = false; });
  }

  Future<void> _toggle(bool value) async {
    // Ask for permission first when enabling
    if (value) {
      final granted = await _svc.requestPermission();
      if (!granted && mounted) {
        _showPermissionDenied();
        return;
      }
    }

    if (widget.isCaregiverMode) {
      await _svc.setCaregiverEnabled(value);
    } else {
      await _svc.setPatientEnabled(value);
    }
    if (mounted) setState(() => _enabled = value);
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
    final theme = Theme.of(context);
    final isCaregiver = widget.isCaregiverMode;

    return Scaffold(
      backgroundColor: isCaregiver
          ? const Color(0xFFF4F7FF)
          : theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            isCaregiver ? const Color(0xFFF4F7FF) : theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 20,
              color: isCaregiver ? Colors.black87 : theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notification Settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isCaregiver ? Colors.black87 : theme.colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Master toggle ──────────────────────────────────────────
                _SectionCard(
                  isCaregiver: isCaregiver,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isCaregiver
                              ? Icons.notifications_active_outlined
                              : Icons.medication_outlined,
                          color: _accent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isCaregiver
                                  ? 'Patient Intake Alerts'
                                  : 'Medication Reminders',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isCaregiver
                                    ? Colors.black87
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isCaregiver
                                  ? 'Get notified when a patient takes or misses a dose'
                                  : 'Receive reminders for each scheduled dose',
                              style: TextStyle(
                                fontSize: 12,
                                color: isCaregiver
                                    ? Colors.black45
                                    : theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enabled,
                        onChanged: _toggle,
                        activeColor: _accent,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── How it works ──────────────────────────────────────────
                Text(
                  'HOW IT WORKS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isCaregiver ? Colors.black38 : theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 10),

                _SectionCard(
                  isCaregiver: isCaregiver,
                  child: Column(
                    children: isCaregiver
                        ? _caregiverSteps(theme)
                        : _patientSteps(theme),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Info banner ───────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _accent.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: _accent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isCaregiver
                              ? 'Notifications appear when you have the app installed '
                                'and are signed in. No internet connection is required '
                                'to receive them — they are delivered locally on your device.'
                              : 'Notifications are delivered locally on your device. '
                                'Make sure the app is installed and notification '
                                'permission is granted for reminders to work.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _accent,
                            height: 1.5,
                          ),
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

  List<Widget> _patientSteps(ThemeData theme) {
    final steps = [
      _StepData(
        icon: Icons.notifications_outlined,
        color: const Color(0xFF1A6BFF),
        title: 'First Reminder',
        subtitle: 'Sent at the scheduled intake time with medicine name, dosage, and time.',
      ),
      _StepData(
        icon: Icons.snooze_outlined,
        color: const Color(0xFFFFA726),
        title: 'Snooze Alert (10 min later)',
        subtitle: 'A follow-up reminder if the dose hasn\'t been marked yet.',
      ),
      _StepData(
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFEF5350),
        title: 'Final Alert (20 min later)',
        subtitle: 'Last warning before the dose is automatically recorded as a Missed Dose with a timestamp.',
        isLast: true,
      ),
    ];
    return steps.map((s) => _StepRow(data: s, theme: theme)).toList();
  }

  List<Widget> _caregiverSteps(ThemeData theme) {
    final steps = [
      _StepData(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF2BC8A7),
        title: 'Dose Taken',
        subtitle: 'You receive a notification when a patient marks a dose as Taken or Taken Late.',
      ),
      _StepData(
        icon: Icons.cancel_outlined,
        color: const Color(0xFFEF5350),
        title: 'Dose Missed',
        subtitle: 'You are alerted when a dose is recorded as Skipped or auto-marked as Missed.',
      ),
      _StepData(
        icon: Icons.history_rounded,
        color: const Color(0xFF3B71FE),
        title: 'Aligned with Intake Updates',
        subtitle: 'Every alert matches the Intake Updates timeline — both include a timestamp.',
        isLast: true,
      ),
    ];
    return steps.map((s) => _StepRow(data: s, theme: theme, isCaregiver: true)).toList();
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _StepData {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool isLast;

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
  final ThemeData theme;
  final bool isCaregiver;

  const _StepRow({
    required this.data,
    required this.theme,
    this.isCaregiver = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isCaregiver ? Colors.black87 : theme.colorScheme.onSurface;
    final subtitleColor = isCaregiver
        ? Colors.black45
        : theme.colorScheme.onSurface.withOpacity(0.5);

    return Padding(
      padding: EdgeInsets.only(bottom: data.isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: data.color, size: 20),
              ),
              if (!data.isLast)
                Container(
                  width: 2,
                  height: 28,
                  color: data.color.withOpacity(0.2),
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
                  Text(
                    data.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.subtitle,
                    style: TextStyle(fontSize: 12, color: subtitleColor, height: 1.4),
                  ),
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
  final bool isCaregiver;

  const _SectionCard({required this.child, required this.isCaregiver});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCaregiver ? Colors.white : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
