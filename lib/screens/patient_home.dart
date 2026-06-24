// lib/screens/patient_home.dart
//
// Skipped-dose optimisation:
//
//   A dose is considered "past its intake window" and treated as Skipped when:
//     (a) The selected date is any day BEFORE today, OR
//     (b) The selected date is today AND the scheduled time + 20 min has
//         already passed (i.e. the final alarm window has closed).
//
//   For any such expired, unmarked dose:
//     • It is automatically recorded as 'skipped' in Firestore the first time
//       the patient views that date (write-once: only if no status exists yet).
//     • In the Mark-As sheet:
//         – "Taken"      → always greyed-out (disabled)
//         – "Taken Late" → ACTIVE (patient may correct the auto-skip)
//         – "Skipped"    → info row showing "auto-recorded"
//
//   For today's doses still within the alarm window, the existing three-stage
//   logic applies (stage 0 → Taken only; stage 1 → Taken Late only; stage 2
//   → same as expired).
//
//   'Snoozed' has been fully removed.
//
// ── Notification scheduling fixes ────────────────────────────────────────
//
//   • Multi-intake times: _scheduleRemindersIfChanged() calls
//     NotificationService.scheduleMedicationReminders() (passing the
//     medication's full intakeTimes list) instead of the old single-time
//     schedulePatientReminder(), so meds with multiple daily doses (e.g.
//     "every 8 hours") get an alarm for every dose, not just the first.
//   • Repeated scheduling: a signature guard (_lastScheduledSignature) means
//     we only reschedule when the medId/dose/unit/time data actually
//     changed, instead of on every Firestore snapshot rebuild (which could
//     be triggered by something unrelated, like an intake status update).
//   • Stale reminders: _lastScheduledMedIds tracks which meds we last
//     scheduled for today. If a medication drops out of today's active list
//     (deleted, deactivated, or past its stop date) its pending alarms are
//     now explicitly cancelled instead of being left to fire forever.
//
// ── Multi-intake-time dashboard fix ──────────────────────────────────────
//
//   The fixes above made NotificationService schedule (and correctly track
//   the alarm stage for) every configured intake time on a medication — but
//   the dashboard itself still only ever rendered ONE card per medication,
//   using the legacy primary hour/minute/period fields. A medication with
//   3 daily intake times would fire 3 alarms a day but only ever show (and
//   allow marking) the first one.
//
//   Fix: _buildMedList() now expands every active medication into one
//   _DoseSlot per configured intake time (falling back to the legacy
//   hour/minute/period when intakeTimes is empty, so single-dose meds are
//   unaffected). Each slot:
//     • Looks up its own status via IntakeService's composite
//       '{medId}_{timeIndex}' key (see intake_service.dart) instead of a
//       bare medId — so marking one dose "Taken" no longer overwrites every
//       other dose of that medication on the same day.
//     • Runs the auto-skip / window-expiry check against ITS OWN scheduled
//       time, not the medication's primary time.
//     • Reads/writes its alarm stage via
//       NotificationService.getAlertStage(medId, timeIndex: t) so the
//       Mark-As sheet's enabled/disabled buttons reflect that specific
//       dose's stage, not always slot 0's.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/medication_model.dart';
import '../services/medication_service.dart';
import '../services/intake_service.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../providers/accessibility_provider.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';
import 'accessibility_settings_screen.dart';
import 'notification_settings_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

bool _isPastDate(DateTime date) {
  final today = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  return d.isBefore(t);
}

bool _isToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

/// True when the 20-minute alarm window for a dose scheduled at
/// [hour]/[minute]/[period] on [date] has elapsed.
///
/// Takes the slot's own time directly (rather than a MedicationModel) so it
/// can be evaluated per intake-time slot, not just a medication's primary
/// time.
bool _isWindowExpired(int hour, int minute, String period, DateTime date) {
  if (_isPastDate(date)) return true;
  if (!_isToday(date)) return false;
  final h24 = hour % 12 + (period == 'PM' ? 12 : 0);
  final scheduled = DateTime(date.year, date.month, date.day, h24, minute);
  return DateTime.now().isAfter(scheduled.add(const Duration(minutes: 20)));
}

/// One concrete, mark-able dose: a medication paired with one of its
/// configured intake times. A medication with 3 intake times produces 3
/// _DoseSlots per day; a medication with no intakeTimes configured produces
/// exactly 1, built from its legacy hour/minute/period fields.
class _DoseSlot {
  final MedicationModel med;
  final int timeIndex;
  final int hour;
  final int minute;
  final String period;

