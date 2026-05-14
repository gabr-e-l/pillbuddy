// lib/screens/patient_home.dart
//
// The Patient's home screen. Patients:
//   - View today's medications (set by their linked caregiver)
//   - Mark each dose as Taken, Taken Late, Snoozed, or Skipped
//   - Cannot add / edit / delete medications
//   - Can view their profile and sign out from Settings

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication_model.dart';
import '../services/medication_service.dart';
import '../services/intake_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _TodayTab(selectedDate: _selectedDate),
          _PatientSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF3B71FE),
        unselectedItemColor: Colors.grey[400],
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
  DateTime _selectedDate = DateTime.now();

  // Horizontal calendar — show 7 days centred on today
  late final List<DateTime> _calendarDays;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _calendarDays = List.generate(
      14,
      (i) => today.subtract(Duration(days: 3 - i)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildHorizontalCalendar(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              "Today's Medications",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(child: _buildMedList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Text(
                "Here are your medications for today.",
                style: TextStyle(fontSize: 14, color: Colors.black45),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHorizontalCalendar() {
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
                color: isSelected
                    ? const Color(0xFF3B71FE)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: isToday && !isSelected
                    ? Border.all(color: const Color(0xFF3B71FE), width: 1.5)
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
                      color: isSelected ? Colors.white70 : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black87,
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

        // Filter meds active on selectedDate (respects startDate, stopDate,
        // selectedWeekDays, and selectedMonthDays via isActiveOn)
        final meds = allMeds
            .where((med) => med.isActiveOn(_selectedDate))
            .toList();

        if (meds.isEmpty && allMeds.isEmpty) {
          return _buildEmptyState();
        }

        if (meds.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_available_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 12),
                const Text(
                  'No medications on this date',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black45),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Check a different date',
                  style: TextStyle(fontSize: 13, color: Colors.black38),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_outlined, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No medications scheduled',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your caregiver hasn\'t added\nany medications yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black38),
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
  final String? status; // null = not yet acted on
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
        final b64 = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        return Image.memory(
          base64Decode(b64),
          width: 40, height: 40, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      } catch (_) {}
    }
    return const SizedBox.shrink();
  }

  Future<void> _handleStatusChange(BuildContext context, String? newStatus) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _localStatus = newStatus; // optimistic update
    });
    try {
      await widget.onStatusChanged(newStatus);
    } catch (e) {
      // Revert optimistic update on failure
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

  void _showActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              med.name,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${med.dose} ${med.unit}  ·  '
              '${med.hour.toString().padLeft(2, '0')}:'
              '${med.minute.toString().padLeft(2, '0')} ${med.period}',
              style: const TextStyle(fontSize: 13, color: Colors.black45),
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
                color: Colors.black38,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: _localStatus != null
            ? Border.all(color: _statusColor.withOpacity(0.4), width: 1.5)
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  med.period,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),

          Container(
            width: 1,
            height: 48,
            color: Colors.grey[200],
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${med.dose} ${med.unit}  ·  ${med.type}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Status button
          GestureDetector(
            onTap: _saving ? null : () => _showActionSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label,
          style:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.black45)),
      onTap: onTap,
    );
  }
}

// ── Patient settings tab ──────────────────────────────────────────────────────

class _PatientSettingsTab extends StatelessWidget {
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Profile card
            StreamBuilder<Map<String, dynamic>?>(
              stream: ProfileService().profileStream(),
              builder: (context, snap) {
                final profileData = snap.data;
                final displayName = (profileData?['name'] as String?)?.isNotEmpty == true
                    ? profileData!['name'] as String
                    : user?.displayName ?? 'Patient';
                final profileImageUrl = profileData?['profileImageUrl'] as String?;

                Widget avatarWidget;
                if (profileImageUrl != null && profileImageUrl.startsWith('data:')) {
                  try {
                    final b64 = profileImageUrl.contains(',')
                        ? profileImageUrl.split(',').last
                        : profileImageUrl;
                    avatarWidget = CircleAvatar(
                      radius: 28,
                      backgroundImage: MemoryImage(base64Decode(b64)),
                    );
                  } catch (_) {
                    avatarWidget = const CircleAvatar(
                      radius: 28,
                      backgroundColor: Color(0xFF3B71FE),
                      child: Icon(Icons.person_outline, color: Colors.white, size: 28),
                    );
                  }
                } else {
                  avatarWidget = CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF3B71FE),
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
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
                      color: Colors.white,
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
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                user?.email ?? '',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black45),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Patient',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF3B71FE),
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit_outlined,
                            size: 18, color: Colors.black38),
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
    final c = color ?? Colors.black87;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
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