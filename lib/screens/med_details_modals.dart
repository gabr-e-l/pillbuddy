// med_details_modals.dart
//
// All bottom-sheet modals used by MedDetailsScreen.
// Kept separate to avoid cluttering the main screen file.

import 'package:flutter/material.dart';
import 'medication_form_data.dart';

// ── Time Picker ───────────────────────────────────────────────────────────────

class TimePickerModal extends StatefulWidget {
  final int hour;
  final int minute;
  final String period;
  final void Function(int hour, int minute, String period) onDone;

  const TimePickerModal({
    super.key,
    required this.hour,
    required this.minute,
    required this.period,
    required this.onDone,
  });

  @override
  State<TimePickerModal> createState() => _TimePickerModalState();
}

class _TimePickerModalState extends State<TimePickerModal> {
  late int _hour;
  late int _minute;
  late String _period;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;
  late FixedExtentScrollController _periodCtrl;

  @override
  void initState() {
    super.initState();
    _hour = widget.hour;
    _minute = widget.minute;
    _period = widget.period;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour - 1);
    _minCtrl = FixedExtentScrollController(initialItem: _minute);
    _periodCtrl = FixedExtentScrollController(
      initialItem: _period == 'AM' ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    _periodCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModalShell(
      title: 'Set Time',
      onDone: () {
        widget.onDone(_hour, _minute, _period);
        Navigator.pop(context);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _WheelPicker(
            controller: _hourCtrl,
            itemCount: 12,
            labelBuilder: (i) => (i + 1).toString().padLeft(2, '0'),
            onChanged: (i) => _hour = i + 1,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              ':',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          _WheelPicker(
            controller: _minCtrl,
            itemCount: 60,
            labelBuilder: (i) => i.toString().padLeft(2, '0'),
            onChanged: (i) => _minute = i,
          ),
          const SizedBox(width: 16),
          _WheelPicker(
            controller: _periodCtrl,
            itemCount: 2,
            labelBuilder: (i) => i == 0 ? 'AM' : 'PM',
            onChanged: (i) => _period = i == 0 ? 'AM' : 'PM',
            width: 60,
          ),
        ],
      ),
    );
  }
}

// ── Frequency Picker ──────────────────────────────────────────────────────────

class FrequencyPickerModal extends StatefulWidget {
  final int freqNumber;
  final String freqUnit;
  final void Function(int number, String unit) onDone;

  const FrequencyPickerModal({
    super.key,
    required this.freqNumber,
    required this.freqUnit,
    required this.onDone,
  });

  @override
  State<FrequencyPickerModal> createState() => _FrequencyPickerModalState();
}

class _FrequencyPickerModalState extends State<FrequencyPickerModal> {
  late int _number;
  late String _unit;
  late FixedExtentScrollController _numberCtrl;
  late FixedExtentScrollController _unitCtrl;

