// lib/screens/splash_screen.dart
//
// Changes:
//   - After the animation, checks FirebaseAuth for a logged-in user.
//   - If logged in: fetches their role from Firestore and routes to the
//     correct home (PatientHome or CaregiverHome).
//   - If not logged in: goes to OnboardingCarousel as before.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'onboarding_carousel_screen.dart';
import 'patient_home.dart';
import 'caregiver_home.dart';

class PillBuddySplash extends StatefulWidget {
  const PillBuddySplash({super.key});

  @override
  State<PillBuddySplash> createState() => _PillBuddySplashState();
}

class _PillBuddySplashState extends State<PillBuddySplash>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();

    Timer(const Duration(seconds: 3), _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Not signed in → onboarding
      _push(const OnboardingCarousel());
      return;
    }

    // Signed in → fetch role and route accordingly
    try {
      final role = await AuthService().fetchRole(user.uid);
      if (!mounted) return;
      if (role == 'caregiver') {
        _push(const CaregiverHome());
      } else {
        // 'patient' or any unknown role → patient home
        _push(const PatientHome());
      }
    } catch (_) {
      if (!mounted) return;
      // If role fetch fails fall back to onboarding
      _push(const OnboardingCarousel());
    }
  }

  void _push(Widget screen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D5BD7),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.medication_liquid_outlined,
                  size: 100,
                  color: Colors.white,
                ),
                SizedBox(height: 20),
                Text(
                  'PillBuddy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}