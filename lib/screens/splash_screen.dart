// lib/screens/splash_screen.dart
//
// Changes:
//   - Full multi-stage animated splash using the PillBuddy logo image.
//   - Stage 1 (0–600 ms)  : white background fades in; logo scales + fades in
//                           with a spring overshoot.
//   - Stage 2 (600–1100 ms): two radial pulse rings expand and fade out.
//   - Stage 3 (900–1400 ms): wordmark ("Pill" + "Buddy") slides up and fades in.
//   - Stage 4 (1100–1500 ms): subtitle + three shimmer dots appear.
//   - Stage 5 (1500 ms +)  : logo enters idle floating loop.
//   - At 3 500 ms: routes to the correct screen (same logic as before).

import 'dart:async';
import 'dart:math' as math;
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
    with TickerProviderStateMixin {
  // ── Main sequencer ──────────────────────────────────────────────────────────
  late final AnimationController _main;

  // Logo
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  // Pulse rings
  late final Animation<double> _ring1Scale;
  late final Animation<double> _ring1Opacity;
  late final Animation<double> _ring2Scale;
  late final Animation<double> _ring2Opacity;

  // Wordmark
  late final Animation<double> _wordOpacity;
  late final Animation<Offset> _wordSlide;

  // Subtitle + dots
  late final Animation<double> _subOpacity;
  late final Animation<double> _subSpacing; // letter-spacing effect via opacity proxy

  // ── Idle float loop ──────────────────────────────────────────────────────────
  late final AnimationController _float;
  late final Animation<double> _floatY;

  // ── Dot shimmer loop ────────────────────────────────────────────────────────
  late final AnimationController _dots;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── Main animation (total 1 600 ms) ──────────────────────────────────────
    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // Logo: spring scale 0.3 → 1.0 (with slight overshoot via elasticOut)
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.0, 0.45, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
      ),
    );

    // Ring 1 (green): expands 0.8 → 1.6, fades 0.7 → 0
    _ring1Scale = Tween<double>(begin: 0.8, end: 1.7).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.30, 0.70, curve: Curves.easeOut),
      ),
    );
    _ring1Opacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.30, 0.70, curve: Curves.easeIn),
      ),
    );

    // Ring 2 (blue): slightly delayed
    _ring2Scale = Tween<double>(begin: 0.8, end: 1.7).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.40, 0.80, curve: Curves.easeOut),
      ),
    );
    _ring2Opacity = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.40, 0.80, curve: Curves.easeIn),
      ),
    );

    // Wordmark: slide up + fade in
    _wordOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.55, 0.80, curve: Curves.easeOut),
      ),
    );
    _wordSlide =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.55, 0.82, curve: Curves.easeOutCubic),
      ),
    );

    // Subtitle
    _subOpacity = Tween<double>(begin: 0.0, end: 0.65).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.72, 0.95, curve: Curves.easeOut),
      ),
    );
    _subSpacing = Tween<double>(begin: 6.0, end: 3.5).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.72, 0.98, curve: Curves.easeOut),
      ),
    );

    // ── Idle float loop ──────────────────────────────────────────────────────
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _floatY = Tween<double>(begin: -7.0, end: 7.0).animate(
      CurvedAnimation(parent: _float, curve: Curves.easeInOut),
    );

    // ── Dot shimmer loop ─────────────────────────────────────────────────────
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Start everything
    _main.forward();
    Timer(const Duration(milliseconds: 3500), _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _push(const OnboardingCarousel());
      return;
    }

    try {
      final role = await AuthService().fetchRole(user.uid);
      if (!mounted) return;
      if (role == 'caregiver') {
        _push(const CaregiverHome());
      } else {
        _push(const PatientHome());
      }
    } catch (_) {
      if (!mounted) return;
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
    _main.dispose();
    _float.dispose();
    _dots.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Logo + pulse rings ─────────────────────────────────────────
            SizedBox(
              width: 220,
              height: 220,
              child: AnimatedBuilder(
                animation: Listenable.merge([_main, _float]),
                builder: (_, __) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ring 1 – green
                      _PulseRing(
                        scale: _ring1Scale.value,
                        opacity: _ring1Opacity.value,
                        color: const Color(0xFF3AC47D),
                        size: 160,
                      ),
                      // Ring 2 – blue
                      _PulseRing(
                        scale: _ring2Scale.value,
                        opacity: _ring2Opacity.value,
                        color: const Color(0xFF2B7BE0),
                        size: 160,
                      ),
                      // Logo image with spring scale + idle float
                      Transform.translate(
                        offset: Offset(0, _floatY.value),
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Opacity(
                            opacity: _logoOpacity.value.clamp(0.0, 1.0),
                            child: Image.asset(
                              'assets/images/pillbuddy_logo.png',
                              width: 170,
                              height: 170,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // ── Wordmark ────────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _main,
              builder: (_, __) {
                return FadeTransition(
                  opacity: _wordOpacity,
                  child: SlideTransition(
                    position: _wordSlide,
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Pill',
                            style: TextStyle(
                              fontFamily: 'sans-serif',
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2D3748),
                              letterSpacing: -1,
                            ),
                          ),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFF3AC47D),
                                  Color(0xFF2B7BE0),
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'Buddy',
                                style: TextStyle(
                                  fontFamily: 'sans-serif',
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white, // masked by shader
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 6),

            // ── Subtitle ────────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _main,
              builder: (_, __) {
                return Opacity(
                  opacity: _subOpacity.value.clamp(0.0, 1.0),
                  child: Text(
                    'Medicine Reminder',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF718096),
                      letterSpacing: _subSpacing.value,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 48),

            // ── Loading dots ─────────────────────────────────────────────────
            AnimatedBuilder(
              animation: Listenable.merge([_main, _dots]),
              builder: (_, __) {
                return Opacity(
                  opacity: _subOpacity.value.clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (i) {
                      final phase = (_dots.value - i * 0.25).clamp(0.0, 1.0);
                      final pulse = math.sin(phase * math.pi).clamp(0.0, 1.0);
                      final dotColors = [
                        const Color(0xFF3AC47D),
                        const Color(0xFF63C9A2),
                        const Color(0xFF2B7BE0),
                      ];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Opacity(
                          opacity: 0.4 + 0.6 * pulse,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: dotColors[i],
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper widget: a single pulse ring ──────────────────────────────────────
class _PulseRing extends StatelessWidget {
  const _PulseRing({
    required this.scale,
    required this.opacity,
    required this.color,
    required this.size,
  });

  final double scale;
  final double opacity;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
          ),
        ),
      ),
    );
  }
}