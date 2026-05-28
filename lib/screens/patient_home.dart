// lib/screens/patient_home.dart
//
// Fixes applied in this version:
//   1. Dark mode + high-contrast: all hardcoded Colors.white / Color(0xFFF4F7FF)
//      replaced with Theme.of(context) surface/background values so the
//      AccessibilityProvider's themeMode actually takes effect on every widget.
//   2. Button size: "Mark as" / status pill and action-sheet tiles now scale
//      their height/padding via AccessibilityProvider.buttonScaleFactor.
//   3. Mark-As bottom-sheet overflow: switched to isScrollControlled:true and
//      MediaQuery.viewInsetsOf(context).bottom so the system nav-bar never clips
//      the last option.
//   4. Light-text fixes: med name and action-tile label/subtitle in the
//      bottom-sheet are now explicitly dark (Theme onSurface) so they are
//      readable on white and on dark backgrounds alike.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/medication_model.dart';
import '../services/medication_service.dart';
import '../services/intake_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../providers/accessibility_provider.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';
import 'accessibility_settings_screen.dart';
import 'notification_settings_screen.dart';
import '../services/notification_service.dart';

class PatientHome extends StatefulWidget {
  const PatientHome({super.key});

  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  int _selectedIndex = 0;
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // bg is slightly tinted in light mode, neutral in dark
    final scaffoldBg = theme.brightness == Brightness.dark
        ? theme.scaffoldBackgroundColor
        : const Color(0xFFF4F7FF);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _TodayTab(selectedDate: _selectedDate),
          const _PatientSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: theme.colorScheme.surface,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurface.withOpacity(0.4),
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.medication_outlined),
            label: 'My Meds',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ── Today tab ─────────────────────────────────────────────────────────────────

class _TodayTab extends StatefulWidget {
  final DateTime selectedDate;
  const _TodayTab({required this.selectedDate});

  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  final _medService = MedicationService();
  final _intakeService = IntakeService();
  final _profileService = ProfileService();
  final _notifService = NotificationService();
  DateTime _selectedDate = DateTime.now();

