// lib/services/caregiver_service.dart
//
// All Firestore operations a caregiver can perform:
//   - Link a patient by email
//   - Stream the list of linked patients
//   - Full CRUD on a patient's medications
//
// Firestore layout:
//   users/{uid}                         ← user profile (role, name, etc.)
//   caregivers/{caregiverUid}/
//     patients/{patientUid}             ← link doc  { name, email, linkedAt }
//   users/{patientUid}/medications/{id} ← patient meds (written by caregiver)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication_model.dart';

class CaregiverService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _caregiverUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _patientsRef =>
      _db.collection('caregivers').doc(_caregiverUid).collection('patients');

  // ── Link patient ───────────────────────────────────────────────────────────

  /// Searches for a user with [email] whose role is 'patient'.
  /// Creates a link doc under caregivers/{cid}/patients/{pid}.
  /// Also writes a back-link on the patient's doc so they know who their caregiver is.
  Future<void> linkPatientByEmail(String email) async {
    // 1. Find user with that email
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .where('role', isEqualTo: 'patient')
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception(
          'No patient account found with that email. '
          'Make sure they have signed up as a Patient first.');
    }

    final patientDoc = query.docs.first;
    final patientUid = patientDoc.id;
    final patientData = patientDoc.data();

    // 2. Check not already linked
    final existing = await _patientsRef.doc(patientUid).get();
    if (existing.exists) {
      throw Exception('This patient is already linked to your account.');
    }

    // 3. Write caregiver → patient link
    await _patientsRef.doc(patientUid).set({
      'uid': patientUid,
      'name': patientData['name'] ?? '',
      'email': patientData['email'] ?? email,
      'linkedAt': FieldValue.serverTimestamp(),
    });

    // 4. Write patient → caregiver back-link
    final caregiverDoc =
        await _db.collection('users').doc(_caregiverUid).get();
    await _db
        .collection('users')
        .doc(patientUid)
        .collection('caregivers')
        .doc(_caregiverUid)
        .set({
      'uid': _caregiverUid,
      'name': caregiverDoc.data()?['name'] ?? '',
      'email': caregiverDoc.data()?['email'] ?? '',
      'linkedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes the caregiver ↔ patient link (does not delete their medications).
  Future<void> unlinkPatient(String patientUid) async {
    await _patientsRef.doc(patientUid).delete();
    await _db
        .collection('users')
        .doc(patientUid)
        .collection('caregivers')
        .doc(_caregiverUid)
        .delete();
  }

  // ── Read patients ──────────────────────────────────────────────────────────

  /// Real-time stream of all linked patients.
  Stream<List<Map<String, dynamic>>> patientsStream() {
    return _patientsRef
        .orderBy('linkedAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // ── Patient medications CRUD ───────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _medsRef(String patientUid) =>
      _db.collection('users').doc(patientUid).collection('medications');

  Stream<List<MedicationModel>> patientMedicationsStream(String patientUid) {
    return _medsRef(patientUid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(MedicationModel.fromDoc).toList());
  }

  Future<String> addMedication(String patientUid, MedicationModel med) async {
    final doc = await _medsRef(patientUid).add(med.toMap());
    return doc.id;
  }

  Future<void> updateMedication(
      String patientUid, String medId, MedicationModel med) async {
    final map = med.toMap()..remove('createdAt');
    await _medsRef(patientUid).doc(medId).update(map);
  }

  Future<void> deleteMedication(String patientUid, String medId) async {
    await _medsRef(patientUid).doc(medId).delete();
  }
}