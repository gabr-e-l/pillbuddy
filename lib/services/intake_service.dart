// lib/services/intake_service.dart
//
// Persists per-dose intake status to Firestore.
//
// Path: users/{uid}/intakes/{date}_{medId}
// Status values: 'taken' | 'taken_late' | 'skipped'
//
// NOTE: 'snoozed' has been removed. The three-stage alarm flow in
// NotificationService handles timing; statuses are now limited to the
// three above.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class IntakeService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _intakesRef =>
      _db.collection('users').doc(_uid).collection('intakes');

  String _docId(String medId, DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}_$medId';

  /// Record or update the status of a dose for a given date.
  /// [status] must be one of: 'taken' | 'taken_late' | 'skipped'
  Future<void> recordIntake({
    required String  medId,
    required String  medName,
    required String  status,
    DateTime?        date,
  }) async {
    final d       = date ?? DateTime.now();
    final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    await _intakesRef.doc(_docId(medId, d)).set({
      'medId':      medId,
      'medName':    medName,
      'status':     status,
      'date':       dateStr,
      'recordedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream of { medId → status } for a given date.
  Stream<Map<String, String>> intakesForDateStream(DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    return _intakesRef
        .where('date', isEqualTo: dateStr)
        .snapshots()
        .map((snap) => {
              for (final doc in snap.docs)
                doc.data()['medId'] as String: doc.data()['status'] as String,
            });
  }

  /// Delete an intake record (undo a marking).
  Future<void> deleteIntake({required String medId, DateTime? date}) async {
    final d = date ?? DateTime.now();
    await _intakesRef.doc(_docId(medId, d)).delete();
  }
}