  _DoseSlot({
    required this.med,
    required this.timeIndex,
    required this.hour,
    required this.minute,
    required this.period,
  });

  String get medId => med.id ?? med.name;
}

/// Expands [med] into one _DoseSlot per configured intake time for [date].
///
/// For 'Hour' frequency, uses [MedicationModel.doseSlotsForDate] to compute
/// the continuous, cross-day schedule (e.g. 1:41 AM, 6:41 AM, 11:41 AM,
/// 4:41 PM, 9:41 PM on day 1; 2:41 AM, 7:41 AM … on day 2).
///
/// For all other frequencies, falls back to the intakeTimes list (or the
/// legacy single hour/minute/period when intakeTimes is empty).
List<_DoseSlot> _expandDoseSlots(MedicationModel med, DateTime date) {
  // ── Hour frequency: compute continuous slots for this specific date ──────
  if (med.freqUnit == 'Hour') {
    final hourSlots = med.doseSlotsForDate(date);
    if (hourSlots.isNotEmpty) {
      return [
        for (int i = 0; i < hourSlots.length; i++)
          _DoseSlot(
            med:       med,
            // Use the global slotIndex as the timeIndex so that Firestore
            // doc IDs are stable and unique across day boundaries.
            // e.g. on June 25 the first dose might be slotIndex=5 not 0.
            timeIndex: (hourSlots[i]['slotIndex'] as num?)?.toInt() ?? i,
            hour:      (hourSlots[i]['hour']      as num).toInt(),
            minute:    (hourSlots[i]['minute']    as num).toInt(),
            period:    hourSlots[i]['period']     as String,
          ),
      ];
    }
    // If doseSlotsForDate returns empty (e.g. old medication without
    // firstDoseDateTime), fall through to the legacy intakeTimes path below.
  }

  // ── All other frequencies (Day, Week, Month) ─────────────────────────────
  if (med.intakeTimes.isEmpty) {
    return [
      _DoseSlot(
        med:       med,
        timeIndex: 0,
        hour:      med.hour,
        minute:    med.minute,
        period:    med.period,
      ),
    ];
  }

  return [
    for (int i = 0; i < med.intakeTimes.length; i++)
      _DoseSlot(
        med:       med,
        timeIndex: i,
        hour:      (med.intakeTimes[i]['hour']   as num?)?.toInt() ?? med.hour,
        minute:    (med.intakeTimes[i]['minute'] as num?)?.toInt() ?? med.minute,
        period:    med.intakeTimes[i]['period']  as String? ?? med.period,
      ),
  ];
}

// ── Root widget ───────────────────────────────────────────────────────────────

class PatientHome extends StatefulWidget {
  const PatientHome({super.key});

  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaffoldBg = theme.brightness == Brightness.dark
        ? theme.scaffoldBackgroundColor
        : const Color(0xFFF4F7FF);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const _TodayTab(),
          const _PatientSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: theme.colorScheme.surface,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurface.withOpacity(0.4),
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.medication_outlined), label: 'My Meds'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

// ── Today tab ─────────────────────────────────────────────────────────────────

class _TodayTab extends StatefulWidget {
  const _TodayTab();

  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  final _medService     = MedicationService();
  final _intakeService  = IntakeService();
  final _profileService = ProfileService();
  final _notifService   = NotificationService();

  DateTime _selectedDate = DateTime.now();
  late final List<DateTime> _calendarDays;

  // Tracks "{date}_{medId}_{timeIndex}" keys that have already been
  // auto-skipped THIS session. Once a key is in this set we never write to
  // Firestore again, so a patient's "Taken Late" correction cannot be
  // overwritten.
  final Set<String> _autoSkippedKeys = {};

  // Guards scheduleMedicationReminders() against being re-invoked on every
  // Firestore snapshot rebuild. The StreamBuilder in _buildMedList() rebuilds
  // on ANY change under the medications collection (including unrelated
  // fields), so without a guard every rebuild would re-call
  // scheduleMedicationReminders() for every active medication, stacking
  // duplicate pending notifications. We only reschedule when the actual set
  // of (medId, time, dose) signatures changes.
  String? _lastScheduledSignature;

