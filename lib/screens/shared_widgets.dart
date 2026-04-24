// lib/screens/shared_widgets.dart
import 'package:flutter/material.dart';

/// A back-chevron + centred title row used at the top of each step.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onBack,
          child: const Icon(Icons.chevron_left, size: 28),
        ),
        Expanded(
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        // Mirror the icon width so the title stays centred.
        const SizedBox(width: 28),
      ],
    );
  }
}

/// A single-column drum-roll wheel.
class WheelPicker extends StatelessWidget {
  const WheelPicker({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.onChanged,
    required this.itemBuilder,
    this.width = 70,
    this.height = 180,
    this.itemExtent = 50,
    this.diameterRatio = 1.2,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final ValueChanged<int> onChanged;
  final Widget Function(BuildContext, int, bool isSelected) itemBuilder;
  final double width;
  final double height;
  final double itemExtent;
  final double diameterRatio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: itemExtent,
        perspective: 0.003,
        diameterRatio: diameterRatio,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          builder: (ctx, i) => itemBuilder(ctx, i, false),
        ),
      ),
    );
  }
}

/// Styled text displayed in a wheel row.
class WheelItem extends StatelessWidget {
  const WheelItem({
    super.key,
    required this.text,
    required this.isSelected,
    this.selectedSize = 32,
    this.unselectedSize = 20,
  });

  final String text;
  final bool isSelected;
  final double selectedSize;
  final double unselectedSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: isSelected ? selectedSize : unselectedSize,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.black : Colors.grey[300],
        ),
      ),
    );
  }
}

/// "08:00 AM" quick-select chip used on the time-picker step.
class QuickTimeChip extends StatelessWidget {
  const QuickTimeChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

/// Primary CTA button used at the bottom of each step.
class NextButton extends StatelessWidget {
  const NextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            elevation: 0,
          ),
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}