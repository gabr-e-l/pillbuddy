// lib/screens/signup_screen.dart
//
// Changes:
//   - Added a DefaultTabController with two tabs: "Email" and "Google".
//   - "Continue with Google" tab triggers AuthService.signInWithGoogle().
//   - Role-conflict guard: shows an error if the Google account is already
//     registered under the opposite role.
//   - Email/password flow is unchanged.

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'patient_home.dart';
import 'caregiver_home.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  final String role; // 'patient' | 'caregiver'
  const SignUpScreen({super.key, required this.role});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  late final TabController _tabController;

  bool get _isPatient => widget.role == 'patient';

  Color get roleColor =>
      _isPatient ? const Color(0xFF1A6BFF) : const Color(0xFF2BC8A7);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _navigateHome() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _isPatient ? const PatientHome() : const CaregiverHome(),
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

  // ── Email/password sign-up ──────────────────────────────────────────────────

  void _onCreateAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      if (_isPatient) {
        await _authService.registerPatient(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await _authService.registerCaregiver(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }

      _navigateHome();
      _showSnack(
        'Welcome to PillBuddy${_isPatient ? ' as a Patient' : ' as a Caregiver'}!',
      );
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'email-already-in-use' => 'This email is already registered.',
        'invalid-email' => 'Please enter a valid email address.',
        'weak-password' => 'Password should be at least 6 characters.',
        _ => 'Sign-up failed. Please try again.',
      };
      _showSnack(message, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google sign-up/in ───────────────────────────────────────────────────────

  void _onContinueWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final cred = await _authService.signInWithGoogle(role: widget.role);
      if (cred == null) return; // user cancelled the picker

      _navigateHome();
      _showSnack(
        'Welcome to PillBuddy${_isPatient ? ' as a Patient' : ' as a Caregiver'}!',
      );
    } on RoleConflictException catch (e) {
      final takenRole = e.existingRole == 'caregiver' ? 'Caregiver' : 'Patient';
      _showSnack(
        'This Google account is already registered as a $takenRole. '
        'Please use a different account.',
        isError: true,
      );
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
    final roleLabel = _isPatient ? 'Patient' : 'Caregiver';
    final roleIcon =
        _isPatient ? Icons.person_outline : Icons.medical_services_outlined;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: SafeArea(
        child: Column(
          children: [
            // ── Back button ─────────────────────────────────────────────────
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),

                    // ── Role badge ──────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(roleIcon, size: 16, color: roleColor),
                          const SizedBox(width: 6),
                          Text(
                            roleLabel,
                            style: TextStyle(
                              color: roleColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isPatient
                          ? 'Sign up to track and view your medications'
                          : 'Sign up to manage medications for your patients',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black45,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Tabs ────────────────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: roleColor,
                        unselectedLabelColor: Colors.black45,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        indicator: BoxDecoration(
                          color: roleColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'Email'),
                          Tab(text: 'Google'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Tab views ───────────────────────────────────────────
                    SizedBox(
                      // Fixed height so it doesn't fight with SingleChildScrollView
                      height: 460,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // ── Email tab ───────────────────────────────────
                          _EmailTab(
                            formKey: _formKey,
                            nameController: _nameController,
                            emailController: _emailController,
                            passwordController: _passwordController,
                            obscurePassword: _obscurePassword,
                            onToggleObscure: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            isLoading: _isLoading,
                            onSubmit: _onCreateAccount,
                            roleColor: roleColor,
                            roleLabel: roleLabel,
                          ),

                          // ── Google tab ──────────────────────────────────
                          _GoogleTab(
                            isLoading: _isGoogleLoading,
                            onContinue: _onContinueWithGoogle,
                            roleLabel: roleLabel,
                            roleColor: roleColor,
                          ),
                        ],
                      ),
                    ),

                    // ── Sign In link ────────────────────────────────────────
                    Center(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black45),
                          children: [
                            const TextSpan(text: 'Already have an account?  '),
                            TextSpan(
                              text: 'Sign In',
                              style: TextStyle(
                                color: roleColor,
                                fontWeight: FontWeight.w600,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const LoginScreen()),
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
          ],
        ),
      ),
    );
  }
}

// ── Email tab ──────────────────────────────────────────────────────────────────

class _EmailTab extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final bool isLoading;
  final VoidCallback onSubmit;
  final Color roleColor;
  final String roleLabel;

  const _EmailTab({
    required this.formKey,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.isLoading,
    required this.onSubmit,
    required this.roleColor,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          const _FieldLabel(label: 'Name'),
          const SizedBox(height: 8),
          _InputField(
            controller: nameController,
            hintText: 'Enter your name',
            keyboardType: TextInputType.name,
            textInputAction: TextInputAction.next,
            roleColor: roleColor,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please enter your name'
                : null,
          ),

          const SizedBox(height: 20),

          // Email
          const _FieldLabel(label: 'Email'),
          const SizedBox(height: 8),
          _InputField(
            controller: emailController,
            hintText: 'Enter your email',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            roleColor: roleColor,
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
            controller: passwordController,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            style: const TextStyle(fontSize: 15, color: Colors.black87),
            decoration: InputDecoration(
              hintText: 'At least 6 characters',
              hintStyle:
                  const TextStyle(color: Colors.black38, fontSize: 14),
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
                borderSide: BorderSide(color: roleColor, width: 1.5),
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
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.black38,
                  size: 20,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter a password';
              if (v.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: roleColor,
                disabledBackgroundColor: roleColor.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Create $roleLabel Account',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Google tab ─────────────────────────────────────────────────────────────────

class _GoogleTab extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onContinue;
  final String roleLabel;
  final Color roleColor;

  const _GoogleTab({
    required this.isLoading,
    required this.onContinue,
    required this.roleLabel,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 16),

        // Illustration area
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: _GoogleLogo(size: 44),
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'Sign up as $roleLabel with Google',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 10),

        const Text(
          'Tap the button below to choose your Google account.\n'
          'Your account will be linked to this role.',
          style: TextStyle(
            fontSize: 13.5,
            color: Colors.black45,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 36),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: isLoading ? null : onContinue,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFDADCE0), width: 1.5),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 0,
            ),
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: roleColor,
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

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A Google account can only be used for one role. '
                  'If it is already registered as ${roleLabel == 'Patient' ? 'a Caregiver' : 'a Patient'}, '
                  'sign-up will be blocked.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber.shade800,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Renders the Google "G" logo using pure Flutter — no image asset needed.
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
  final Color roleColor;

  const _InputField({
    required this.controller,
    required this.hintText,
    required this.keyboardType,
    required this.textInputAction,
    required this.roleColor,
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
            borderSide: BorderSide(color: roleColor, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
        validator: validator,
      );
}