  // Tracks which medIds we last scheduled reminders for. If a medId
  // disappears from today's active list (deleted, deactivated, or past its
  // stop date) on the next rebuild, its pending alarms are cancelled instead
  // of being left to fire indefinitely.
  Set<String> _lastScheduledMedIds = {};

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _calendarDays =
        List.generate(14, (i) => today.subtract(Duration(days: 3 - i)));
    _notifService.init();
  }

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(onSurface),
          // Wrap calendar in a no-text-scale zone so XL system font size
          // cannot inflate the day/weekday labels beyond the fixed cell height.
          MediaQuery.withNoTextScaling(
            child: _buildHorizontalCalendar(theme),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              _isToday(_selectedDate)
                  ? "Today's Medications"
                  : _isPastDate(_selectedDate)
                      ? 'Past Medications'
                      : 'Upcoming Medications',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: onSurface),
            ),
          ),
          Expanded(child: _buildMedList()),
        ],
      ),
    );
  }

  Widget _buildHeader(Color onSurface) {
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
              Text('Hello, $name 👋',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: onSurface)),
              Text('Here are your medications for today.',
                  style: TextStyle(
                      fontSize: 14, color: onSurface.withOpacity(0.5))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHorizontalCalendar(ThemeData theme) {
    final primary   = theme.colorScheme.primary;
    final surface   = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    // Use a fixed logical height that never depends on font/button scale
    // so the carousel never overflows at XL accessibility sizes.
    const double itemHeight = 60.0;
    const double vertPad    = 8.0;
    const double totalHeight = itemHeight + vertPad * 2;

    return SizedBox(
      height: totalHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: vertPad),
        itemCount: _calendarDays.length,
        itemBuilder: (context, i) {
          final day        = _calendarDays[i];
          final isSelected = _isSameDay(day, _selectedDate);
          final isToday    = _isSameDay(day, DateTime.now());
          return GestureDetector(
            onTap: () => setState(() => _selectedDate = day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 48,
              decoration: BoxDecoration(
                color: isSelected ? primary : surface,
                borderRadius: BorderRadius.circular(12),
                border: isToday && !isSelected
                    ? Border.all(color: primary, width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _weekdayLabel(day),
                    style: TextStyle(
                      // Clamp the weekday label to a fixed small size so it
                      // never stretches the card at XL font scale.
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white70
                          : onSurface.withOpacity(0.45),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${day.day}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : onSurface)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMedList() {
    final theme     = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

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
        final meds    = allMeds.where((m) => m.isActiveOn(_selectedDate)).toList();

        // Schedule reminders for today's active meds — guarded so this only
        // (re)runs when the underlying schedule actually changed, not on
        // every snapshot rebuild (e.g. a status update elsewhere triggering
        // this StreamBuilder to rebuild with otherwise-identical med data).
        _scheduleRemindersIfChanged(
            allMeds.where((m) => m.isActiveOn(DateTime.now())).toList());

        if (meds.isEmpty && allMeds.isEmpty) return _buildEmptyState(onSurface);

        // Expand every active medication into one dose slot per configured
        // intake time. This is what makes a 2x/day or 3x/day medication show
        // up as multiple, independently mark-able cards instead of one.
        final doseSlots = <_DoseSlot>[
          for (final med in meds) ..._expandDoseSlots(med, _selectedDate),
        ];
        // Sort by time-of-day so doses appear in chronological order rather
        // than grouped by medication.
        doseSlots.sort((a, b) {
          final aH = a.hour % 12 + (a.period == 'PM' ? 12 : 0);
          final bH = b.hour % 12 + (b.period == 'PM' ? 12 : 0);
          if (aH != bH) return aH.compareTo(bH);
          return a.minute.compareTo(b.minute);
        });

        if (doseSlots.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_available_outlined,
                    size: 64, color: onSurface.withOpacity(0.2)),
                const SizedBox(height: 12),
                Text('No medications on this date',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withOpacity(0.45))),
                const SizedBox(height: 6),
                Text('Check a different date',
                    style: TextStyle(
                        fontSize: 13, color: onSurface.withOpacity(0.35))),
              ],
            ),
          );
        }

        return StreamBuilder<Map<String, String>>(
          stream: _intakeService.intakesForDateStream(_selectedDate),
          builder: (context, intakeSnap) {
            final intakes      = intakeSnap.data ?? {};
            final selectedDate = _selectedDate;

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: doseSlots.length,
              itemBuilder: (context, i) {
                final slot   = doseSlots[i];
                final medId  = slot.medId;
                final lookupKey = IntakeService.mapKey(medId, slot.timeIndex);
                String? status = intakes[lookupKey];

                // ── Auto-skip logic ──────────────────────────────────────
                // Rules:
                //  • Only fires when the intake window has expired.
                //  • NEVER overwrites 'taken' or 'taken_late' — those are
                //    patient corrections that must be preserved.
                //
                // Bug fix: the previous implementation used an in-memory Set
                // (_autoSkippedKeys) as a write-once guard. This worked within
                // a session but failed on app restart because:
                //   1. The Set is cleared.
                //   2. The intake stream briefly emits an empty map before
                //      Firestore returns real data.
                //   3. status == null → auto-skip fires → writes 'skipped'
                //      overwriting the patient's 'taken_late' correction.
                //
                // New approach:
                //  • _autoSkippedKeys still prevents duplicate writes within
                //    a single session (fast path — avoids repeated Firestore
                //    reads on every stream rebuild).
                //  • But when the key is NOT in the set (i.e. first time we
                //    see this slot this session, including after a restart),
                //    we do a one-time async Firestore read BEFORE writing
                //    'skipped'. If Firestore already has 'taken' or
                //    'taken_late' we skip the write entirely and add the key
                //    to _autoSkippedKeys so we never check again this session.
                //  • The UI shows status as 'skipped' optimistically (correct
                //    for the common case). If the async read reveals a
                //    correction, the stream will emit the real status on the
                //    next snapshot and the card will update.
                if (_isWindowExpired(
                    slot.hour, slot.minute, slot.period, selectedDate)) {
                  if (status == 'taken' || status == 'taken_late') {
                    // Patient has already corrected this — mark key as done
                    // so we never auto-skip this slot again this session.
                    final skipKey =
                        '${selectedDate.year}-'
                        "${selectedDate.month.toString().padLeft(2, '0')}-"
                        "${selectedDate.day.toString().padLeft(2, '0')}"
                        '_$lookupKey';
                    _autoSkippedKeys.add(skipKey);
                  } else {
                    final skipKey =
                        '${selectedDate.year}-'
                        "${selectedDate.month.toString().padLeft(2, '0')}-"
                        "${selectedDate.day.toString().padLeft(2, '0')}"
                        '_$lookupKey';
                    if (!_autoSkippedKeys.contains(skipKey)) {
                      _autoSkippedKeys.add(skipKey);
                      // Read Firestore first — never overwrite taken/taken_late.
                      _intakeService
                          .getIntakeStatus(
                        medId:     medId,
                        timeIndex: slot.timeIndex,
                        date:      selectedDate,
                      )
                          .then((existing) {
                        if (existing != 'taken' && existing != 'taken_late') {
                          _intakeService.recordIntake(
                            medId:     medId,
                            medName:   slot.med.name,
                            status:    'skipped',
                            timeIndex: slot.timeIndex,
                            date:      selectedDate,
                          );
                        }
                        // If existing IS taken/taken_late, do nothing —
                        // the stream will show the correct status on next emit.
                      });
                    }
                    // Optimistic UI: show skipped while the stream updates.
                    if (status == null) status = 'skipped';
                  }
                }

                return _MedCard(
                  med:          slot.med,
                  timeIndex:    slot.timeIndex,
                  hour:         slot.hour,
                  minute:       slot.minute,
                  period:       slot.period,
                  status:       status,
                  selectedDate: selectedDate,
                  onStatusChanged: (newStatus) async {
                    // When the patient actively sets a status (especially
                    // 'taken_late' to correct an auto-skip), remove the
                    // skipKey from _autoSkippedKeys so future stream
                    // re-emissions see the real Firestore status and the
                    // auto-skip block's "status == taken_late" guard works
                    // correctly on the very next rebuild.
                    final skipKey =
                        '${selectedDate.year}-'
                        "${selectedDate.month.toString().padLeft(2, '0')}-"
                        "${selectedDate.day.toString().padLeft(2, '0')}"
                        '_$lookupKey';
                    _autoSkippedKeys.remove(skipKey);

                    if (newStatus == null) {
                      await _intakeService.deleteIntake(
                          medId: medId,
                          timeIndex: slot.timeIndex,
                          date: selectedDate);
                    } else {
                      await _intakeService.recordIntake(
                        medId:     medId,
                        medName:   slot.med.name,
                        status:    newStatus,
                        timeIndex: slot.timeIndex,
                        date:      selectedDate,
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

  /// Schedules patient reminders for [todaysMeds], but only when the
  /// schedule actually changed (signature guard).
  ///
  /// For 'Hour' frequency meds, the intake times are computed dynamically
  /// per-day from [MedicationModel.doseSlotsForDate], so the alarms correctly
  /// reflect the continuous cross-day schedule instead of a static daily list.
  void _scheduleRemindersIfChanged(List<MedicationModel> todaysMeds) {
    final today = DateTime.now();
    final currentMedIds = todaysMeds.map((m) => m.id ?? m.name).toSet();

    final removedMedIds = _lastScheduledMedIds.difference(currentMedIds);
    for (final medId in removedMedIds) {
      _notifService.cancelPatientReminder(medId);
    }
    _lastScheduledMedIds = currentMedIds;

    // Build a signature that includes today's actual dose times for Hour meds.
    final signature = todaysMeds.map((m) {
      final List<Map<String, dynamic>> times;
      if (m.freqUnit == 'Hour') {
        times = m.doseSlotsForDate(today);
      } else if (m.intakeTimes.isNotEmpty) {
        times = m.intakeTimes;
      } else {
        times = [{'hour': m.hour, 'minute': m.minute, 'period': m.period}];
      }
      final timesKey = times
          .map((t) => '${t['hour']}:${t['minute']}${t['period']}')
          .join(',');
      return '${m.id ?? m.name}|${m.dose}|${m.unit}|$timesKey';
    }).toList()
      ..sort();
    final joined = signature.join(';');

    if (joined == _lastScheduledSignature) return;
    _lastScheduledSignature = joined;

    for (final med in todaysMeds) {
      // For Hour frequency, schedule each of today's computed dose times as
      // individual alarms using the global slotIndex as timeIndex (so Firestore
      // doc IDs are stable and unique across day boundaries).
      if (med.freqUnit == 'Hour') {
        final todaySlots = med.doseSlotsForDate(today);
        if (todaySlots.isNotEmpty) {
          // Cancel all existing alarms first — cancelPatientReminder()
          // sweeps all possible slot indices. Then schedule today's slots.
          _notifService.cancelPatientReminder(med.id ?? med.name);
          for (final slot in todaySlots) {
            _notifService.schedulePatientReminder(
              medId:     med.id ?? med.name,
              medName:   med.name,
              dose:      med.dose,
              unit:      med.unit,
              hour:      (slot['hour']   as num).toInt(),
              minute:    (slot['minute'] as num).toInt(),
              period:    slot['period']  as String,
              timeIndex: (slot['slotIndex'] as num?)?.toInt() ?? 0,
            );
          }
          continue;
        }
      }
      // Non-Hour frequency: use the stored intakeTimes list.
      _notifService.scheduleMedicationReminders(
        medId:       med.id ?? med.name,
        medName:     med.name,
        dose:        med.dose,
        unit:        med.unit,
        intakeTimes: med.intakeTimes,
        hour:        med.hour,
        minute:      med.minute,
        period:      med.period,
      );
    }
  }

  Widget _buildEmptyState(Color onSurface) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_outlined,
              size: 72, color: onSurface.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text('No medications scheduled',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: onSurface.withOpacity(0.45))),
          const SizedBox(height: 8),
          Text("Your caregiver hasn't added\nany medications yet.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: onSurface.withOpacity(0.35))),
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
  final MedicationModel                med;
  // The specific intake-time slot this card represents. hour/minute/period
  // are THIS slot's time (which may differ from med.hour/minute/period for
  // medications with multiple daily doses) — timeIndex is the matching
  // index into med.intakeTimes (or 0 for the legacy single-time fallback).
  final int                            timeIndex;
  final int                            hour;
  final int                            minute;
  final String                         period;
  final String?                        status;
  final DateTime                       selectedDate;
  final Future<void> Function(String?) onStatusChanged;

  const _MedCard({
    required this.med,
    required this.timeIndex,
    required this.hour,
    required this.minute,
    required this.period,
    required this.status,
    required this.selectedDate,
    required this.onStatusChanged,
  });

  @override
  State<_MedCard> createState() => _MedCardState();
}

class _MedCardState extends State<_MedCard> {
  String? _localStatus;
  bool    _saving     = false;
  int     _alertStage = 0;

  final _notifService = NotificationService();

  @override
  void initState() {
    super.initState();
    _localStatus = widget.status;
    _refreshStage();
  }

  @override
  void didUpdateWidget(_MedCard old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _localStatus = widget.status;
  }

  Future<void> _refreshStage() async {
    if (!_isToday(widget.selectedDate)) return;
    final stage = await _notifService.getAlertStage(
      widget.med.id ?? widget.med.name,
      timeIndex: widget.timeIndex,
    );
    if (mounted) setState(() => _alertStage = stage);
  }

  MedicationModel get med => widget.med;

  bool get _windowExpired =>
      _isWindowExpired(widget.hour, widget.minute, widget.period, widget.selectedDate);

  // If the patient already marked as 'taken' on time, nothing is "expired"
  // from their perspective — suppress all the warning/skipped UI.
  bool get _alreadyTakenOnTime => _localStatus == 'taken';

  // Taken is only active on today, stage 0, window not yet expired,
  // and dose not already marked.
  bool get _takenActive =>
      !_alreadyTakenOnTime &&
      !_windowExpired &&
      _alertStage == 0 &&
      _localStatus == null;

  // Taken Late is active when:
  //  • window has expired OR stage >= 1, AND
  //  • dose was NOT already marked 'taken' on time.
  bool get _takenLateActive =>
      !_alreadyTakenOnTime && (_windowExpired || _alertStage >= 1);

  // Show the skipped info row (instead of a Skipped button) when:
  //  • window expired OR stage 2 reached, AND
  //  • dose was NOT taken on time (taken on time suppresses all warning UI).
  bool get _showSkippedInfo =>
      !_alreadyTakenOnTime && (_windowExpired || _alertStage >= 2);

  // Show the context banner above the action tiles.
  bool get _showBanner =>
      !_alreadyTakenOnTime && (_showSkippedInfo || _alertStage == 1);

  Color get _statusColor => switch (_localStatus) {
        'taken'      => const Color(0xFF2BC8A7),
        'taken_late' => const Color(0xFFFFA726),
        'skipped'    => const Color(0xFFEF5350),
        _            => const Color(0xFF3B71FE),
      };

  String get _statusLabel => switch (_localStatus) {
        'taken'      => 'Taken ✓',
        'taken_late' => 'Taken Late',
        'skipped'    => 'Skipped',
        _            => 'Mark as',
      };

  Future<void> _handleStatusChange(BuildContext ctx, String? newStatus) async {
    if (_saving) return;
    setState(() { _saving = true; _localStatus = newStatus; });
    try {
      await widget.onStatusChanged(newStatus);

      // ── Cancel pending alarms when dose is actively marked ──────────────
      // When a patient marks a dose as 'taken' or 'taken_late' we must
      // cancel any still-pending Stage 1 (+10 min) and Stage 2 (+20 min)
      // alarms for this specific slot so they don't fire after the patient
      // has already acted. We also reset the SharedPreferences stage counter
      // so the Mark-As sheet returns to the correct enabled/disabled state.
      //
      // We do NOT cancel when newStatus is null (Undo) — in that case the
      // alarms are already gone (they already fired to reach stage >= 1, or
      // we're inside the initial window and the original Stage 0 already
      // fired). The patient used Undo to clear a mistaken tap; we just
      // remove the Firestore record and leave the alarm state as-is.
      if (newStatus == 'taken' || newStatus == 'taken_late') {
        final medId = med.id ?? med.name;
        await _notifService.cancelSlotStages(
          medId,
          widget.timeIndex,
          medName: med.name,
          dose:    med.dose,
          unit:    med.unit,
          hour:    widget.hour,
          minute:  widget.minute,
          period:  widget.period,
        );
        await _notifService.resetAlertStage(medId, timeIndex: widget.timeIndex);
        if (mounted) setState(() => _alertStage = 0);
      }
    } catch (e) {
      setState(() => _localStatus = widget.status);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('Could not save: $e'),
            backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showActionSheet(BuildContext context) async {
    await _refreshStage();
    if (!context.mounted) return;

    final theme      = Theme.of(context);
    final sheetBg    = theme.colorScheme.surface;
    final onSurface  = theme.colorScheme.onSurface;
    final bottomPad  = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom + 16;

    final takenActive     = _takenActive;
    final takenLateActive = _takenLateActive;
    final showSkippedInfo = _showSkippedInfo;
    final showBanner      = _showBanner;

    showModalBottomSheet(
      context:            context,
      backgroundColor:    Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(med.name,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: onSurface)),
            Text(
              '${med.dose} ${med.unit}  ·  '
              '${widget.hour.toString().padLeft(2, '0')}:'
              '${widget.minute.toString().padLeft(2, '0')} ${widget.period}',
              style: TextStyle(fontSize: 13, color: onSurface.withOpacity(0.5)),
            ),
            if (showBanner) ...[
              const SizedBox(height: 12),
              _ContextBanner(
                isExpired:  showSkippedInfo,
                alertStage: _alertStage,
                onSurface:  onSurface,
              ),
            ],
            const SizedBox(height: 16),
            _ActionTile(
              icon:     Icons.check_circle_outline,
              color:    const Color(0xFF2BC8A7),
              label:    'Taken',
              subtitle: 'I took it on time',
              enabled:  takenActive,
              onTap: takenActive
                  ? () { Navigator.pop(sheetCtx); _handleStatusChange(context, 'taken'); }
                  : null,
            ),
            _ActionTile(
              icon:     Icons.watch_later_outlined,
              color:    const Color(0xFFFFA726),
              label:    'Taken Late',
              subtitle: 'I took it, but late',
              enabled:  takenLateActive,
              onTap: takenLateActive
                  ? () { Navigator.pop(sheetCtx); _handleStatusChange(context, 'taken_late'); }
                  : null,
            ),
            if (showSkippedInfo)
              _SkippedInfoRow(onSurface: onSurface)
            else
              _ActionTile(
                icon:     Icons.cancel_outlined,
                color:    const Color(0xFFEF5350),
                label:    'Skipped',
                subtitle: 'I did not take it',
                enabled:  false,
                onTap:    null,
              ),
            // Undo only for taken/taken_late — not for auto-skipped records.
            if (_localStatus == 'taken' || _localStatus == 'taken_late')
              _ActionTile(
                icon:     Icons.undo_outlined,
                color:    onSurface.withOpacity(0.4),
                label:    'Undo',
                subtitle: 'Clear this record',
                enabled:  true,
                onTap: () { Navigator.pop(sheetCtx); _handleStatusChange(context, null); },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acc       = context.watch<AccessibilityProvider>();
    final theme     = Theme.of(context);
    final surface   = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final btnV      = 8.0  * acc.buttonScaleFactor;
    final btnH      = 12.0 * acc.buttonScaleFactor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: _localStatus != null
            ? Border.all(color: _statusColor.withOpacity(0.4), width: 1.5)
            : (_windowExpired && !_alreadyTakenOnTime)
                ? Border.all(
                    color: const Color(0xFFEF5350).withOpacity(0.2), width: 1)
                : null,
      ),
      child: Opacity(
        opacity: (_windowExpired && _localStatus == null) ? 0.75 : 1.0,
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Column(
                children: [
                  Text(
                    '${widget.hour.toString().padLeft(2, '0')}:'
                    '${widget.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: onSurface),
                  ),
                  Text(widget.period,
                      style: TextStyle(
                          fontSize: 12, color: onSurface.withOpacity(0.45))),
                ],
              ),
            ),
            Container(
              width: 1, height: 48,
              color: onSurface.withOpacity(0.08),
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
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
                        Text(med.name,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: onSurface)),
                        const SizedBox(height: 4),
                        Text('${med.dose} ${med.unit}  ·  ${med.type}',
                            style: TextStyle(
                                fontSize: 12,
                                color: onSurface.withOpacity(0.45))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _saving ? null : () => _showActionSheet(context),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: btnH, vertical: btnV),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _saving
                    ? SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _statusColor))
                    : Text(_statusLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusColor)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildMedImage(String imageUrl) {
    if (imageUrl.startsWith('data:')) {
      try {
        final b64 = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        return Image.memory(base64Decode(b64),
            width: 40, height: 40, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink());
      } catch (_) {}
    }
    return const SizedBox.shrink();
  }
}

// ── Context banner ────────────────────────────────────────────────────────────

class _ContextBanner extends StatelessWidget {
  final bool  isExpired;
  final int   alertStage;
  final Color onSurface;
  const _ContextBanner(
      {required this.isExpired,
      required this.alertStage,
      required this.onSurface});

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = isExpired
        ? (
            Icons.warning_amber_rounded,
            const Color(0xFFEF5350),
            'The intake window for this dose has closed.\n'
                'It has been recorded as Skipped. '
                'You may still mark it as "Taken Late".',
          )
        : (
            Icons.access_time_outlined,
            const Color(0xFFFFA726),
            'Follow-up reminder sent (+10 min).\n'
                'Only "Taken Late" is available now.',
          );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withOpacity(0.75),
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ── Skipped info row ──────────────────────────────────────────────────────────

class _SkippedInfoRow extends StatelessWidget {
  final Color onSurface;
  const _SkippedInfoRow({required this.onSurface});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFEF5350);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: const Icon(Icons.cancel_outlined, color: color, size: 22),
        ),
        title: Text('Skipped (auto-recorded)',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: onSurface.withOpacity(0.4))),
        subtitle: Text('Recorded after the intake window closed',
            style: TextStyle(
                fontSize: 12, color: onSurface.withOpacity(0.3))),
      ),
    );
  }
}

// ── Action tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData      icon;
  final Color         color;
  final String        label;
  final String        subtitle;
  final bool          enabled;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface      = Theme.of(context).colorScheme.onSurface;
    final effectiveColor = enabled ? color : onSurface.withOpacity(0.25);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: effectiveColor.withOpacity(0.12),
        child: Icon(icon, color: effectiveColor, size: 22),
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: enabled ? onSurface : onSurface.withOpacity(0.3))),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: enabled
                  ? onSurface.withOpacity(0.5)
                  : onSurface.withOpacity(0.25))),
      onTap: onTap,
    );
  }
}

