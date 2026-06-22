// lib/services/medication_service.dart
//
// All Firestore operations for medications.
// Data lives at:  users/{uid}/medications/{medId}
//
// Usage:
//   final svc = MedicationService();
//   await svc.addMedication(med);
//   Stream<List<MedicationModel>> stream = svc.medicationsStream();

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication_model.dart';

class MedicationService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Returns the medications collection for the current user.
  CollectionReference<Map<String, dynamic>> get _medsRef {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not signed in');
    return _db.collection('users').doc(uid).collection('medications');
  }

  // ── Create ────────────────────────────────────────────────────────────────

  /// Add a new medication and return its generated Firestore ID.
  Future<String> addMedication(MedicationModel med) async {
    final doc = await _medsRef.add(med.toMap());
    return doc.id;
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Real-time stream of all medications, ordered by creation time.
  Stream<List<MedicationModel>> medicationsStream() {
    return _medsRef
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(MedicationModel.fromDoc).toList());
  }

  /// Fetch a single medication by ID (one-time read).
  Future<MedicationModel?> getMedication(String medId) async {
    final doc = await _medsRef.doc(medId).get();
    if (!doc.exists) return null;
    return MedicationModel.fromDoc(doc);
  }

  /// Real-time stream of a single medication document. Used by screens like
  /// Medication Details so fields that change outside the screen itself
  /// (e.g. stockCount being decremented when a dose is marked taken on the
  /// Home tab) are reflected live instead of staying frozen at whatever
  /// snapshot the screen was opened with.
  Stream<MedicationModel?> medicationStream(String medId) {
    return _medsRef.doc(medId).snapshots().map(
        (doc) => doc.exists ? MedicationModel.fromDoc(doc) : null);
  }

  // ── Update ────────────────────────────────────────────────────────────────

  /// Update an existing medication document.
  ///
  /// IMPORTANT: MedicationModel.toMap() always includes
  /// 'createdAt': FieldValue.serverTimestamp() (so addMedication() above
  /// gets a correct creation time on insert). Firestore's .update() only
  /// touches the fields present in the map it's given, so stripping
  /// 'createdAt' here before calling .update() means the original creation
  /// timestamp is left untouched on every subsequent edit instead of being
  /// silently overwritten on each save.
  Future<void> updateMedication(String medId, MedicationModel med) async {
    final map = med.toMap()..remove('createdAt'); // don't overwrite timestamp
    await _medsRef.doc(medId).update(map);
  }

  /// Update only specific fields (partial update).
  Future<void> updateFields(
      String medId, Map<String, dynamic> fields) async {
    await _medsRef.doc(medId).update(fields);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  /// Permanently delete a medication document.
  Future<void> deleteMedication(String medId) async {
    await _medsRef.doc(medId).delete();
  }
}