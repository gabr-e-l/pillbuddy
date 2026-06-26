// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'caregiver_intake_cache.dart';

/// Thrown when a Google account is already registered under a different role.
class RoleConflictException implements Exception {
  final String existingRole;
  const RoleConflictException(this.existingRole);

  @override
  String toString() => 'RoleConflictException: account is registered as $existingRole';
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Register (email/password) ───────────────────────────────────────────────

  Future<UserCredential> registerPatient({
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

  // ── Google Sign-In / Sign-Up ────────────────────────────────────────────────

  /// Signs in (or registers) with Google for the given [role].
  ///
  /// Behaviour:
  ///   • New account  → creates Firestore doc with [role] and returns.
  ///   • Existing account, same role → signs in normally.
  ///   • Existing account, different role → signs out and throws [RoleConflictException].
  ///
  /// Returns null if the user cancelled the Google account picker.
  Future<UserCredential?> signInWithGoogle({required String role}) async {
    // Trigger the Google account chooser
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final cred = await _auth.signInWithCredential(credential);
    final uid = cred.user!.uid;
    final docRef = _db.collection('users').doc(uid);
    final doc = await docRef.get();

    if (doc.exists) {
      // ── Returning user: enforce role consistency ───────────────────────────
      final existingRole = doc.data()?['role'] as String?;
      if (existingRole != null && existingRole != role) {
        // This Google account belongs to a different role — reject.
        await _auth.signOut();
        await _googleSignIn.signOut();
        throw RoleConflictException(existingRole);
      }
      // Same role: nothing extra to write; fall through and return.
    } else {
      // ── New user: create Firestore profile ────────────────────────────────
      final user = cred.user!;
      await docRef.set({
        'uid': uid,
        'name': user.displayName ?? googleUser.email.split('@').first,
        'email': user.email ?? googleUser.email,
        'role': role,
        'avatarIndex': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    return cred;
  }

  /// Sign-in-only variant: opens the Google picker and signs in with whatever
  /// account the user picks.  No role is written — the existing Firestore doc
  /// (if any) is left untouched.  The caller is responsible for reading the
  /// role from Firestore and routing accordingly.
  ///
  /// Returns null if the user cancelled the picker.
  Future<UserCredential?> signInWithGoogleForLogin() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential);
  }

  // ── Sign In (email/password) ────────────────────────────────────────────────

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

  Future<void> signOut() async {
    await CaregiverIntakeCache.instance.clear();
    // Sign out from Google as well so the account picker shows next time.
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}