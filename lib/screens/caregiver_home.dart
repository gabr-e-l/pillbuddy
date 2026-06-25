// lib/screens/caregiver_home.dart
//
// UPDATED:
//   - Uses CaregiverThemeWrapper (no inline Theme+MediaQuery boilerplate).
//   - Text sizes are NOT manually multiplied by fontScaleFactor — the
//     MediaQuery textScaler in the wrapper already handles that.
//   - Button heights are scaled via buttonScaleFactor.
//   - All colours come from the theme's ColorScheme so dark/HC mode works.

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/medication_model.dart';
import '../providers/caregiver_accessibility_provider.dart';
import '../services/caregiver_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/notification_service.dart';
import '../services/caregiver_intake_cache.dart';
import 'add_patient_screen.dart';
import 'caregiver_patient_meds_screen.dart';
import 'caregiver_intake_history_screen.dart';
import 'caregiver_accessibility_settings_screen.dart';
import 'caregiver_theme_wrapper.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';
import 'notification_settings_screen.dart';

class CaregiverHome extends StatefulWidget {
  const CaregiverHome({super.key});

  @override
  State<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends State<CaregiverHome> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return CaregiverThemeWrapper(
      builder: (ctx, acc) {
        final cs     = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF4F7FF);
        final navBg   = isDark ? const Color(0xFF1E1E2E) : Colors.white;

        return Scaffold(
          backgroundColor: bgColor,
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              _PatientsTab(),
              const _CaregiverSettingsTab(),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
            backgroundColor: navBg,
            selectedItemColor: cs.primary,
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
      },
    );
  }
}

// ── Patients tab ──────────────────────────────────────────────────────────────

class _PatientsTab extends StatelessWidget {
  final _service = CaregiverService();

