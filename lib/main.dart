// lib/main.dart
//
// Changes from previous version:
//   - Wraps the entire app with ChangeNotifierProvider<AccessibilityProvider>
//   - Loads persisted accessibility prefs before showing the first frame
//   - Applies dynamic theme mode, font scale, and theme data from the provider

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/accessibility_provider.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialise local notifications (registers channels, loads timezone data)
  await NotificationService().init();
  await NotificationService().requestPermission();

  // Load saved accessibility prefs before the first frame
  final accessibilityProvider = AccessibilityProvider();
  await accessibilityProvider.load();

  runApp(
    ChangeNotifierProvider<AccessibilityProvider>.value(
      value: accessibilityProvider,
      child: const PillBuddyApp(),
    ),
  );
}

class PillBuddyApp extends StatelessWidget {
  const PillBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccessibilityProvider>();

    return MediaQuery(
      // Override system text scale with our own font scale factor
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(acc.fontScaleFactor),
      ),
      child: MaterialApp(
        title: 'PillBuddy',
        debugShowCheckedModeBanner: false,

        // Dynamic theming driven by AccessibilityProvider
        themeMode: acc.flutterThemeMode,
        theme: acc.buildLightTheme(),
        darkTheme: acc.buildDarkTheme(),

        // Centers the mobile-width content on wide web screens
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