// ── Patient settings tab ──────────────────────────────────────────────────────

class _PatientSettingsTab extends StatelessWidget {
  const _PatientSettingsTab();

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
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Sign Out', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService().signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user      = FirebaseAuth.instance.currentUser;
    final theme     = Theme.of(context);
    final surface   = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final primary   = theme.colorScheme.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: onSurface)),
            const SizedBox(height: 24),
            StreamBuilder<Map<String, dynamic>?>(
              stream: ProfileService().profileStream(),
              builder: (context, snap) {
                final profileData = snap.data;
                final displayName =
                    (profileData?['name'] as String?)?.isNotEmpty == true
                        ? profileData!['name'] as String
                        : user?.displayName ?? 'Patient';
                final profileImageUrl =
                    profileData?['profileImageUrl'] as String?;

                Widget avatar;
                if (profileImageUrl != null &&
                    profileImageUrl.startsWith('data:')) {
                  try {
                    final b64 = profileImageUrl.contains(',')
                        ? profileImageUrl.split(',').last
                        : profileImageUrl;
                    avatar = CircleAvatar(
                        radius: 28,
                        backgroundImage: MemoryImage(base64Decode(b64)));
                  } catch (_) {
                    avatar = _defaultAvatar(displayName, primary);
                  }
                } else {
                  avatar = _defaultAvatar(displayName, primary);
                }

                return GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileSettingsScreen())),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        avatar,
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(displayName,
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: onSurface)),
                              Text(user?.email ?? '',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: onSurface.withOpacity(0.45))),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('Patient',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: primary,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_outlined,
                            size: 18,
                            color: onSurface.withOpacity(0.35)),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _SettingsTile(
                icon: Icons.edit_outlined,
                label: 'Edit Profile',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProfileSettingsScreen()))),
            const SizedBox(height: 12),
            _SettingsTile(
                icon: Icons.accessibility_new_rounded,
                label: 'Accessibility',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const AccessibilitySettingsScreen()))),
            const SizedBox(height: 12),
            _SettingsTile(
                icon: Icons.notifications_outlined,
                label: 'Notification Settings',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const NotificationSettingsScreen()))),
            const SizedBox(height: 12),
            _SettingsTile(
                icon: Icons.logout,
                label: 'Sign Out',
                color: Colors.red,
                onTap: () => _signOut(context)),
          ],
        ),
      ),
    );
  }

  Widget _defaultAvatar(String name, Color primary) => CircleAvatar(
        radius: 28,
        backgroundColor: primary,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'P',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color?       color;
  final VoidCallback onTap;

  const _SettingsTile(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final c       = color ?? theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 14),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c))),
            Icon(Icons.chevron_right, color: c.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}