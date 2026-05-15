// lib/screens/accessibility_settings_screen.dart
//
// Patient-side Accessibility Settings:
//   • Auto-adapt from phone settings (toggle — when ON, all manual controls
//     are disabled and the app mirrors the device's current mode / font / size)
//   • Theme: Light | Dark | High Contrast
//   • Font Size: Small | Medium | Large | Extra-Large
//   • Button Size: Normal | Large | Extra-Large
//
// All changes are persisted via AccessibilityProvider / SharedPreferences.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/accessibility_provider.dart';

class AccessibilitySettingsScreen extends StatelessWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccessibilityProvider>();
    final isAuto = acc.autoAdapt;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Accessibility',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Auto-adapt banner ──────────────────────────────────────────
            _AutoAdaptCard(isAuto: isAuto, primaryColor: primaryColor),

            const SizedBox(height: 24),

            // ── Section: Appearance ───────────────────────────────────────
            _SectionHeader(label: 'Appearance', primaryColor: primaryColor),
            const SizedBox(height: 10),
            _ThemeSelector(isLocked: isAuto),

            const SizedBox(height: 24),

            // ── Section: Text ─────────────────────────────────────────────
            _SectionHeader(label: 'Text Size', primaryColor: primaryColor),
            const SizedBox(height: 10),
            _FontSizeSelector(isLocked: isAuto),

            const SizedBox(height: 24),

            // ── Section: Buttons ──────────────────────────────────────────
            _SectionHeader(label: 'Button Size', primaryColor: primaryColor),
            const SizedBox(height: 10),
            _ButtonSizeSelector(isLocked: isAuto),

            const SizedBox(height: 24),

            // ── Live preview card ─────────────────────────────────────────
            _SectionHeader(label: 'Preview', primaryColor: primaryColor),
            const SizedBox(height: 10),
            _PreviewCard(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Auto-adapt card ───────────────────────────────────────────────────────────

class _AutoAdaptCard extends StatelessWidget {
  final bool isAuto;
  final Color primaryColor;

  const _AutoAdaptCard({required this.isAuto, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final acc = context.read<AccessibilityProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final subtitleColor = isDark ? Colors.white60 : Colors.black45;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isAuto ? primaryColor : cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isAuto
                  ? Colors.white.withValues(alpha: 0.2)
                  : primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.phone_android_rounded,
              color: isAuto ? Colors.white : primaryColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Adapt to Phone Settings',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isAuto ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isAuto
                      ? 'Mirroring your device mode, font & size'
                      : 'Mirror your phone\'s display settings automatically',
                  style: TextStyle(
                    fontSize: 12,
                    color: isAuto ? Colors.white70 : subtitleColor,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isAuto,
            onChanged: (v) => acc.setAutoAdapt(v),
            activeColor: Colors.white,
            activeTrackColor: Colors.white.withValues(alpha: 0.4),
            inactiveThumbColor: primaryColor,
            inactiveTrackColor: primaryColor.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color primaryColor;

  const _SectionHeader({required this.label, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: primaryColor,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── Theme selector ────────────────────────────────────────────────────────────

class _ThemeSelector extends StatelessWidget {
  final bool isLocked;
  const _ThemeSelector({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccessibilityProvider>();

    final options = [
      _ThemeOption(
        mode: AppThemeMode.light,
        icon: Icons.light_mode_rounded,
        label: 'Light',
        bg: Colors.white,
        iconColor: const Color(0xFFFFA726),
        borderColor: Colors.grey.shade300,
      ),
      _ThemeOption(
        mode: AppThemeMode.dark,
        icon: Icons.dark_mode_rounded,
        label: 'Dark',
        bg: const Color(0xFF1E1E2E),
        iconColor: const Color(0xFF82B1FF),
        borderColor: Colors.grey.shade700,
      ),
      _ThemeOption(
        mode: AppThemeMode.highContrast,
        icon: Icons.contrast_rounded,
        label: 'High\nContrast',
        bg: Colors.black,
        iconColor: Colors.yellow,
        borderColor: Colors.black,
      ),
    ];

    return Opacity(
      opacity: isLocked ? 0.45 : 1.0,
      child: Row(
        children: options.map((opt) {
          final selected = acc.themeMode == opt.mode;
          return Expanded(
            child: GestureDetector(
              onTap: isLocked ? null : () => acc.setThemeMode(opt.mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: opt.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : opt.borderColor,
                    width: selected ? 2.5 : 1.2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : [],
                ),
                child: Column(
                  children: [
                    Icon(opt.icon, color: opt.iconColor, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      opt.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: opt.mode == AppThemeMode.dark ||
                                opt.mode == AppThemeMode.highContrast
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(height: 6),
                      Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ThemeOption {
  final AppThemeMode mode;
  final IconData icon;
  final String label;
  final Color bg;
  final Color iconColor;
  final Color borderColor;

  const _ThemeOption({
    required this.mode,
    required this.icon,
    required this.label,
    required this.bg,
    required this.iconColor,
    required this.borderColor,
  });
}

// ── Font size selector ────────────────────────────────────────────────────────

class _FontSizeSelector extends StatelessWidget {
  final bool isLocked;
  const _FontSizeSelector({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccessibilityProvider>();
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    final options = [
      (FontSizeOption.small,      'A',  12.0, 'Small'),
      (FontSizeOption.medium,     'A',  16.0, 'Medium'),
      (FontSizeOption.large,      'A',  20.0, 'Large'),
      (FontSizeOption.extraLarge, 'A',  24.0, 'X-Large'),
    ];

    return Opacity(
      opacity: isLocked ? 0.45 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: options.map((opt) {
            final (mode, letter, fontSize, label) = opt;
            final selected = acc.fontSize == mode;
            return GestureDetector(
              onTap: isLocked ? null : () => acc.setFontSize(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? primary : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: selected ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? primary : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle_rounded,
                          color: primary, size: 20),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Button size selector ──────────────────────────────────────────────────────

class _ButtonSizeSelector extends StatelessWidget {
  final bool isLocked;
  const _ButtonSizeSelector({required this.isLocked});

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccessibilityProvider>();
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    final options = [
      (ButtonSizeOption.normal,     Icons.crop_square_rounded,   'Normal',      'Standard button height'),
      (ButtonSizeOption.large,      Icons.crop_landscape_rounded, 'Large',       'Easier to tap'),
      (ButtonSizeOption.extraLarge, Icons.crop_din_rounded,       'Extra-Large', 'Maximum tap area'),
    ];

    return Opacity(
      opacity: isLocked ? 0.45 : 1.0,
      child: Column(
        children: options.map((opt) {
          final (mode, icon, label, desc) = opt;
          final selected = acc.buttonSize == mode;

          // Scale the preview button height
          final previewH = switch (mode) {
            ButtonSizeOption.normal     => 38.0,
            ButtonSizeOption.large      => 48.0,
            ButtonSizeOption.extraLarge => 58.0,
          };

          return GestureDetector(
            onTap: isLocked ? null : () => acc.setButtonSize(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? primary.withValues(alpha: 0.08)
                    : cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? primary : Colors.grey.withValues(alpha: 0.2),
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
              ),
              child: Row(
                children: [
                  // Description column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Live mini-button preview
                  const SizedBox(width: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: previewH,
                    width: 80,
                    decoration: BoxDecoration(
                      color: selected ? primary : primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'Tap Me',
                        style: TextStyle(
                          fontSize: previewH * 0.28,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : primary,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: primary, size: 22)
                  else
                    const SizedBox(width: 22),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Live preview card ─────────────────────────────────────────────────────────

class _PreviewCard extends StatelessWidget {
  const _PreviewCard();

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccessibilityProvider>();
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final onCard = isDark ? Colors.white : Colors.black87;

    final scale = acc.fontScaleFactor;
    final btnScale = acc.buttonScaleFactor;
    final btnH = 44.0 * btnScale;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: acc.isHighContrast ? Colors.black : primary.withValues(alpha: 0.25),
          width: acc.isHighContrast ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_rounded, color: primary, size: 18),
              const SizedBox(width: 6),
              Text(
                'Live Preview',
                style: TextStyle(
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Medication Reminder',
            style: TextStyle(
              fontSize: 18 * scale,
              fontWeight: FontWeight.bold,
              color: onCard,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Take 1 tablet of Aspirin 100mg with water.',
            style: TextStyle(
              fontSize: 13 * scale,
              color: onCard.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: btnH,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                'Mark as Taken',
                style: TextStyle(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w700,
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
