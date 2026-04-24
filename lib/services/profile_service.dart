// lib/services/profile_service.dart
//
// Reads and writes the user profile stored at:
//   users/{uid}/profile  (single document)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> get _profileRef {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not signed in');
    return _db.collection('users').doc(uid);
  }

  /// Save (merge) profile fields into the user document.
  Future<void> saveProfile({
    required String name,
    DateTime? dateOfBirth,
    required String gender,
    required int avatarIndex,
  }) async {
    await _profileRef.set({
      'name': name,
      'dateOfBirth':
          dateOfBirth != null ? Timestamp.fromDate(dateOfBirth) : null,
      'gender': gender,
      'avatarIndex': avatarIndex,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Fetch the profile once and return it as a Map.
  Future<Map<String, dynamic>?> getProfile() async {
    final doc = await _profileRef.get();
    return doc.data();
  }

  /// Real-time stream of the profile document.
  Stream<Map<String, dynamic>?> profileStream() {
    return _profileRef.snapshots().map((doc) => doc.data());
  }
}