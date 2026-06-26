// lib/screens/onboarding_screen.dart
//
// Changes:
//   - "CLIENT" → "Sign up as Patient"  → SignUpScreen(role: 'patient')
//   - "Admin Login" → "Sign up as Caregiver" → SignUpScreen(role: 'caregiver')
//   - Added "Already have an account? Sign In" link at the bottom.

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: SafeArea(
        child: Column(
          children: [
            // Back button
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 12),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      size: 20, color: Colors.black87),
                  onPressed: () {
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Illustration
            Expanded(child: _BrandMarkWidget()),

            // Dots
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DotIndicator(isActive: false),
                SizedBox(width: 6),
                _DotIndicator(isActive: false),
                SizedBox(width: 6),
                _DotIndicator(isActive: true),
              ],
            ),

            const SizedBox(height: 28),

            // Title & subtitle
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Text(
                    'For your patients, family, and friends',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Easily manage medication for everyone you care about with seamless profile switching.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Sign up as Patient ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SignUpScreen(role: 'patient'),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A6BFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_outline, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Sign up as Patient',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Sign up as Caregiver ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SignUpScreen(role: 'caregiver'),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: Color(0xFF2BC8A7), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medical_services_outlined,
                          color: Color(0xFF2BC8A7), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Sign up as Caregiver',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2BC8A7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Already have an account ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 15, color: Colors.black54),
                  children: [
                    const TextSpan(text: 'Already have an account?  '),
                    TextSpan(
                      text: 'Sign In',
                      style: const TextStyle(
                        color: Color(0xFF1A6BFF),
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                            ),
                    ),
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

// ── Brand mark illustration ────────────────────────────────────────────────
// A clean, uncluttered visual built around PillBuddy's actual logo — no small
// icons or busy overlapping circles, just one clear, high-contrast focal point.

class _BrandMarkWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 260,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3AC47D).withOpacity(0.08),
              ),
            ),
            Container(
              width: 185,
              height: 185,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3AC47D).withOpacity(0.14),
              ),
            ),
            Container(
              width: 148,
              height: 148,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/pillbuddy_logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.medication_liquid_outlined,
                  size: 56,
                  color: Color(0xFF3AC47D),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  final bool isActive;
  const _DotIndicator({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isActive ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF1A6BFF) : Colors.black26,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}