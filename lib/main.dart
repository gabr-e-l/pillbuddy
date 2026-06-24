// lib/main.dart
//
// UPDATED: Registers CaregiverAccessibilityProvider alongside the existing
// AccessibilityProvider so both patient and caregiver sides have independent
// accessibility settings loaded before the first frame.

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/accessibility_provider.dart';
import 'providers/caregiver_accessibility_provider.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

/// Top-level background notification handler.
/// Must be a plain top-level function (not a class method) annotated with
/// @pragma('vm:entry-point') so the AOT compiler keeps it.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  NotificationService.handleBackground(response);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialise local notifications
  await NotificationService().init();
  await NotificationService().requestPermission();

  // Load saved accessibility prefs for BOTH roles before the first frame
  final accessibilityProvider = AccessibilityProvider();
  await accessibilityProvider.load();

  final caregiverAccessibilityProvider = CaregiverAccessibilityProvider();
  await caregiverAccessibilityProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccessibilityProvider>.value(
          value: accessibilityProvider,
        ),
        ChangeNotifierProvider<CaregiverAccessibilityProvider>.value(
          value: caregiverAccessibilityProvider,
        ),
      ],
      child: const PillBuddyApp(),
    ),
  );
}

class PillBuddyApp extends StatelessWidget {
  const PillBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Patient-side accessibility drives the global MaterialApp theme so the
    // patient screens continue to work exactly as before.  The caregiver side
    // reads CaregiverAccessibilityProvider directly inside CaregiverHome and
    // its sub-screens and wraps itself in its own theming.
    final acc = context.watch<AccessibilityProvider>();

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(acc.fontScaleFactor),
      ),
      child: MaterialApp(
        title: 'PillBuddy',
        debugShowCheckedModeBanner: false,

        // Patient-side theming
        themeMode: acc.flutterThemeMode,
        theme: acc.buildLightTheme(),
        darkTheme: acc.buildDarkTheme(),

        builder: (context, child) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: child!,
            ),
          );
        },
        home: const PillBuddySplash(),
      ),
    );
  }
}