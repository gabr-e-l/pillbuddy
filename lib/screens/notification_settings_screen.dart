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
// UPDATED: Wraps content in the correct accessibility theme so that dark/HC
// mode, font scale, and button scale from AccessibilityProvider (patient) or
// CaregiverAccessibilityProvider (caregiver) are applied automatically.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/accessibility_provider.dart';
import '../providers/caregiver_accessibility_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = widget.isCaregiverMode
        ? await _svc.isCaregiverEnabled()
        : await _svc.isPatientEnabled();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool value) async {
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    if (widget.isCaregiverMode) {
      return _buildWithCaregiverTheme();
    } else {
      return _buildWithPatientTheme();
    }
  }

  Widget _buildWithPatientTheme() {
    final acc = context.watch<AccessibilityProvider>();
    final isDark = acc.themeMode == AppThemeMode.dark;
    final theme = isDark ? acc.buildDarkTheme() : acc.buildLightTheme();
    final mq = MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(acc.fontScaleFactor));

    return Theme(
      data: theme,
      child: MediaQuery(
        data: mq,
        child: Builder(builder: (ctx) => _buildContent(ctx)),
      ),
    );
  }

  Widget _buildWithCaregiverTheme() {
    final acc = context.watch<CaregiverAccessibilityProvider>();
    final mq = MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(acc.fontScaleFactor));

    return Theme(
      data: acc.theme,
      child: MediaQuery(
        data: mq,
        child: Builder(builder: (ctx) => _buildContent(ctx)),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF121212) : const Color(0xFFF4F7FF);
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final onSurface = cs.onSurface;

    // Accent: caregiver teal vs patient primary
    final accent = widget.isCaregiverMode ? const Color(0xFF2BC8A7) : cs.primary;

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
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: onSurface,
          ),
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.isCaregiverMode
                              ? Icons.notifications_active_outlined
                              : Icons.medication_outlined,
                          color: accent,
                          size: 24,
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
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.isCaregiverMode
                                  ? 'Get notified when a patient takes or misses a dose'
                                  : 'Receive reminders for each scheduled dose',
                              style: TextStyle(
                                fontSize: 12,
                                color: onSurface.withValues(alpha: 0.5),
                              ),
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

                // ── Info banner ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: accent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.isCaregiverMode
                              ? 'Notifications appear when you have the app installed '
                                'and are signed in. No internet connection is required '
                                'to receive them — they are delivered locally on your device.'
                              : 'Notifications are delivered locally on your device. '
                                'Make sure the app is installed and notification '
                                'permission is granted for reminders to work.',
                          style: TextStyle(
                            fontSize: 12,
                            color: accent,
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

  List<Widget> _patientSteps(Color onSurface) {
    final steps = [
      _StepData(
        icon: Icons.notifications_outlined,
        color: const Color(0xFF1A6BFF),
        title: 'First Reminder',
        subtitle:
            'Sent at the scheduled intake time with medicine name, dosage, and time.',
      ),
      _StepData(
        icon: Icons.snooze_outlined,
        color: const Color(0xFFFFA726),
        title: 'Snooze Alert (10 min later)',
        subtitle:
            "A follow-up reminder if the dose hasn't been marked yet.",
      ),
      _StepData(
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFEF5350),
        title: 'Final Alert (20 min later)',
        subtitle:
            'Last warning before the dose is automatically recorded as a Missed Dose with a timestamp.',
        isLast: true,
      ),
    ];
    return steps.map((s) => _StepRow(data: s, onSurface: onSurface)).toList();
  }

  List<Widget> _caregiverSteps(Color onSurface) {
    final steps = [
      _StepData(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF2BC8A7),
        title: 'Dose Taken',
        subtitle:
            'You receive a notification when a patient marks a dose as Taken or Taken Late.',
      ),
      _StepData(
        icon: Icons.cancel_outlined,
        color: const Color(0xFFEF5350),
        title: 'Dose Missed',
        subtitle:
            'You are alerted when a dose is recorded as Skipped or auto-marked as Missed.',
      ),
      _StepData(
        icon: Icons.history_rounded,
        color: const Color(0xFF3B71FE),
        title: 'Aligned with Intake Updates',
        subtitle:
            'Every alert matches the Intake Updates timeline — both include a timestamp.',
        isLast: true,
      ),
    ];
    return steps.map((s) => _StepRow(data: s, onSurface: onSurface)).toList();
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

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
  final Color onSurface;

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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: data.color, size: 20),
              ),
              if (!data.isLast)
                Container(
                  width: 2,
                  height: 28,
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
                  Text(
                    data.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    data.subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: onSurface.withValues(alpha: 0.5),
                        height: 1.4),
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
  final Color cardColor;
  final bool isDark;

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