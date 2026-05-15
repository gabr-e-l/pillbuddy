// lib/screens/caregiver_intake_history_screen.dart
//
// Intake Updates — caregiver view of a patient's full medication adherence history.
//
// Features:
//   • Summary bar — total taken / taken-late / snoozed / skipped counts
//   • Date filter chips — All | Today | This Week | This Month | Custom range
//   • Medication filter — filter to one specific medication
//   • Grouped timeline — entries grouped by date, newest first
//   • Adherence rate progress bar per group
//   • Real-time Firestore stream from users/{patientUid}/intakes

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class IntakeRecord {
  final String medId;
  final String medName;
  final String status; // taken | taken_late | snoozed | skipped
  final String date;   // yyyy-MM-dd
  final DateTime? recordedAt;

  const IntakeRecord({
    required this.medId,
    required this.medName,
    required this.status,
    required this.date,
    this.recordedAt,
  });

  factory IntakeRecord.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return IntakeRecord(
      medId:      d['medId']   as String? ?? '',
      medName:    d['medName'] as String? ?? 'Unknown',
      status:     d['status']  as String? ?? 'unknown',
      date:       d['date']    as String? ?? '',
      recordedAt: d['recordedAt'] != null
          ? (d['recordedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

// ── Service helper (reads another user's intakes) ─────────────────────────────

class _CaregiverIntakeReader {
  final _db = FirebaseFirestore.instance;

  Stream<List<IntakeRecord>> streamForPatient(String patientUid) {
    return _db
        .collection('users')
        .doc(patientUid)
        .collection('intakes')
        .orderBy('recordedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(IntakeRecord.fromDoc).toList());
  }
}

// ── Date range filter ─────────────────────────────────────────────────────────

enum _DateFilter { all, today, week, month, custom }

extension _DateFilterLabel on _DateFilter {
  String get label {
    switch (this) {
      case _DateFilter.all:    return 'All';
      case _DateFilter.today:  return 'Today';
      case _DateFilter.week:   return 'This Week';
      case _DateFilter.month:  return 'This Month';
      case _DateFilter.custom: return 'Custom';
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CaregiverIntakeHistoryScreen extends StatefulWidget {
  final String patientUid;
  final String patientName;

  const CaregiverIntakeHistoryScreen({
    super.key,
    required this.patientUid,
    required this.patientName,
  });

  @override
  State<CaregiverIntakeHistoryScreen> createState() =>
      _CaregiverIntakeHistoryScreenState();
}

class _CaregiverIntakeHistoryScreenState
    extends State<CaregiverIntakeHistoryScreen> {
  final _reader = _CaregiverIntakeReader();

  _DateFilter _dateFilter = _DateFilter.all;
  DateTimeRange? _customRange;
  String? _selectedMedId; // null = all meds
  String? _selectedMedName;

  static const _teal   = Color(0xFF2BC8A7);
  static const _orange = Color(0xFFFFA726);
  static const _grey   = Color(0xFF9E9E9E);
  static const _red    = Color(0xFFEF5350);
  static const _bg     = Color(0xFFF4F7FF);

  // ── Filtering ─────────────────────────────────────────────────────────────

  bool _inDateRange(IntakeRecord r) {
    if (_dateFilter == _DateFilter.all) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime? from, to;
    switch (_dateFilter) {
      case _DateFilter.today:
        from = to = today;
        break;
      case _DateFilter.week:
        from = today.subtract(Duration(days: today.weekday - 1));
        to   = from.add(const Duration(days: 6));
        break;
      case _DateFilter.month:
        from = DateTime(now.year, now.month, 1);
        to   = DateTime(now.year, now.month + 1, 0);
        break;
      case _DateFilter.custom:
        if (_customRange == null) return true;
        from = _customRange!.start;
        to   = _customRange!.end;
        break;
      case _DateFilter.all:
        return true;
    }

    final parts = r.date.split('-');
    if (parts.length != 3) return false;
    final d = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final fromD = DateTime(from!.year, from.month, from.day);
    final toD   = DateTime(to!.year,   to.month,   to.day);
    return !d.isBefore(fromD) && !d.isAfter(toD);
  }

  List<IntakeRecord> _apply(List<IntakeRecord> all) {
    return all.where((r) {
      if (!_inDateRange(r)) return false;
      if (_selectedMedId != null && r.medId != _selectedMedId) return false;
      return true;
    }).toList();
  }

  // ── Grouping ──────────────────────────────────────────────────────────────

  /// Returns records grouped by date string, newest date first.
  Map<String, List<IntakeRecord>> _group(List<IntakeRecord> records) {
    final map = <String, List<IntakeRecord>>{};
    for (final r in records) {
      map.putIfAbsent(r.date, () => []).add(r);
    }
    // Sort dates descending
    final sorted = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Map.fromEntries(sorted);
  }

  // ── Custom date picker ─────────────────────────────────────────────────────

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 7)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _teal),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _customRange  = range;
        _dateFilter   = _DateFilter.custom;
      });
    }
  }

  // ── Med filter picker ─────────────────────────────────────────────────────

  void _showMedFilter(List<IntakeRecord> all) {
    // Collect unique meds from the current data
    final meds = <String, String>{}; // medId → medName
    for (final r in all) {
      meds[r.medId] = r.medName;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Filter by Medication',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.medication_outlined, color: _teal),
              title: const Text('All Medications'),
              trailing: _selectedMedId == null
                  ? const Icon(Icons.check, color: _teal)
                  : null,
              onTap: () {
                setState(() {
                  _selectedMedId   = null;
                  _selectedMedName = null;
                });
                Navigator.pop(ctx);
              },
            ),
            ...meds.entries.map((e) => ListTile(
                  leading:
                      const Icon(Icons.medication, color: Colors.black45),
                  title: Text(e.value),
                  trailing: _selectedMedId == e.key
                      ? const Icon(Icons.check, color: _teal)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedMedId   = e.key;
                      _selectedMedName = e.value;
                    });
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'taken':      return _teal;
      case 'taken_late': return _orange;
      case 'snoozed':    return _grey;
      case 'skipped':    return _red;
      default:           return Colors.blueGrey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'taken':      return Icons.check_circle_rounded;
      case 'taken_late': return Icons.watch_later_rounded;
      case 'snoozed':    return Icons.snooze_rounded;
      case 'skipped':    return Icons.cancel_rounded;
      default:           return Icons.help_outline_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'taken':      return 'Taken';
      case 'taken_late': return 'Taken Late';
      case 'snoozed':    return 'Snoozed';
      case 'skipped':    return 'Skipped';
      default:           return status;
    }
  }

  String _friendlyDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    final d    = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final now  = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff  = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  String _timeOf(IntakeRecord r) {
    final t = r.recordedAt;
    if (t == null) return '';
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  // ── Summary stats ─────────────────────────────────────────────────────────

  Map<String, int> _counts(List<IntakeRecord> records) {
    return {
      'taken':      records.where((r) => r.status == 'taken').length,
      'taken_late': records.where((r) => r.status == 'taken_late').length,
      'snoozed':    records.where((r) => r.status == 'snoozed').length,
      'skipped':    records.where((r) => r.status == 'skipped').length,
    };
  }

  double _adherenceRate(List<IntakeRecord> records) {
    if (records.isEmpty) return 0;
    final taken = records
        .where((r) => r.status == 'taken' || r.status == 'taken_late')
        .length;
    return taken / records.length;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              size: 20, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              widget.patientName,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const Text(
              'Intake Updates',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<IntakeRecord>>(
        stream: _reader.streamForPatient(widget.patientUid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _teal));
          }
          if (snap.hasError) {
            return Center(
              child: Text('Error: ${snap.error}',
                  style: const TextStyle(color: Colors.redAccent)),
            );
          }

          final all      = snap.data ?? [];
          final filtered = _apply(all);
          final grouped  = _group(filtered);
          final counts   = _counts(filtered);
          final rate     = _adherenceRate(filtered);

          return Column(
            children: [
              // ── Filter bar ───────────────────────────────────────────
              _buildFilterBar(all),

              // ── Summary card ──────────────────────────────────────────
              if (filtered.isNotEmpty)
                _buildSummaryCard(counts, rate, filtered.length),

              // ── Timeline ──────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmpty()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: grouped.entries.map((entry) {
                          return _buildDayGroup(
                              entry.key, entry.value);
                        }).toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Filter bar ────────────────────────────────────────────────────────────

  Widget _buildFilterBar(List<IntakeRecord> all) {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._DateFilter.values.map((f) {
                  final sel = _dateFilter == f;
                  return GestureDetector(
                    onTap: () async {
                      if (f == _DateFilter.custom) {
                        await _pickCustomRange();
                      } else {
                        setState(() => _dateFilter = f);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? _teal : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? _teal : Colors.grey.shade200,
                        ),
                      ),
                      child: Text(
                        f == _DateFilter.custom && _customRange != null
                            ? '${_customRange!.start.day}/${_customRange!.start.month} – ${_customRange!.end.day}/${_customRange!.end.month}'
                            : f.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Medication filter pill
          GestureDetector(
            onTap: () => _showMedFilter(all),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _selectedMedId != null
                    ? _teal.withOpacity(0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedMedId != null
                      ? _teal
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medication_outlined,
                      size: 14,
                      color: _selectedMedId != null
                          ? _teal
                          : Colors.black45),
                  const SizedBox(width: 6),
                  Text(
                    _selectedMedName ?? 'All Medications',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedMedId != null
                          ? _teal
                          : Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: _selectedMedId != null
                          ? _teal
                          : Colors.black38),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary card ──────────────────────────────────────────────────────────

  Widget _buildSummaryCard(
      Map<String, int> counts, double rate, int total) {
    final pct = (rate * 100).round();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Adherence rate
          Row(
            children: [
              const Text('Adherence Rate',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const Spacer(),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: pct >= 80
                      ? _teal
                      : pct >= 50
                          ? _orange
                          : _red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 7,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(
                pct >= 80
                    ? _teal
                    : pct >= 50
                        ? _orange
                        : _red,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Stat chips
          Row(
            children: [
              _statChip(Icons.check_circle_rounded, _teal,
                  counts['taken']!, 'Taken'),
              const SizedBox(width: 8),
              _statChip(Icons.watch_later_rounded, _orange,
                  counts['taken_late']!, 'Late'),
              const SizedBox(width: 8),
              _statChip(Icons.snooze_rounded, _grey,
                  counts['snoozed']!, 'Snoozed'),
              const SizedBox(width: 8),
              _statChip(Icons.cancel_rounded, _red,
                  counts['skipped']!, 'Skipped'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(
      IconData icon, Color color, int count, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(
              '$count',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black45,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  // ── Day group ─────────────────────────────────────────────────────────────

  Widget _buildDayGroup(String dateStr, List<IntakeRecord> records) {
    final taken = records
        .where((r) => r.status == 'taken' || r.status == 'taken_late')
        .length;
    final rate = records.isEmpty ? 0.0 : taken / records.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Date header
        Row(
          children: [
            Text(
              _friendlyDate(dateStr),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: rate,
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      rate >= 0.8 ? _teal : rate >= 0.5 ? _orange : _red),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$taken/${records.length}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black38),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Record cards
        ...records.map((r) => _buildRecordCard(r)),
      ],
    );
  }

  Widget _buildRecordCard(IntakeRecord r) {
    final color = _statusColor(r.status);
    final icon  = _statusIcon(r.status);
    final label = _statusLabel(r.status);
    final time  = _timeOf(r);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          // Med name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.medName,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Recorded-at time
          if (time.isNotEmpty)
            Text(
              time,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black38),
            ),
        ],
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No intake records',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black54),
          ),
          const SizedBox(height: 8),
          const Text(
            'Records will appear here once\nthe patient logs their doses.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black38),
          ),
        ],
      ),
    );
  }
}
