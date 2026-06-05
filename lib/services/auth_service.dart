// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Register ───────────────────────────────────────────────────────────────

  Future<UserCredential> registerPatient({
    required String name,
    required String email,
    required String password,
  }) async {
    // Always store email in lowercase so caregiver email-lookup queries match.
    final normalizedEmail = email.trim().toLowerCase();
    final cred = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    await cred.user!.updateDisplayName(name);
    await _db.collection('users').doc(cred.user!.uid).set({
      'uid': cred.user!.uid,
      'name': name,
      'email': normalizedEmail,
      'role': 'patient',
      'avatarIndex': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return cred;
  }

  Future<UserCredential> registerCaregiver({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final cred = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    await cred.user!.updateDisplayName(name);
    await _db.collection('users').doc(cred.user!.uid).set({
      'uid': cred.user!.uid,
      'name': name,
      'email': normalizedEmail,
      'role': 'caregiver',
      'avatarIndex': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return cred;
  }

  // ── Sign In ────────────────────────────────────────────────────────────────

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // ── Role fetch ─────────────────────────────────────────────────────────────

  /// Returns 'patient', 'caregiver', or null if not found.
  Future<String?> fetchRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['role'] as String?;
  }

  // ── Sign Out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async => _auth.signOut();
}