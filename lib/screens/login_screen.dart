// lib/screens/login_screen.dart
//
// Changes:
//   - After successful sign-in, fetches the user's role from Firestore.
//   - Routes to PatientHome or CaregiverHome based on role.
//   - Added "Continue with Google" button that calls AuthService.signInWithGoogle
//     with the role already stored in Firestore (sign-in, not sign-up).

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'patient_home.dart';
import 'caregiver_home.dart';
import 'onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _navigateHome(String? role) {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            role == 'caregiver' ? const CaregiverHome() : const PatientHome(),
      ),
      (route) => false,
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  // ── Email/password sign-in ──────────────────────────────────────────────────

  void _onSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final cred = await _authService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      final role = await _authService.fetchRole(cred.user!.uid);

      _navigateHome(role);
      _showSnack('Welcome back to PillBuddy!');
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => 'No account found with this email.',
        'wrong-password' => 'Incorrect password. Please try again.',
        'invalid-email' => 'Please enter a valid email address.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => 'Sign-in failed. Please try again.',
      };
      _showSnack(message, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google sign-in ──────────────────────────────────────────────────────────
  //
  // For sign-in we still pass a dummy role because AuthService.signInWithGoogle
  // is used for BOTH sign-up and sign-in.  For existing accounts the role stored
  // in Firestore is authoritative; we just need any non-conflicting value here.
  // We pass an empty string so that the role-conflict check passes for ANY
  // already-registered Google account (existing role ≠ '').
  //
  // The actual routing uses the Firestore role, same as email/password flow.

  void _onGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      // Pass a sentinel that won't conflict with 'patient' or 'caregiver'
      // so existing Google accounts can sign in regardless of their role.
      final cred = await _authService.signInWithGoogleForLogin();
      if (cred == null) return; // user cancelled

      if (!mounted) return;
      final role = await _authService.fetchRole(cred.user!.uid);

      if (role == null) {
        // Google account exists in Firebase Auth but has no Firestore doc.
        // This shouldn't happen in normal flow — ask the user to sign up first.
        _showSnack(
          'No PillBuddy account found for this Google account. '
          'Please sign up first.',
          isError: true,
        );
        await _authService.signOut();
        return;
      }

      _navigateHome(role);
      _showSnack('Welcome back to PillBuddy!');
    } on FirebaseAuthException catch (e) {
      _showSnack(
        e.message ?? 'Google sign-in failed. Please try again.',
        isError: true,
      );
    } catch (_) {
      _showSnack('Google sign-in failed. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF2BC8A7);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 12),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.arrow_back_ios,
                      size: 20, color: Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),

                      // Logo
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/pillbuddy_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                              Icons.medication_liquid_outlined,
                              color: Color(0xFF2BC8A7),
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      const Text(
                        'Welcome Back',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sign in to your PillBuddy account',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black45,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Email
                      const _FieldLabel(label: 'Email'),
                      const SizedBox(height: 8),
                      _InputField(
                        controller: _emailController,
                        hintText: 'Enter your email',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(v.trim())) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Password
                      const _FieldLabel(label: 'Password'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _onSignIn(),
                        style: const TextStyle(
                            fontSize: 15, color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: 'Enter your password',
                          hintStyle: const TextStyle(
                              color: Colors.black38, fontSize: 14),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF1A6BFF), width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Colors.redAccent, width: 1.2),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Colors.redAccent, width: 1.5),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.black38,
                              size: 20,
                            ),
                            onPressed: () => setState(() =>
                                _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 36),

                      // Sign In button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _onSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            disabledBackgroundColor:
                                accentColor.withOpacity(0.6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // OR divider
                      Row(
                        children: [
                          const Expanded(
                              child: Divider(color: Colors.black12)),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: TextStyle(
                                color: Colors.black38,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Expanded(
                              child: Divider(color: Colors.black12)),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Continue with Google
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed:
                              _isGoogleLoading ? null : _onGoogleSignIn,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: Color(0xFFDADCE0), width: 1.5),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: _isGoogleLoading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: accentColor,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _GoogleLogo(size: 22),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Continue with Google',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Center(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 14, color: Colors.black45),
                            children: [
                              const TextSpan(text: "Don't have an account?  "),
                              TextSpan(
                                text: 'Sign Up',
                                style: const TextStyle(
                                  color: Color(0xFF1A6BFF),
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const OnboardingScreen()),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Google Logo ────────────────────────────────────────────────────────────────

class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Accurate vector reproduction of the official multi-colour Google "G"
    // mark (18×18 design grid), scaled to fit the requested size. The
    // previous implementation approximated the G with pie-slice arcs cut
    // out by a white circle, which produced visible gaps/seams — this
    // version uses the actual logo path geometry instead.
    final double k = size.width / 18.0;
    final Paint p = Paint()..style = PaintingStyle.fill;

    // Blue
    p.color = const Color(0xFF4285F4);
    canvas.drawPath(
      Path()
        ..moveTo(17.64 * k, 9.2045 * k)
        ..cubicTo(17.64 * k, 8.5664 * k, 17.5827 * k, 7.9527 * k,
            17.4764 * k, 7.3636 * k)
        ..lineTo(9 * k, 7.3636 * k)
        ..lineTo(9 * k, 10.845 * k)
        ..lineTo(13.8436 * k, 10.845 * k)
        ..cubicTo(13.635 * k, 11.97 * k, 13.0009 * k, 12.9232 * k,
            12.0477 * k, 13.5614 * k)
        ..lineTo(12.0477 * k, 15.8195 * k)
        ..lineTo(14.9564 * k, 15.8195 * k)
        ..cubicTo(16.6582 * k, 14.2527 * k, 17.64 * k, 11.9455 * k,
            17.64 * k, 9.2045 * k)
        ..close(),
      p,
    );

    // Green
    p.color = const Color(0xFF34A853);
    canvas.drawPath(
      Path()
        ..moveTo(9 * k, 18 * k)
        ..cubicTo(11.43 * k, 18 * k, 13.4673 * k, 17.194 * k, 14.9564 * k,
            15.8195 * k)
        ..lineTo(12.0477 * k, 13.5614 * k)
        ..cubicTo(11.2418 * k, 14.1018 * k, 10.2109 * k, 14.4219 * k,
            9 * k, 14.4219 * k)
        ..cubicTo(6.6555 * k, 14.4219 * k, 4.6718 * k, 12.8383 * k,
            3.9636 * k, 10.7115 * k)
        ..lineTo(0.9573 * k, 10.7115 * k)
        ..lineTo(0.9573 * k, 13.0433 * k)
        ..cubicTo(2.4382 * k, 15.9832 * k, 5.4818 * k, 18 * k, 9 * k, 18 * k)
        ..close(),
      p,
    );

    // Yellow
    p.color = const Color(0xFFFBBC05);
    canvas.drawPath(
      Path()
        ..moveTo(3.9636 * k, 10.71 * k)
        ..cubicTo(3.7836 * k, 10.1696 * k, 3.6813 * k, 9.5932 * k,
            3.6813 * k, 9.0 * k)
        ..cubicTo(3.6813 * k, 8.4068 * k, 3.7836 * k, 7.8304 * k,
            3.9636 * k, 7.29 * k)
        ..lineTo(3.9636 * k, 4.9582 * k)
        ..lineTo(0.9573 * k, 4.9582 * k)
        ..cubicTo(0.3477 * k, 6.1732 * k, 0.0, 7.5477 * k, 0.0, 9 * k)
        ..cubicTo(0.0, 10.4523 * k, 0.3477 * k, 11.8268 * k, 0.9573 * k,
            13.0418 * k)
        ..lineTo(3.9636 * k, 10.71 * k)
        ..close(),
      p,
    );

    // Red
    p.color = const Color(0xFFEA4335);
    canvas.drawPath(
      Path()
        ..moveTo(9 * k, 3.5795 * k)
        ..cubicTo(10.3214 * k, 3.5795 * k, 11.5077 * k, 4.0336 * k,
            12.4405 * k, 4.9255 * k)
        ..lineTo(15.0218 * k, 2.3441 * k)
        ..cubicTo(13.4632 * k, 0.8918 * k, 11.4259 * k, 0.0, 9 * k, 0.0)
        ..cubicTo(5.4818 * k, 0.0, 2.4382 * k, 2.0168 * k, 0.9573 * k,
            4.9582 * k)
        ..lineTo(3.9636 * k, 7.29 * k)
        ..cubicTo(4.6718 * k, 5.1632 * k, 6.6555 * k, 3.5795 * k, 9 * k,
            3.5795 * k)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Reusable widgets ───────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      );
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final String? Function(String?)? validator;

  const _InputField({
    required this.controller,
    required this.hintText,
    required this.keyboardType,
    required this.textInputAction,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFF1A6BFF), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Colors.redAccent, width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
        validator: validator,
      );
}