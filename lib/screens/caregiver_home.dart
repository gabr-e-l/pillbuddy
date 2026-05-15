// lib/screens/caregiver_home.dart
//
// The Caregiver's home screen. Caregivers can:
//   - See all linked patients
//   - Add a patient by email
//   - Tap a patient to manage their medications (add / edit / delete)
//   - View patient adherence summary (taken / skipped counts for today)
//   - Sign out from Settings tab

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication_model.dart';
import '../services/caregiver_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import 'add_patient_screen.dart';
import 'caregiver_patient_meds_screen.dart';
import 'caregiver_intake_history_screen.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';

class CaregiverHome extends StatefulWidget {
  const CaregiverHome({super.key});

  @override
  State<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends State<CaregiverHome> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _PatientsTab(),
          _CaregiverSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF2BC8A7),
        unselectedItemColor: Colors.grey[400],
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Patients',
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

// ── Patients tab ──────────────────────────────────────────────────────────────

class _PatientsTab extends StatelessWidget {
  final _service = CaregiverService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : 'Caregiver';

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hello, $name 👋',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Your patients',
                        style: TextStyle(fontSize: 14, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Add patient button
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AddPatientScreen()),
                  ),
                  icon: const Icon(Icons.person_add_outlined,
                      size: 18, color: Colors.white),
                  label: const Text(
                    'Add Patient',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2BC8A7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Patient list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.patientsStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error loading patients.\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }

                final patients = snap.data ?? [];

                if (patients.isEmpty) {
                  return _buildEmptyState(context);
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: patients.length,
                  itemBuilder: (context, i) =>
                      _PatientCard(patient: patients[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No patients yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap "Add Patient" to link\nyour first patient.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black38),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AddPatientScreen()),
            ),
            icon: const Icon(Icons.person_add_outlined, color: Colors.white),
            label: const Text(
              'Add Patient',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2BC8A7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Patient card ──────────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;
  final _service = CaregiverService();

  _PatientCard({required this.patient});

  void _confirmUnlink(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Patient'),
        content: Text(
            'Remove ${patient['name']} from your patient list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.unlinkPatient(patient['uid'] as String);
            },
            child: const Text('Remove',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientUid = patient['uid'] as String;
    final patientName = (patient['name'] as String?)?.isNotEmpty == true
        ? patient['name'] as String
        : 'Patient';
    final email = patient['email'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CaregiverPatientMedsScreen(
            patientUid: patientUid,
            patientName: patientName,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 26,
              backgroundColor:
                  const Color(0xFF2BC8A7).withOpacity(0.15),
              child: Text(
                patientName.isNotEmpty
                    ? patientName[0].toUpperCase()
                    : 'P',
                style: const TextStyle(
                  color: Color(0xFF2BC8A7),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patientName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 6),
                  // Med count badge
                  StreamBuilder<List<MedicationModel>>(
                    stream:
                        _service.patientMedicationsStream(patientUid),
                    builder: (ctx, snap) {
                      final count = snap.data?.length ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count medication${count == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // Intake Updates quick-link
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CaregiverIntakeHistoryScreen(
                          patientUid: patientUid,
                          patientName: patientName,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B71FE).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded,
                              size: 13, color: Color(0xFF3B71FE)),
                          SizedBox(width: 4),
                          Text(
                            'Intake Updates',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF3B71FE),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Column(
              children: [
                const Icon(Icons.chevron_right,
                    color: Colors.black38, size: 22),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _confirmUnlink(context),
                  child: const Icon(Icons.link_off,
                      color: Colors.redAccent, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Caregiver settings tab ────────────────────────────────────────────────────

class _CaregiverSettingsTab extends StatelessWidget {
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
                    : user?.displayName ?? 'Caregiver';
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
                    avatarWidget = CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF2BC8A7).withOpacity(0.15),
                      child: const Icon(Icons.medical_services_outlined,
                          color: Color(0xFF2BC8A7), size: 28),
                    );
                  }
                } else {
                  avatarWidget = CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF2BC8A7).withOpacity(0.15),
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                      style: const TextStyle(
                          color: Color(0xFF2BC8A7),
                          fontWeight: FontWeight.bold,
                          fontSize: 22),
                    ),
                  );
                }

                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfileSettingsScreen(isCaregiverMode: true),
                    ),
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
                            color: const Color(0xFF2BC8A7).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Caregiver',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF2BC8A7),
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

            // Edit Profile
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileSettingsScreen(isCaregiverMode: true),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.person_outline, color: Color(0xFF2BC8A7), size: 22),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Edit Profile',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.black38, size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Sign out
            GestureDetector(
              onTap: () => _signOut(context),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 22),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Sign Out',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: Colors.red),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.redAccent, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}