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
            Expanded(child: _ProfileBubblesWidget()),

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
                    'For yourself, family and friends',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Easily manage medication for everyone you care about with seamless profile switching.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black45,
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
                height: 52,
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
                      Icon(Icons.person_outline, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Sign up as Patient',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Sign up as Caregiver ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SignUpScreen(role: 'caregiver'),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: Color(0xFF1A6BFF), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medical_services_outlined,
                          color: Color(0xFF1A6BFF), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Sign up as Caregiver',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A6BFF),
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
                      fontSize: 14, color: Colors.black45),
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

// ── Profile bubbles illustration ──────────────────────────────────────────────

class _ProfileBubblesWidget extends StatelessWidget {
  static const List<IconData> _icons = [
    Icons.person,
    Icons.elderly,
    Icons.face,
    Icons.person_2,
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 280,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _ring(220, const Color(0xFFDDE4F0)),
            _ring(160, const Color(0xFFCDD7EE)),
            Positioned(
              top: 80, left: 90,
              child: _bubble(88, _icons[3], false),
            ),
            Positioned(
              top: 0, left: 110,
              child: _bubble(56, _icons[0], false),
            ),
            Positioned(
              top: 90, left: 10,
              child: _bubble(62, _icons[1], true),
            ),
            Positioned(
              top: 70, right: 8,
              child: _bubble(62, _icons[2], true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.45),
        ),
      );

  Widget _bubble(double size, IconData icon, bool grey) {
    Widget w = CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFCDD7EE),
      child: Icon(icon, size: size * 0.45, color: Colors.white70),
    );
    if (grey) {
      w = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: w,
      );
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(child: SizedBox(width: size, height: size, child: w)),
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