  @override
  void initState() {
    super.initState();
    _number = widget.freqNumber;
    _unit = widget.freqUnit;
    _numberCtrl = FixedExtentScrollController(initialItem: _number - 1);
    _unitCtrl = FixedExtentScrollController(
      initialItem: MedicationFormData.freqUnits.indexOf(_unit),
    );
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModalShell(
      title: 'Set frequency',
      onDone: () {
        widget.onDone(_number, _unit);
        Navigator.pop(context);
      },
      child: Row(
        children: [
          // Static "Every" label
          const Expanded(
            child: Center(
              child: Text(
                'Every',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          // Number wheel (1–30)
          Expanded(
            child: _WheelPicker(
              controller: _numberCtrl,
              itemCount: 30,
              labelBuilder: (i) => '${i + 1}',
              onChanged: (i) => _number = i + 1,
            ),
          ),
          // Unit wheel (Hour / Day / Week / Month)
          Expanded(
            child: _WheelPicker.fromList(
              controller: _unitCtrl,
              items: MedicationFormData.freqUnits,
              onChanged: (i) => _unit = MedicationFormData.freqUnits[i],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dose Picker ───────────────────────────────────────────────────────────────

class DosePickerModal extends StatefulWidget {
  final double doseAmount;
  final String doseForm;
  final void Function(double amount, String form) onDone;

  const DosePickerModal({
    super.key,
    required this.doseAmount,
    required this.doseForm,
    required this.onDone,
  });

  @override
  State<DosePickerModal> createState() => _DosePickerModalState();
}

class _DosePickerModalState extends State<DosePickerModal> {
  static const _amounts = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0];
  static const _forms = [
    'Tablet',
    'Capsule',
    'Pill',
    'Drop',
    'Syrup',
    'Injection',
    'Spray',
  ];

  late double _amount;
  late String _form;
  late FixedExtentScrollController _amountCtrl;
  late FixedExtentScrollController _formCtrl;

  @override
  void initState() {
    super.initState();
    _amount = widget.doseAmount;
    _form = widget.doseForm;
    final amountIdx = _amounts.indexWhere((a) => a == _amount);
    final formIdx = _forms.indexWhere((f) => f == _form);
    _amountCtrl = FixedExtentScrollController(
      initialItem: amountIdx < 0 ? 1 : amountIdx,
    );
    _formCtrl = FixedExtentScrollController(
      initialItem: formIdx < 0 ? 0 : formIdx,
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _formCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModalShell(
      title: 'Select Dosage',
      onDone: () {
        widget.onDone(_amount, _form);
        Navigator.pop(context);
      },
      child: Row(
        children: [
          // Amount wheel (0.5 increments)
          Expanded(
            child: _WheelPicker(
              controller: _amountCtrl,
              itemCount: _amounts.length,
              labelBuilder: (i) => _amounts[i] % 1 == 0
                  ? _amounts[i].toInt().toString()
                  : _amounts[i].toString(),
              onChanged: (i) => _amount = _amounts[i],
            ),
          ),
          // Form wheel (Tablet, Capsule, etc.)
          Expanded(
            child: _WheelPicker.fromList(
              controller: _formCtrl,
              items: _forms,
              onChanged: (i) => _form = _forms[i],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stock Picker ──────────────────────────────────────────────────────────────

class StockPickerModal extends StatefulWidget {
  final int stockCount;
  final String stockUnit;
  final void Function(int count, String unit) onDone;

  const StockPickerModal({
    super.key,
    required this.stockCount,
    required this.stockUnit,
    required this.onDone,
  });

  @override
  State<StockPickerModal> createState() => _StockPickerModalState();
}

class _StockPickerModalState extends State<StockPickerModal> {
  static const _units = ['Pills', 'Capsules', 'Tablets', 'ml', 'Drops'];

  late int _count;
  late String _unit;
  late FixedExtentScrollController _countCtrl;
  late FixedExtentScrollController _unitCtrl;

  @override
  void initState() {
    super.initState();
    _count = widget.stockCount;
    _unit = widget.stockUnit;
    final unitIdx = _units.indexWhere((u) => u == _unit);
    _countCtrl = FixedExtentScrollController(initialItem: _count - 1);
    _unitCtrl = FixedExtentScrollController(
      initialItem: unitIdx < 0 ? 0 : unitIdx,
    );
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ModalShell(
      title: 'Initial Stock',
      onDone: () {
        widget.onDone(_count, _unit);
        Navigator.pop(context);
      },
      child: Row(
        children: [
          // Count wheel (1–100)
          Expanded(
            child: _WheelPicker(
              controller: _countCtrl,
              itemCount: 100,
              labelBuilder: (i) => '${i + 1}',
              onChanged: (i) => _count = i + 1,
            ),
          ),
          // Unit wheel (Pills, Capsules, etc.)
          Expanded(
            child: _WheelPicker.fromList(
              controller: _unitCtrl,
              items: _units,
              onChanged: (i) => _unit = _units[i],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Note Editor ───────────────────────────────────────────────────────────────

class NoteEditModal extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onDone;

  const NoteEditModal({
    super.key,
    required this.controller,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Note',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Optional note about the medication',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF4F7FF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),
          _DoneButton(onPressed: onDone),
        ],
      ),
    );
  }
}

// ── Shared internal widgets ───────────────────────────────────────────────────

/// Standard bottom-sheet shell: header + scrollable content area + Done button.
class _ModalShell extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onDone;

  const _ModalShell({
    required this.title,
    required this.child,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Wheel content
          SizedBox(height: 200, child: child),
          _DoneButton(onPressed: onDone),
        ],
      ),
    );
  }
}

/// Reusable list-wheel picker with a builder or a string list.
class _WheelPicker extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int) labelBuilder;
  final ValueChanged<int> onChanged;
  final double width;

  const _WheelPicker({
    required this.controller,
    required this.itemCount,
    required this.labelBuilder,
    required this.onChanged,
    this.width = 70,
  });

  /// Convenience constructor for a fixed list of strings.
  factory _WheelPicker.fromList({
    required FixedExtentScrollController controller,
    required List<String> items,
    required ValueChanged<int> onChanged,
    double width = 70,
  }) {
    return _WheelPicker(
      controller: controller,
      itemCount: items.length,
      labelBuilder: (i) => items[i],
      onChanged: onChanged,
      width: width,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 48,
        perspective: 0.003,
        diameterRatio: 1.3,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          builder: (_, i) {
            final isSelected =
                controller.hasClients && controller.selectedItem == i;
            return Center(
              child: Text(
                labelBuilder(i),
                style: TextStyle(
                  fontSize: isSelected ? 24 : 18,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.black : Colors.grey[300],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Blue "Done" button used at the bottom of every modal.
class _DoneButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _DoneButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: SizedBox(
        width: double.infinity,
        height: 50,
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
          child: const Text('Done', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}
