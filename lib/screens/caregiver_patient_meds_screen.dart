// lib/screens/caregiver_patient_meds_screen.dart
//
// Shown when a caregiver taps a patient card in CaregiverHome.
// Displays the patient's medication list and allows the caregiver to:
//   - Add a new medication for the patient
//   - Delete an existing medication
//   - Tap a med to edit it (via CaregiverMedEditScreen)

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
          icon: const Icon(Icons.arrow_back_ios,
              size: 20, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              patientName,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const Text(
              'Medications',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          // Add medication button
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
              child: Text(
                'Error: ${snap.error}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          final meds = snap.data ?? [];

          if (meds.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.medication_outlined,
                      size: 72, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text(
                    'No medications yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a medication for $patientName.',
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black38),
                  ),
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
                    icon: const Icon(Icons.add,
                        color: Colors.white, size: 18),
                    label: const Text(
                      'Add Medication',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
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

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: meds.length,
            itemBuilder: (context, i) {
              final med = meds[i];
              return _MedCard(
                med: med,
                patientUid: patientUid,
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
  final CaregiverService service;

  const _MedCard({
    required this.med,
    required this.patientUid,
    required this.service,
  });

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.medication_outlined,
                color: Color(0xFF2BC8A7), size: 26),
          ),

          const SizedBox(width: 14),

          // Info
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
                const SizedBox(height: 4),
                Text(
                  '${med.hour.toString().padLeft(2, '0')}:'
                  '${med.minute.toString().padLeft(2, '0')} ${med.period}  '
                  '·  Every ${med.freqNumber} ${med.freqUnit}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),

          // Delete
          IconButton(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 22),
          ),
        ],
      ),
    );
  }
}