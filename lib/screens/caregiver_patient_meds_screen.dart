// lib/screens/caregiver_patient_meds_screen.dart
//
// UPDATED: Uses CaregiverThemeWrapper — no manual font multipliers needed
// inside (MediaQuery textScaler handles it). Dark/HC colours come from
// the theme's ColorScheme.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medication_model.dart';
import '../providers/caregiver_accessibility_provider.dart';
import '../services/caregiver_service.dart';
import 'caregiver_add_med_screen.dart';
import 'caregiver_intake_history_screen.dart';
import 'caregiver_theme_wrapper.dart';

class CaregiverPatientMedsScreen extends StatelessWidget {
  final String patientUid;
  final String patientName;

  const CaregiverPatientMedsScreen({
    super.key,
    required this.patientUid,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    final service = CaregiverService();

    return CaregiverThemeWrapper(
      builder: (ctx, acc) {
        final cs      = Theme.of(ctx).colorScheme;
        final isDark  = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark
            ? const Color(0xFF121212)
            : const Color(0xFFF4F7FF);

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios,
                  size: 20, color: cs.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              children: [
                Text(
                  patientName,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface),
                ),
                Text(
                  'Medications',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.45)),
                ),
              ],
            ),
            centerTitle: true,
            actions: [
              // Intake updates
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: 'Intake Updates',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CaregiverIntakeHistoryScreen(
                        patientUid: patientUid,
                        patientName: patientName,
                      ),
                    ),
                  ),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B71FE)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.history_rounded,
                        color: Color(0xFF3B71FE), size: 20),
                  ),
                ),
              ),
              // Add med
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CaregiverAddMedScreen(
                        patientUid: patientUid,
                        patientName: patientName,
                      ),
                    ),
                  ),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
          body: StreamBuilder<List<MedicationModel>>(
            stream: service.patientMedicationsStream(patientUid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                    child:
                        CircularProgressIndicator(color: cs.primary));
              }
              if (snap.hasError) {
                return Center(
                  child: Text('Error: ${snap.error}',
                      style:
                          const TextStyle(color: Colors.redAccent)),
                );
              }

              final meds = snap.data ?? [];

              if (meds.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medication_outlined,
                          size: 72,
                          color:
                              cs.onSurface.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      Text('No medications yet',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface
                                  .withValues(alpha: 0.5))),
                      const SizedBox(height: 8),
                      Text('Add a medication for $patientName.',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface
                                  .withValues(alpha: 0.35))),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48.0 * acc.buttonScaleFactor,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CaregiverAddMedScreen(
                                patientUid: patientUid,
                                patientName: patientName,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.add,
                              color: Colors.white, size: 18),
                          label: const Text('Add Medication',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(20)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: meds.length,
                itemBuilder: (context, i) {
                  final med = meds[i];
                  return _MedCard(
                    med: med,
                    patientUid: patientUid,
                    patientName: patientName,
                    service: service,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ── Med card ──────────────────────────────────────────────────────────────────

class _MedCard extends StatelessWidget {
  final MedicationModel  med;
  final String           patientUid;
  final String           patientName;
  final CaregiverService service;

  const _MedCard({
    required this.med,
    required this.patientUid,
    required this.patientName,
    required this.service,
  });

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Medication'),
        content:
            Text('Are you sure you want to delete "${med.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await service.deleteMedication(patientUid, med.id!);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openEdit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaregiverAddMedScreen(
          patientUid: patientUid,
          patientName: patientName,
          existingMed: med,
        ),
      ),
    );
  }

  Widget _buildMedIcon(ColorScheme cs) {
    final imageUrl = med.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('data:')) {
        try {
          final b64 = imageUrl.contains(',')
              ? imageUrl.split(',').last
              : imageUrl;
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(b64),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultIcon(cs),
            ),
          );
        } catch (_) {}
      }
    }
    return _defaultIcon(cs);
  }

  Widget _defaultIcon(ColorScheme cs) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.medication_outlined,
            color: cs.primary, size: 26),
      );

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return GestureDetector(
      onTap: () => _openEdit(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
            _buildMedIcon(cs),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    med.name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${med.dose} ${med.unit}  ·  ${med.type}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.45)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_primaryTimeLabel()}  ·  ${_freqLabel()}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.45)),
                  ),
                  if (med.startingDate != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      _dateRangeLabel(),
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface
                              .withValues(alpha: 0.35)),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                GestureDetector(
                  onTap: () => _openEdit(context),
                  child: Icon(Icons.edit_outlined,
                      color: cs.primary, size: 20),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _confirmDelete(context),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.redAccent, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _primaryTimeLabel() {
    final t = med.intakeTimes.isNotEmpty ? med.intakeTimes.first : null;
    final h = (t?['hour'] as int? ?? med.hour)
        .toString()
        .padLeft(2, '0');
    final m = (t?['minute'] as int? ?? med.minute)
        .toString()
        .padLeft(2, '0');
    final p = t?['period'] as String? ?? med.period;
    return '$h:$m $p';
  }

  String _freqLabel() {
    switch (med.freqUnit) {
      case 'Hour':
        return 'Every ${med.freqNumber}h';
      case 'Day':
        return '${med.freqNumber}× / day';
      case 'Week':
        if (med.selectedWeekDays.isNotEmpty) {
          const short = {
            1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu',
            5: 'Fri', 6: 'Sat', 7: 'Sun',
          };
          final sorted = List<int>.from(med.selectedWeekDays)..sort();
          return sorted.map((d) => short[d]).join(', ');
        }
        return '${med.freqNumber}× / week';
      case 'Month':
        if (med.selectedMonthDays.isNotEmpty) {
          final sorted =
              List<int>.from(med.selectedMonthDays)..sort();
          return 'Day ${sorted.join(', ')} of month';
        }
        return '${med.freqNumber}× / month';
      default:
        return '${med.freqNumber}× / ${med.freqUnit}';
    }
  }

  String _dateRangeLabel() {
    String s = '';
    if (med.startingDate != null) {
      final d = med.startingDate!;
      s += 'From ${d.day}/${d.month}/${d.year}';
    }
    if (med.stopDate != null) {
      final d = med.stopDate!;
      s += '  –  ${d.day}/${d.month}/${d.year}';
    }
    return s;
  }
}