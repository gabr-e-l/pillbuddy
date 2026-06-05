// lib/screens/caregiver_intake_history_screen.dart
//
// Intake Updates — caregiver view of a patient's full medication adherence
// history.
//
// Features:
//   • Summary bar — total taken / taken-late / skipped counts + adherence rate
//   • Date filter chips — All | Today | This Week | This Month | Custom range
//   • Medication filter — filter to one specific medication
//   • Grouped timeline — entries grouped by date, newest first
//   • Adherence rate progress bar per group
//   • Real-time Firestore stream from users/{patientUid}/intakes
//
// Status values: 'taken' | 'taken_late' | 'skipped'
// ('snoozed' has been removed from the app.)
//
// UPDATED: All text, colours, cards and buttons respect
// CaregiverAccessibilityProvider (dark/HC/font/button scale).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medication_model.dart';
import '../providers/caregiver_accessibility_provider.dart';
import 'caregiver_theme_wrapper.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class IntakeRecord {
  final String    medId;
  final String    medName;
  final String    status;      // taken | taken_late | skipped
  final String    date;        // yyyy-MM-dd
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
      medId:      d['medId']      as String? ?? '',
      medName:    d['medName']    as String? ?? 'Unknown',
      status:     d['status']     as String? ?? 'unknown',
      date:       d['date']       as String? ?? '',
      recordedAt: d['recordedAt'] != null
          ? (d['recordedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

// ── Service helper ────────────────────────────────────────────────────────────

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

  /// Live stream of the patient's current medications (for the filter list).
  Stream<List<MedicationModel>> medsStreamForPatient(String patientUid) {
    return _db
        .collection('users')
        .doc(patientUid)
        .collection('medications')
        .snapshots()
        .map((snap) => snap.docs
          .map((d) => MedicationModel.fromDoc(d))
          .toList());
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

  _DateFilter    _dateFilter    = _DateFilter.all;
  DateTimeRange? _customRange;
  String?        _selectedMedId;
  String?        _selectedMedName;

  // Status palette – fixed, independent of theme
  static const _teal   = Color(0xFF2BC8A7);
  static const _orange = Color(0xFFFFA726);
  static const _red    = Color(0xFFEF5350);

  // ── Filtering ──────────────────────────────────────────────────────────────

  bool _inDateRange(IntakeRecord r) {
    if (_dateFilter == _DateFilter.all) return true;
    final now   = DateTime.now();
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
    final d     = DateTime(int.parse(parts[0]), int.parse(parts[1]),
        int.parse(parts[2]));
    final fromD = DateTime(from!.year, from.month, from.day);
    final toD   = DateTime(to!.year,   to.month,   to.day);
    return !d.isBefore(fromD) && !d.isAfter(toD);
  }

  List<IntakeRecord> _apply(List<IntakeRecord> all) => all.where((r) {
        if (!_inDateRange(r)) return false;
        if (_selectedMedId != null && r.medId != _selectedMedId) return false;
        return true;
      }).toList();

  Map<String, List<IntakeRecord>> _group(List<IntakeRecord> records) {
    final map = <String, List<IntakeRecord>>{};
    for (final r in records) {
      map.putIfAbsent(r.date, () => []).add(r);
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Map.fromEntries(sorted);
  }

  // ── Pickers ────────────────────────────────────────────────────────────────

  Future<void> _pickCustomRange() async {
    final now   = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate:  now,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 7)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: _teal)),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _customRange = range;
        _dateFilter  = _DateFilter.custom;
      });
    }
  }

  void _showMedFilter(List<MedicationModel> meds) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final onSheet = isDark ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context:  context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Filter by Medication',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: onSheet)),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.medication_outlined, color: _teal),
              title:   Text('All Medications',
                  style: TextStyle(color: onSheet)),
              trailing: _selectedMedId == null
                  ? const Icon(Icons.check, color: _teal)
                  : null,
              onTap: () {
                setState(() { _selectedMedId = null; _selectedMedName = null; });
                Navigator.pop(ctx);
              },
            ),
            ...meds.map((m) => ListTile(
                  leading: Icon(Icons.medication,
                      color: isDark ? Colors.white54 : Colors.black45),
                  title: Text(m.name,
                      style: TextStyle(color: onSheet),
                      overflow: TextOverflow.ellipsis),
                  trailing: _selectedMedId == m.id
                      ? const Icon(Icons.check, color: _teal)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedMedId   = m.id;
                      _selectedMedName = m.name;
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
      case 'skipped':    return _red;
      default:           return Colors.blueGrey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'taken':      return Icons.check_circle_rounded;
      case 'taken_late': return Icons.watch_later_rounded;
      case 'skipped':    return Icons.cancel_rounded;
      default:           return Icons.help_outline_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'taken':      return 'Taken';
      case 'taken_late': return 'Taken Late';
      case 'skipped':    return 'Skipped';
      default:           return status;
    }
  }

  String _friendlyDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    final d     = DateTime(int.parse(parts[0]), int.parse(parts[1]),
        int.parse(parts[2]));
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff  = today
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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

  /// Returns counts for the three active statuses only.
  Map<String, int> _counts(List<IntakeRecord> records) => {
        'taken':      records.where((r) => r.status == 'taken').length,
        'taken_late': records.where((r) => r.status == 'taken_late').length,
        'skipped':    records.where((r) => r.status == 'skipped').length,
      };

  double _adherenceRate(List<IntakeRecord> records) {
    if (records.isEmpty) return 0;
    final taken = records
        .where((r) => r.status == 'taken' || r.status == 'taken_late')
        .length;
    return taken / records.length;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CaregiverThemeWrapper(
      builder: (ctx, acc) {
        final cs      = Theme.of(ctx).colorScheme;
        final isDark  = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor =
            isDark ? const Color(0xFF121212) : const Color(0xFFF4F7FF);

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, size: 20, color: cs.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              children: [
                Text(
                  widget.patientName,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface),
                ),
                Text(
                  'Intake Updates',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
            centerTitle: true,
          ),
          body: StreamBuilder<List<MedicationModel>>(
            stream: _reader.medsStreamForPatient(widget.patientUid),
            builder: (context, medsSnap) {
              final liveMeds = medsSnap.data ?? [];
              // If the currently-selected med was deleted, clear the filter.
              if (_selectedMedId != null &&
                  liveMeds.every((m) => m.id != _selectedMedId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _selectedMedId   = null;
                      _selectedMedName = null;
                    });
                  }
                });
              }
              return StreamBuilder<List<IntakeRecord>>(
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
                  _buildFilterBar(liveMeds, isDark, cs),
                  if (filtered.isNotEmpty)
                    _buildSummaryCard(counts, rate, isDark, cs),
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmpty(isDark, cs)
                        : ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            children: grouped.entries
                                .map((e) => _buildDayGroup(
                                    e.key, e.value, isDark, cs))
                                .toList(),
                          ),
                  ),
                ],
              );
            },
          );
        }),
        );
      },
    );
  }

  // ── Filter bar ─────────────────────────────────────────────────────────────

  Widget _buildFilterBar(
      List<MedicationModel> liveMeds, bool isDark, ColorScheme cs) {
    final chipBg     = isDark ? const Color(0xFF2A2A3E) : Colors.white;
    final chipBorder = isDark ? Colors.white12 : Colors.grey.shade200;

    return Container(
      color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF4F7FF),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _DateFilter.values.map((f) {
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
                      color: sel ? _teal : chipBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel ? _teal : chipBorder),
                    ),
                    child: Text(
                      f == _DateFilter.custom && _customRange != null
                          ? '${_customRange!.start.day}/'
                              '${_customRange!.start.month}'
                              ' – ${_customRange!.end.day}/'
                              '${_customRange!.end.month}'
                          : f.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel
                            ? Colors.white
                            : cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Medication filter pill — Flexible prevents overflow with long names
          GestureDetector(
            onTap: () => _showMedFilter(liveMeds),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _selectedMedId != null
                    ? _teal.withValues(alpha: 0.12)
                    : chipBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color:
                        _selectedMedId != null ? _teal : chipBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medication_outlined,
                      size: 14,
                      color: _selectedMedId != null
                          ? _teal
                          : cs.onSurface.withValues(alpha: 0.45)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _selectedMedName ?? 'All Medications',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _selectedMedId != null
                            ? _teal
                            : cs.onSurface.withValues(alpha: 0.6),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: _selectedMedId != null
                          ? _teal
                          : cs.onSurface.withValues(alpha: 0.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary card ───────────────────────────────────────────────────────────

  Widget _buildSummaryCard(Map<String, int> counts, double rate,
      bool isDark, ColorScheme cs) {
    final pct       = (rate * 100).round();
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final labelClr  = cs.onSurface.withValues(alpha: 0.55);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color:
                  Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Adherence rate row
          Row(
            children: [
              Text('Adherence Rate',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: labelClr)),
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
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 7,
              backgroundColor:
                  isDark ? Colors.white12 : Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(
                pct >= 80 ? _teal : pct >= 50 ? _orange : _red,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Three stat chips — Taken / Late / Skipped
          Row(
            children: [
              _statChip(Icons.check_circle_rounded, _teal,
                  counts['taken']!,      'Taken',   isDark),
              const SizedBox(width: 8),
              _statChip(Icons.watch_later_rounded, _orange,
                  counts['taken_late']!, 'Late',    isDark),
              const SizedBox(width: 8),
              _statChip(Icons.cancel_rounded, _red,
                  counts['skipped']!,    'Skipped', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, Color color, int count, String label,
      bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text('$count',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ── Day group ──────────────────────────────────────────────────────────────

  Widget _buildDayGroup(String dateStr, List<IntakeRecord> records,
      bool isDark, ColorScheme cs) {
    final taken = records
        .where((r) => r.status == 'taken' || r.status == 'taken_late')
        .length;
    final rate       = records.isEmpty ? 0.0 : taken / records.length;
    final headerClr  = cs.onSurface.withValues(alpha: 0.55);
    final countColor = cs.onSurface.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              _friendlyDate(dateStr),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: headerClr),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: rate,
                  minHeight: 4,
                  backgroundColor:
                      isDark ? Colors.white12 : Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      rate >= 0.8
                          ? _teal
                          : rate >= 0.5
                              ? _orange
                              : _red),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$taken/${records.length}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: countColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...records.map((r) => _buildRecordCard(r, isDark, cs)),
      ],
    );
  }

  Widget _buildRecordCard(
      IntakeRecord r, bool isDark, ColorScheme cs) {
    final color     = _statusColor(r.status);
    final icon      = _statusIcon(r.status);
    final label     = _statusLabel(r.status);
    final time      = _timeOf(r);
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final nameColor = cs.onSurface;
    final timeColor = cs.onSurface.withValues(alpha: 0.4);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.2),
            width: 1),
        boxShadow: [
          BoxShadow(
              color:
                  Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.medName,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: nameColor)),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(
                        alpha: isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ],
            ),
          ),
          if (time.isNotEmpty)
            Text(time,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: timeColor)),
        ],
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmpty(bool isDark, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded,
              size: 72,
              color: cs.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No intake records',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 8),
          Text(
            'Records will appear here once\nthe patient logs their doses.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}