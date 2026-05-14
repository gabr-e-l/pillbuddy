// lib/screens/caregiver_patient_meds_screen.dart
//
// Displays the patient's medication list. Caregivers can:
//   - Add a new medication
//   - Edit an existing medication (tap card or edit icon)
//   - Delete an existing medication

import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/caregiver_service.dart';
import 'caregiver_add_med_screen.dart';

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

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              patientName,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const Text(
              'Medications',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
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
                  color: const Color(0xFF2BC8A7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<MedicationModel>>(
        stream: service.patientMedicationsStream(patientUid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Error: ${snap.error}',
                  style: const TextStyle(color: Colors.redAccent)),
            );
          }

          final meds = snap.data ?? [];

          if (meds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.medication_outlined, size: 72, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text('No medications yet',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  Text('Add a medication for $patientName.',
                      style: const TextStyle(fontSize: 13, color: Colors.black38)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CaregiverAddMedScreen(
                          patientUid: patientUid,
                          patientName: patientName,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    label: const Text('Add Medication',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2BC8A7),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
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
  }
}

// ── Med card ──────────────────────────────────────────────────────────────────

class _MedCard extends StatelessWidget {
  final MedicationModel med;
  final String patientUid;
  final String patientName;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Medication'),
        content: Text('Are you sure you want to delete "${med.name}"?'),
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
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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

  Widget _buildMedIcon() {
    final imageUrl = med.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('data:')) {
        try {
          final base64Data = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(base64Data),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultIcon(),
            ),
          );
        } catch (_) {}
      }
    }
    return _defaultIcon();
  }

  Widget _defaultIcon() => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.medication_outlined,
            color: Color(0xFF2BC8A7), size: 26),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openEdit(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _buildMedIcon(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    med.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${med.dose} ${med.unit}  ·  ${med.type}',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_primaryTimeLabel()}  ·  ${_freqLabel()}',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  if (med.startingDate != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      _dateRangeLabel(),
                      style: const TextStyle(fontSize: 11, color: Colors.black38),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                // Edit button
                GestureDetector(
                  onTap: () => _openEdit(context),
                  child: const Icon(Icons.edit_outlined,
                      color: Color(0xFF2BC8A7), size: 20),
                ),
                const SizedBox(height: 10),
                // Delete button
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
    final h = (t?['hour'] as int? ?? med.hour).toString().padLeft(2, '0');
    final m = (t?['minute'] as int? ?? med.minute).toString().padLeft(2, '0');
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
          final sorted = List<int>.from(med.selectedMonthDays)..sort();
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