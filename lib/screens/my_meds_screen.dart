// lib/screens/my_meds_screen.dart
//
// Displays today's medications fetched in real-time from Firestore.
// Users can tap the Take/Taken button to toggle status (persisted locally per session;
// extend with a Firestore 'intakes' sub-collection for full history tracking).

import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/medication_service.dart';
import 'med_details.dart';

class MyMedsScreen extends StatefulWidget {
  final DateTime selectedDate;

  const MyMedsScreen({super.key, required this.selectedDate});

  @override
  State<MyMedsScreen> createState() => _MyMedsScreenState();
}

class _MyMedsScreenState extends State<MyMedsScreen> {
  final _service = MedicationService();
  String _selectedFilter = 'All';

  // Tracks which meds have been taken this session (by Firestore doc ID)
  final Set<String> _takenIds = {};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildHorizontalCalendar(),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text(
              "Today's Medication",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
          ),
          StreamBuilder<List<MedicationModel>>(
            stream: _service.medicationsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return Expanded(
                  child: Center(
                    child: Text('Error: ${snapshot.error}'),
                  ),
                );
              }

              final all = snapshot.data ?? [];

              // Assign status based on _takenIds set
              final medsWithStatus = all.map((med) {
                final status =
                    _takenIds.contains(med.id) ? 'Taken' : 'Take';
                return _MedWithStatus(med: med, status: status);
              }).toList();

              // Filter chips
              final taken =
                  medsWithStatus.where((m) => m.status == 'Taken').length;

              final filtered = _selectedFilter == 'All'
                  ? medsWithStatus
                  : medsWithStatus
                      .where((m) => m.status == _selectedFilter)
                      .toList();

              return Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _buildFilterChip(
                              'All', all.length.toString()),
                          const SizedBox(width: 10),
                          _buildFilterChip('Taken', taken.toString()),
                          const SizedBox(width: 10),
                          _buildFilterChip(
                            'Take',
                            (all.length - taken).toString(),
                            label: 'Pending',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (all.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.medication_outlined,
                                  size: 64, color: Colors.grey),
                              SizedBox(height: 12),
                              Text(
                                'No medications yet.\nTap "Add Meds" to get started.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _buildMedCard(filtered[index]);
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Calendar strip ────────────────────────────────────────────────────────

  Widget _buildHorizontalCalendar() {
    final selected = widget.selectedDate;
    final monday =
        selected.subtract(Duration(days: selected.weekday - 1));
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Schedule for ${months[selected.month - 1]} ${selected.day}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            itemCount: 7,
            itemBuilder: (context, index) {
              final dayDate = monday.add(Duration(days: index));
              final isSelected = dayDate.day == selected.day &&
                  dayDate.month == selected.month;
              return _dateItem(
                ['M','T','W','T','F','S','S'][dayDate.weekday - 1],
                dayDate.day.toString(),
                isSelected: isSelected,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dateItem(String day, String date, {bool isSelected = false}) {
    return Container(
      width: 55,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE3F2FD) : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        border: isSelected
            ? Border.all(color: const Color(0xFF3B71FE), width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(day,
              style: TextStyle(
                color: isSelected ? const Color(0xFF3B71FE) : Colors.grey,
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 4),
          Text(date,
              style: TextStyle(
                color: isSelected ? const Color(0xFF3B71FE) : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              )),
        ],
      ),
    );
  }

  // ── Filter chips ──────────────────────────────────────────────────────────

  Widget _buildFilterChip(String value, String count, {String? label}) {
    final displayLabel = label ?? value;
    final isActive = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF3B71FE) : const Color(0xFFF4F7FF),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Text(
              displayLabel,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isActive ? Colors.blue.shade900 : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Text(
                count,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Medication card ───────────────────────────────────────────────────────

  Widget _buildMedCard(_MedWithStatus item) {
    final med = item.med;
    final isTaken = item.status == 'Taken';

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Medication type icon placeholder
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MedDetailsScreen(
                  medId: med.id!,
                  initialMed: med,
                ),
              ),
            ),
            child: Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FF),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Icon(
                  _iconForType(med.type),
                  size: 36,
                  color: const Color(0xFF3B71FE),
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        med.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isTaken)
                      _buildBadge('Taken ✓', Colors.green),
                  ],
                ),
                Text(
                  med.doseLabel,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Text(
                  med.timeLabel,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        if (isTaken) {
                          _takenIds.remove(med.id);
                        } else {
                          _takenIds.add(med.id!);
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isTaken ? Colors.green : const Color(0xFF3B71FE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isTaken ? 'Taken' : 'Take',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type.toLowerCase()) {
      'capsule' => Icons.medication,
      'injection' => Icons.vaccines,
      'spray' => Icons.air,
      'drop' => Icons.water_drop,
      'syrup' => Icons.local_drink,
      _ => Icons.medication_liquid,
    };
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

class _MedWithStatus {
  final MedicationModel med;
  final String status; // 'Take' | 'Taken'

  const _MedWithStatus({required this.med, required this.status});
}