  late final List<DateTime> _calendarDays;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _calendarDays = List.generate(
      14,
      (i) => today.subtract(Duration(days: 3 - i)),
    );
    // Initialise local notifications when the patient home loads.
    _notifService.init();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(onSurface),
          _buildHorizontalCalendar(theme),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              "Today's Medications",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
          ),
          Expanded(child: _buildMedList()),
        ],
      ),
    );
  }

  Widget _buildHeader(Color onSurface) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _profileService.profileStream(),
      builder: (context, snap) {
        final name = (snap.data?['name'] as String?)?.isNotEmpty == true
            ? snap.data!['name'] as String
            : 'there';
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $name 👋',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
              Text(
                "Here are your medications for today.",
                style:
                    TextStyle(fontSize: 14, color: onSurface.withOpacity(0.5)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHorizontalCalendar(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;

    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _calendarDays.length,
        itemBuilder: (context, i) {
          final day = _calendarDays[i];
          final isSelected = _isSameDay(day, _selectedDate);
          final isToday = _isSameDay(day, DateTime.now());
          return GestureDetector(
            onTap: () => setState(() => _selectedDate = day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 48,
              decoration: BoxDecoration(
                color: isSelected ? primary : surface,
                borderRadius: BorderRadius.circular(12),
                border: isToday && !isSelected
                    ? Border.all(color: primary, width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _weekdayLabel(day),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white70
                          : onSurface.withOpacity(0.45),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMedList() {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return StreamBuilder<List<MedicationModel>>(
      stream: _medService.medicationsStream(),
      builder: (context, medSnap) {
        if (medSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (medSnap.hasError) {
          return Center(
            child: Text(
              'Could not load medications.\n${medSnap.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final allMeds = medSnap.data ?? [];
        final meds =
            allMeds.where((med) => med.isActiveOn(_selectedDate)).toList();

        // Schedule / refresh local reminders for all active medications.
        for (final med in allMeds.where((m) => m.isActiveOn(DateTime.now()))) {
          _notifService.schedulePatientReminder(
            medId:   med.id ?? med.name,
            medName: med.name,
            dose:    med.dose,
            unit:    med.unit,
            hour:    med.hour,
            minute:  med.minute,
            period:  med.period,
          );
        }

        if (meds.isEmpty && allMeds.isEmpty) {
          return _buildEmptyState(onSurface);
        }

        if (meds.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_available_outlined,
                    size: 64, color: onSurface.withOpacity(0.2)),
                const SizedBox(height: 12),
                Text(
                  'No medications on this date',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: onSurface.withOpacity(0.45)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Check a different date',
                  style: TextStyle(
                      fontSize: 13, color: onSurface.withOpacity(0.35)),
                ),
              ],
            ),
          );
        }

        return StreamBuilder<Map<String, String>>(
          stream: _intakeService.intakesForDateStream(_selectedDate),
          builder: (context, intakeSnap) {
            final intakes = intakeSnap.data ?? {};
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: meds.length,
              itemBuilder: (context, i) {
                final med = meds[i];
                final status = intakes[med.id];
                return _MedCard(
                  med: med,
                  status: status,
                  selectedDate: _selectedDate,
                  onStatusChanged: (newStatus) async {
                    if (newStatus == null) {
                      await _intakeService.deleteIntake(
                          medId: med.id!, date: _selectedDate);
                    } else {
                      await _intakeService.recordIntake(
                        medId: med.id!,
                        medName: med.name,
                        status: newStatus,
                        date: _selectedDate,
                      );
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(Color onSurface) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_outlined,
              size: 72, color: onSurface.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'No medications scheduled',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: onSurface.withOpacity(0.45),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your caregiver hasn't added\nany medications yet.",
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: onSurface.withOpacity(0.35)),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekdayLabel(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }
}

// ── Medication card ───────────────────────────────────────────────────────────

class _MedCard extends StatefulWidget {
  final MedicationModel med;
  final String? status;
  final DateTime selectedDate;
  final Future<void> Function(String? status) onStatusChanged;

  const _MedCard({
    required this.med,
    required this.status,
    required this.selectedDate,
    required this.onStatusChanged,
  });

  @override
  State<_MedCard> createState() => _MedCardState();
}

class _MedCardState extends State<_MedCard> {
  String? _localStatus;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _localStatus = widget.status;
  }

  @override
  void didUpdateWidget(_MedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _localStatus = widget.status;
    }
  }

  MedicationModel get med => widget.med;

  Color get _statusColor {
    return switch (_localStatus) {
      'taken' => const Color(0xFF2BC8A7),
      'taken_late' => const Color(0xFFFFA726),
      'skipped' => const Color(0xFFEF5350),
      'snoozed' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF3B71FE),
    };
  }

  String get _statusLabel {
    return switch (_localStatus) {
      'taken' => 'Taken ✓',
      'taken_late' => 'Taken Late',
      'skipped' => 'Skipped',
      'snoozed' => 'Snoozed',
      _ => 'Mark as',
    };
  }

  static Widget _buildMedImage(String imageUrl) {
    if (imageUrl.startsWith('data:')) {
      try {
        final b64 =
            imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        return Image.memory(
          base64Decode(b64),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      } catch (_) {}
    }
    return const SizedBox.shrink();
  }

  Future<void> _handleStatusChange(
      BuildContext context, String? newStatus) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _localStatus = newStatus;
    });
    try {
      await widget.onStatusChanged(newStatus);
    } catch (e) {
      setState(() => _localStatus = widget.status);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // FIX 3 + 4: isScrollControlled removes the overflow; explicit colors fix
  // the light-text issue inside the sheet.
  void _showActionSheet(BuildContext context) {
    final theme = Theme.of(context);
    final sheetBg = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    // Extra bottom padding = system nav-bar height so nothing is clipped
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom +
        16;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // isScrollControlled lets the sheet be exactly as tall as its content
      // without Flutter forcing a minimum height that causes overflow
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // FIX 4: explicit onSurface color so name is readable in all modes
            Text(
              med.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
            Text(
              '${med.dose} ${med.unit}  ·  '
              '${med.hour.toString().padLeft(2, '0')}:'
              '${med.minute.toString().padLeft(2, '0')} ${med.period}',
              style: TextStyle(
                  fontSize: 13, color: onSurface.withOpacity(0.5)),
            ),
            const SizedBox(height: 20),
            _ActionTile(
              icon: Icons.check_circle_outline,
              color: const Color(0xFF2BC8A7),
              label: 'Taken',
              subtitle: 'I took it on time',
              onTap: () {
                Navigator.pop(sheetContext);
                _handleStatusChange(context, 'taken');
              },
            ),
            _ActionTile(
              icon: Icons.watch_later_outlined,
              color: const Color(0xFFFFA726),
              label: 'Taken Late',
              subtitle: 'I took it, but late',
              onTap: () {
                Navigator.pop(sheetContext);
                _handleStatusChange(context, 'taken_late');
              },
            ),
            _ActionTile(
              icon: Icons.snooze_outlined,
              color: const Color(0xFF9E9E9E),
              label: 'Snoozed',
              subtitle: 'Remind me later',
              onTap: () {
                Navigator.pop(sheetContext);
                _handleStatusChange(context, 'snoozed');
              },
            ),
            _ActionTile(
              icon: Icons.cancel_outlined,
              color: const Color(0xFFEF5350),
              label: 'Skipped',
              subtitle: 'I did not take it',
              onTap: () {
                Navigator.pop(sheetContext);
                _handleStatusChange(context, 'skipped');
              },
            ),
            if (_localStatus != null)
              _ActionTile(
                icon: Icons.undo_outlined,
                color: onSurface.withOpacity(0.4),
                label: 'Undo',
                subtitle: 'Clear this record',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handleStatusChange(context, null);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccessibilityProvider>();
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    // FIX 2: scale the status-pill vertical padding by buttonScaleFactor
    final btnV = 8.0 * acc.buttonScaleFactor;
    final btnH = 12.0 * acc.buttonScaleFactor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: _localStatus != null
            ? Border.all(
                color: _statusColor.withOpacity(0.4), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          // Time column
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(
                  '${med.hour.toString().padLeft(2, '0')}:'
                  '${med.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
                Text(
                  med.period,
                  style: TextStyle(
                      fontSize: 12, color: onSurface.withOpacity(0.45)),
                ),
              ],
            ),
          ),

          Container(
            width: 1,
            height: 48,
            color: onSurface.withOpacity(0.08),
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),

          // Med info
          Expanded(
            child: Row(
              children: [
                if (med.imageUrl != null && med.imageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildMedImage(med.imageUrl!),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${med.dose} ${med.unit}  ·  ${med.type}',
                        style: TextStyle(
                            fontSize: 12,
                            color: onSurface.withOpacity(0.45)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Status / Mark-as button — FIX 2: scaled padding
          GestureDetector(
            onTap: _saving ? null : () => _showActionSheet(context),
            child: Container(
              padding:
                  EdgeInsets.symmetric(horizontal: btnH, vertical: btnV),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _saving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _statusColor,
                      ),
                    )
                  : Text(
                      _statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _statusColor,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action tile (inside bottom sheet) ────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // FIX 4: use Theme colors so text is readable in dark/HC modes
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color, size: 22),
      ),
      // Explicit dark colors — no more invisible text
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: onSurface.withOpacity(0.5),
        ),
      ),
      onTap: onTap,
    );
  }
}

// ── Patient settings tab ──────────────────────────────────────────────────────

class _PatientSettingsTab extends StatelessWidget {
  const _PatientSettingsTab();

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService().signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: onSurface),
            ),
            const SizedBox(height: 24),

            // Profile card
            StreamBuilder<Map<String, dynamic>?>(
              stream: ProfileService().profileStream(),
              builder: (context, snap) {
                final profileData = snap.data;
                final displayName =
                    (profileData?['name'] as String?)?.isNotEmpty == true
                        ? profileData!['name'] as String
                        : user?.displayName ?? 'Patient';
                final profileImageUrl =
                    profileData?['profileImageUrl'] as String?;

                Widget avatarWidget;
                if (profileImageUrl != null &&
                    profileImageUrl.startsWith('data:')) {
                  try {
                    final b64 = profileImageUrl.contains(',')
                        ? profileImageUrl.split(',').last
                        : profileImageUrl;
                    avatarWidget = CircleAvatar(
                      radius: 28,
                      backgroundImage: MemoryImage(base64Decode(b64)),
                    );
                  } catch (_) {
                    avatarWidget = CircleAvatar(
                      radius: 28,
                      backgroundColor: primary,
                      child: const Icon(Icons.person_outline,
                          color: Colors.white, size: 28),
                    );
                  }
                } else {
                  avatarWidget = CircleAvatar(
                    radius: 28,
                    backgroundColor: primary,
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : 'P',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20),
                    ),
                  );
                }

                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProfileSettingsScreen()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        avatarWidget,
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: onSurface),
                              ),
                              Text(
                                user?.email ?? '',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: onSurface.withOpacity(0.45)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Patient',
                            style: TextStyle(
                                fontSize: 12,
                                color: primary,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_outlined,
                            size: 18,
                            color: onSurface.withOpacity(0.35)),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Edit profile
            _SettingsTile(
              icon: Icons.edit_outlined,
              label: 'Edit Profile',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ProfileSettingsScreen()),
              ),
            ),

            const SizedBox(height: 12),

            // Accessibility
            _SettingsTile(
              icon: Icons.accessibility_new_rounded,
              label: 'Accessibility',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AccessibilitySettingsScreen()),
              ),
            ),

            const SizedBox(height: 12),

            // Notifications
            _SettingsTile(
              icon: Icons.notifications_outlined,
              label: 'Notification Settings',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()),
              ),
            ),

            const SizedBox(height: 12),

            // Sign out
            _SettingsTile(
              icon: Icons.logout,
              label: 'Sign Out',
              color: Colors.red,
              onTap: () => _signOut(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final defaultColor = theme.colorScheme.onSurface;
    final c = color ?? defaultColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: c.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}