  @override
  Widget build(BuildContext context) {
    final acc  = context.watch<CaregiverAccessibilityProvider>();
    final cs   = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : 'Caregiver';

    final btnH = 40.0 * acc.buttonScaleFactor;

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
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Your patients',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: btnH,
                  child: ElevatedButton.icon(
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
                      backgroundColor: cs.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.patientsStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                      child:
                          CircularProgressIndicator(color: cs.primary));
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
                  return _buildEmptyState(context, acc, cs);
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

  Widget _buildEmptyState(BuildContext context,
      CaregiverAccessibilityProvider acc, ColorScheme cs) {
    final btnH = 48.0 * acc.buttonScaleFactor;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline,
              size: 72, color: cs.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'No patients yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Patient" to link\nyour first patient.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.35)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: btnH,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AddPatientScreen()),
              ),
              icon: const Icon(Icons.person_add_outlined,
                  color: Colors.white),
              label: const Text('Add Patient',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Patient card ──────────────────────────────────────────────────────────────

class _PatientCard extends StatefulWidget {
  final Map<String, dynamic> patient;
  const _PatientCard({required this.patient});

  @override
  State<_PatientCard> createState() => _PatientCardState();
}

class _PatientCardState extends State<_PatientCard> {
  final _service      = CaregiverService();
  final _notifService = NotificationService();

  @override
  void initState() {
    super.initState();
    _notifService.init();
  }

  void _confirmUnlink(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Patient'),
        content: Text(
            'Remove ${widget.patient['name']} from your patient list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _service
                  .unlinkPatient(widget.patient['uid'] as String);
            },
            child: const Text('Remove',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleIntakeUpdate(
    Map<String, String> newIntakes,
    String patientUid,
    String patientName, {
    Map<String, String> medNames = const {},
    required String date,
  }) async {
    final cache = CaregiverIntakeCache.instance;
    for (final entry in newIntakes.entries) {
      final medId  = entry.key;
      final status = entry.value;
      if (status == 'taken' ||
          status == 'taken_late' ||
          status == 'skipped') {
        // shouldNotify() checks the singleton cache (backed by
        // SharedPreferences) and returns true only when the status is
        // genuinely new — survives navigation, rebuilds AND cold restarts.
        final notify = await cache.shouldNotify(
          patientUid: patientUid,
          medId:      medId,
          date:       date,
          status:     status,
        );
        if (notify) {
          _notifService.notifyCaregiverIntakeUpdate(
            patientUid:  patientUid,
            patientName: patientName,
            medName:     medNames[medId] ?? medId,
            status:      status,
            timestamp:   DateTime.now(),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc     = context.watch<CaregiverAccessibilityProvider>();
    final cs      = Theme.of(context).colorScheme;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    final patientUid  = widget.patient['uid'] as String;
    final patientName =
        (widget.patient['name'] as String?)?.isNotEmpty == true
            ? widget.patient['name'] as String
            : 'Patient';
    final email = widget.patient['email'] as String? ?? '';

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
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 26,
              backgroundColor: cs.primary.withValues(alpha: 0.15),
              child: Text(
                patientName.isNotEmpty
                    ? patientName[0].toUpperCase()
                    : 'P',
                style: TextStyle(
                  color: cs.primary,
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            cs.onSurface.withValues(alpha: 0.45)),
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
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count medication${count == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                cs.onSurface.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // Silent intake notification listener
                  Builder(builder: (context) {
                    final n      = DateTime.now();
                    final today  = '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(patientUid)
                          .collection('intakes')
                          .where('date', isEqualTo: today)
                          .snapshots()
                          .map((s) =>
                              s.docs.map((d) => d.data()).toList()),
                      builder: (context, intakeSnap) {
                        if (intakeSnap.hasData) {
                          final docs      = intakeSnap.data!;
                          final statusMap = <String, String>{
                            for (final d in docs)
                              if (d['medId'] != null &&
                                  d['status'] != null)
                                d['medId'] as String:
                                    d['status'] as String,
                          };
                          final nameMap = <String, String>{
                            for (final d in docs)
                              if (d['medId'] != null &&
                                  d['medName'] != null)
                                d['medId'] as String:
                                    d['medName'] as String,
                          };
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) {
                            if (mounted) {
                              _handleIntakeUpdate(
                                statusMap,
                                patientUid,
                                patientName,
                                medNames: nameMap,
                                date: today,
                              );
                            }
                          });
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  }),
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
                        color: const Color(0xFF3B71FE)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.history_rounded,
                              size: 13, color: Color(0xFF3B71FE)),
                          const SizedBox(width: 4),
                          Text(
                            'Intake Updates',
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFF3B71FE),
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
                Icon(Icons.chevron_right,
                    color: cs.onSurface.withValues(alpha: 0.3),
                    size: 22),
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
  const _CaregiverSettingsTab();

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
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

  Widget _tile({
    required BuildContext context,
    required CaregiverAccessibilityProvider acc,
    required ColorScheme cs,
    required Color iconColor,
    required IconData icon,
    required String label,
    Color? labelColor,
    required VoidCallback onTap,
  }) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final tileH = 56.0 * acc.buttonScaleFactor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: tileH),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: labelColor ?? cs.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: (labelColor ?? cs.onSurface).withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acc    = context.watch<CaregiverAccessibilityProvider>();
    final cs     = Theme.of(context).colorScheme;
    final user   = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 24),

            // ── Profile card ───────────────────────────────────────────
            StreamBuilder<Map<String, dynamic>?>(
              stream: ProfileService().profileStream(),
              builder: (context, snap) {
                final profileData = snap.data;
                final displayName =
                    (profileData?['name'] as String?)?.isNotEmpty == true
                        ? profileData!['name'] as String
                        : user?.displayName ?? 'Caregiver';
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
                    avatarWidget = _defaultAvatar(displayName, cs);
                  }
                } else {
                  avatarWidget = _defaultAvatar(displayName, cs);
                }

                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfileSettingsScreen(
                          isCaregiverMode: true),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                              alpha: isDark ? 0.25 : 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        avatarWidget,
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                user?.email ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Caregiver',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_outlined,
                            size: 18,
                            color: cs.onSurface
                                .withValues(alpha: 0.35)),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            _tile(
              context: context,
              acc: acc,
              cs: cs,
              iconColor: cs.primary,
              icon: Icons.person_outline,
              label: 'Edit Profile',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileSettingsScreen(
                      isCaregiverMode: true),
                ),
              ),
            ),

            const SizedBox(height: 12),

            _tile(
              context: context,
              acc: acc,
              cs: cs,
              iconColor: cs.primary,
              icon: Icons.notifications_outlined,
              label: 'Notification Settings',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(
                      isCaregiverMode: true),
                ),
              ),
            ),

            const SizedBox(height: 12),

            _tile(
              context: context,
              acc: acc,
              cs: cs,
              iconColor: cs.primary,
              icon: Icons.accessibility_new_rounded,
              label: 'Accessibility',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const CaregiverAccessibilitySettingsScreen(),
                ),
              ),
            ),

            const SizedBox(height: 12),

            _tile(
              context: context,
              acc: acc,
              cs: cs,
              iconColor: Colors.red,
              icon: Icons.logout,
              label: 'Sign Out',
              labelColor: Colors.red,
              onTap: () => _signOut(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultAvatar(String displayName, ColorScheme cs) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: cs.primary.withValues(alpha: 0.15),
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
        style: TextStyle(
            color: cs.primary, fontWeight: FontWeight.bold, fontSize: 22),
      ),
    );
  }
}