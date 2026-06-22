// lib/services/intake_service.dart
//
// Persists per-dose intake status to Firestore.
//
// Path: users/{uid}/intakes/{date}_{medId}_{timeIndex}
// Status values: 'taken' | 'taken_late' | 'skipped'
//
// NOTE: 'snoozed' has been removed. The three-stage alarm flow in
// NotificationService handles timing; statuses are now limited to the
// three above.
//
// ── Multi-intake-time fix ───────────────────────────────────────────────
//
// Previously the Firestore doc id (and the stream's map key) was just
// {date}_{medId}, meaning a medication with multiple daily intake times
// (e.g. "every 8 hours") had exactly ONE status slot per day no matter how
// many doses it actually has. Marking any one dose "Taken" would silently
// apply to all of them, because they were literally the same document.
//
// [timeIndex] now identifies *which* configured intake time (0-based,
// matching MedicationModel.intakeTimes order — same indexing
// NotificationService already uses for alarms) a given status belongs to.
// Defaults to 0 so single-time medications keep using the same doc id
// shape as before ({date}_{medId}_0 — note this DOES change existing doc
// ids; see migration note at the bottom of this file).
//
// The stream now emits Map<String, String> keyed by '{medId}_{timeIndex}'
// instead of bare medId, so callers must look up status with that same
// composite key.
//
// ── Stock auto-decrement ─────────────────────────────────────────────────
//
// recordIntake() and deleteIntake() also keep the medication's stockCount
// in sync with what was actually consumed:
//   • Marking a dose 'taken' or 'taken_late' decrements stockCount by 1,
//     but ONLY the first time a dose transitions into a "consumed" state —
//     editing 'taken' → 'taken_late' (or vice versa) does not decrement
//     again, since exactly one dose was physically taken either way.
//   • Moving a dose AWAY from a consumed state (e.g. correcting 'taken' to
//     'skipped', or using "Undo" to delete the record entirely) restores
//     +1 to stockCount, since that dose is no longer counted as consumed.
//   • stockCount is clamped to a minimum of 0 so a desynced count can never
//     go negative.
//
// Both the intake doc and the medication doc are updated inside a single
// Firestore transaction so the stock count can never drift out of sync with
// the recorded intake history (e.g. due to a write succeeding for one but
// failing for the other).
//
// ── Migration note ───────────────────────────────────────────────────────
//
// Existing intake docs in Firestore were written with the OLD id shape
// ({date}_{medId}, no trailing _0). Those old docs will simply no longer
// be matched by the new {date}_{medId}_0 id, so today's already-recorded
// statuses for single-dose medications may appear to "reset" once. This
// is a one-time cosmetic issue (history under the old doc ids is not
// deleted, just orphaned) — flag if you want a backfill script instead of
// letting it lapse naturally.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class IntakeService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const _consumedStatuses = {'taken', 'taken_late'};

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _intakesRef =>
      _db.collection('users').doc(_uid).collection('intakes');

  CollectionReference<Map<String, dynamic>> get _medsRef =>
      _db.collection('users').doc(_uid).collection('medications');

  String _docId(String medId, int timeIndex, DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}_${medId}_$timeIndex';

  /// Composite key used in the stream's returned map and expected by
  /// callers (e.g. patient_home.dart) when looking up a dose's status.
  static String mapKey(String medId, int timeIndex) => '${medId}_$timeIndex';

  /// Record or update the status of a dose for a given date and intake-time
  /// slot. [status] must be one of: 'taken' | 'taken_late' | 'skipped'
  ///
  /// [timeIndex] identifies which of the medication's (possibly multiple)
  /// daily intake times this status belongs to — defaults to 0 for
  /// single-time medications.
  ///
  /// Adjusts the medication's stockCount by ±1 when the dose transitions
  /// into or out of a "consumed" state (taken / taken_late) — see file
  /// header for the full rule.
  Future<void> recordIntake({
    required String  medId,
    required String  medName,
    required String  status,
    int               timeIndex = 0,
    DateTime?         date,
  }) async {
    final d       = date ?? DateTime.now();
    final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    final intakeDocRef = _intakesRef.doc(_docId(medId, timeIndex, d));
    final medDocRef    = _medsRef.doc(medId);

    await _db.runTransaction<void>((txn) async {
      // All reads must happen before any writes in a Firestore transaction,
      // so read both docs up front regardless of whether we'll end up
      // needing the medication doc.
      final DocumentSnapshot<Map<String, dynamic>> intakeSnap =
          await txn.get(intakeDocRef);
      final previousStatus = intakeSnap.exists
          ? (intakeSnap.data()?['status'] as String?)
          : null;

      final wasConsumed = _consumedStatuses.contains(previousStatus);
      final isConsumed  = _consumedStatuses.contains(status);
      final stockTransition = wasConsumed != isConsumed;

      DocumentSnapshot<Map<String, dynamic>>? medSnap;
      if (stockTransition) {
        medSnap = await txn.get(medDocRef);
      }

      txn.set(intakeDocRef, {
        'medId':      medId,
        'medName':    medName,
        'status':     status,
        'timeIndex':  timeIndex,
        'date':       dateStr,
        'recordedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!stockTransition) {
        // No transition between consumed / not-consumed — e.g. correcting
        // 'taken' -> 'taken_late', or 'skipped' -> 'skipped'. Stock already
        // reflects the right state, so don't touch it.
        return;
      }

      if (medSnap == null || !medSnap.exists) return; // medication may have been deleted

      final currentStock = (medSnap.data()?['stockCount'] as num?)?.toInt() ?? 0;
      final delta = isConsumed ? -1 : 1; // newly consumed → -1, reverted → +1
      final newStock = (currentStock + delta).clamp(0, 1 << 30).toInt();

      txn.update(medDocRef, {'stockCount': newStock});
    });
  }

  /// Stream of { '{medId}_{timeIndex}' → status } for a given date.
  ///
  /// Keyed by the composite mapKey (not bare medId) so multiple intake
  /// times for the same medication each resolve to an independent status.
  /// Falls back to timeIndex 0 for any legacy doc that doesn't carry a
  /// 'timeIndex' field (e.g. docs written before this fix).
  Stream<Map<String, String>> intakesForDateStream(DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    return _intakesRef
        .where('date', isEqualTo: dateStr)
        .snapshots()
        .map((snap) => {
              for (final doc in snap.docs)
                mapKey(
                  doc.data()['medId'] as String,
                  (doc.data()['timeIndex'] as num?)?.toInt() ?? 0,
                ): doc.data()['status'] as String,
            });
  }

  /// Delete an intake record (undo a marking) for a given date/time-slot.
  ///
  /// If the deleted record was 'taken' or 'taken_late', restores +1 to the
  /// medication's stockCount since that dose is no longer counted as
  /// consumed (mirrors the restore behaviour in recordIntake).
  Future<void> deleteIntake({
    required String medId,
    int             timeIndex = 0,
    DateTime?       date,
  }) async {
    final d = date ?? DateTime.now();
    final intakeDocRef = _intakesRef.doc(_docId(medId, timeIndex, d));
    final medDocRef    = _medsRef.doc(medId);

    await _db.runTransaction<void>((txn) async {
      final DocumentSnapshot<Map<String, dynamic>> intakeSnap =
          await txn.get(intakeDocRef);
      if (!intakeSnap.exists) return;

      final previousStatus = intakeSnap.data()?['status'] as String?;
      final wasConsumed = _consumedStatuses.contains(previousStatus);

      // All reads must happen before any writes in a Firestore transaction.
      DocumentSnapshot<Map<String, dynamic>>? medSnap;
      if (wasConsumed) {
        medSnap = await txn.get(medDocRef);
      }

      txn.delete(intakeDocRef);

      if (!wasConsumed || medSnap == null || !medSnap.exists) return;

      final currentStock = (medSnap.data()?['stockCount'] as num?)?.toInt() ?? 0;
      final newStock = (currentStock + 1).clamp(0, 1 << 30).toInt();
      txn.update(medDocRef, {'stockCount': newStock});
    });
  }
}