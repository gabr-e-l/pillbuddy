// lib/screens/patient_home.dart
//
// The Patient's home screen. Patients:
//   - View today's medications (set by their linked caregiver)
//   - Mark each dose as Taken, Taken Late, Snoozed, or Skipped
//   - Cannot add / edit / delete medications
//   - Can view their profile and sign out from Settings

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

        final meds = medSnap.data ?? [];

        if (meds.isEmpty) {
          return _buildEmptyState();
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

class _MedCard extends StatelessWidget {
  final MedicationModel med;
  final String? status; // null = not yet acted on
  final DateTime selectedDate;
  final void Function(String? status) onStatusChanged;

  const _MedCard({
    required this.med,
    required this.status,
    required this.selectedDate,
    required this.onStatusChanged,
  });

  Color get _statusColor {
    return switch (status) {
      'taken' => const Color(0xFF2BC8A7),
      'taken_late' => const Color(0xFFFFA726),
      'skipped' => const Color(0xFFEF5350),
      'snoozed' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF3B71FE),
    };
  }

  String get _statusLabel {
    return switch (status) {
      'taken' => 'Taken ✓',
      'taken_late' => 'Taken Late',
      'skipped' => 'Skipped',
      'snoozed' => 'Snoozed',
      _ => 'Mark as',
    };
  }

  void _showActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
                Navigator.pop(context);
                onStatusChanged('taken');
              },
            ),
            _ActionTile(
              icon: Icons.watch_later_outlined,
              color: const Color(0xFFFFA726),
              label: 'Taken Late',
              subtitle: 'I took it, but late',
              onTap: () {
                Navigator.pop(context);
                onStatusChanged('taken_late');
              },
            ),
            _ActionTile(
              icon: Icons.snooze_outlined,
              color: const Color(0xFF9E9E9E),
              label: 'Snoozed',
              subtitle: 'Remind me later',
              onTap: () {
                Navigator.pop(context);
                onStatusChanged('snoozed');
              },
            ),
            _ActionTile(
              icon: Icons.cancel_outlined,
              color: const Color(0xFFEF5350),
              label: 'Skipped',
              subtitle: 'I did not take it',
              onTap: () {
                Navigator.pop(context);
                onStatusChanged('skipped');
              },
            ),
            if (status != null)
              _ActionTile(
                icon: Icons.undo_outlined,
                color: Colors.black38,
                label: 'Undo',
                subtitle: 'Clear this record',
                onTap: () {
                  Navigator.pop(context);
                  onStatusChanged(null);
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
        border: status != null
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

          // Status button
          GestureDetector(
            onTap: () => _showActionSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFF3B71FE),
                    child: Icon(Icons.person_outline,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Patient',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
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