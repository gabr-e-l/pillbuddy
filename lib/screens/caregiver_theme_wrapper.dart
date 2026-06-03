// lib/screens/caregiver_theme_wrapper.dart
//
// Drop-in wrapper that applies the caregiver accessibility theme and font
// scale to any subtree.  Use it at the top of every caregiver Scaffold so
// the settings are consistent without repeating the boilerplate.
//
// Usage:
//   return CaregiverThemeWrapper(
//     builder: (context, acc) => Scaffold(...),
//   );

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/caregiver_accessibility_provider.dart';

class CaregiverThemeWrapper extends StatelessWidget {
  /// Receives the inner [BuildContext] (already has the correct Theme) and
  /// the resolved [CaregiverAccessibilityProvider] for reading buttonScaleFactor
  /// or other non-text values.
  final Widget Function(
      BuildContext context, CaregiverAccessibilityProvider acc) builder;

  const CaregiverThemeWrapper({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<CaregiverAccessibilityProvider>();
    return Theme(
      data: acc.theme,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(acc.fontScaleFactor),
        ),
        child: Builder(
          builder: (ctx) => builder(ctx, acc),
        ),
      ),
    );
  }
}