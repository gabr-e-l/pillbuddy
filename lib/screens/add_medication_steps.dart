// add_medication_steps.dart
import 'package:flutter/material.dart';
import 'medication_form_data.dart';
import 'shared_widgets.dart';
import 'calendar_modal.dart';

// ─────────────────────────────────────────────
// Step 1 – Medication Name
// ─────────────────────────────────────────────
class NameStep extends StatefulWidget {
  const NameStep({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  State<NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<NameStep> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // First step has no back button, so we just show the title centred.
          const Center(
            child: Text(
              'Medication Name',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: widget.controller,
              onChanged: (_) => widget.onChanged(),
              decoration: const InputDecoration(
                hintText: 'e.g. Metformin',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Step 2 – Dose + Medication Type
// ─────────────────────────────────────────────
class DoseTypeStep extends StatelessWidget {
  const DoseTypeStep({
    super.key,
    required this.data,
    required this.doseController,
    required this.onDoseChanged,
    required this.onTypeChanged,
    required this.onBack,
  });

  final MedicationFormData data;
  final FixedExtentScrollController doseController;
  final ValueChanged<double> onDoseChanged;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.chevron_left, size: 28),
            ),
          ),
          const SizedBox(height: 16),
          _buildDosePicker(),
          const Divider(),
          const SizedBox(height: 16),
          _buildTypeGrid(),
        ],
      ),
    );
  }

  Widget _buildDosePicker() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: ListWheelScrollView.useDelegate(
            controller: doseController,
            itemExtent: 36,
            perspective: 0.003,
            diameterRatio: 1.5,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) => onDoseChanged((i + 1) * 0.5),
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: 20,
              builder: (_, i) {
                final val = (i + 1) * 0.5;
                final isSelected = val == data.dose;
                return Center(
                  child: Text(
                    val % 1 == 0 ? val.toInt().toString() : val.toString(),
                    style: TextStyle(
                      fontSize: isSelected ? 22 : 16,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? Colors.black : Colors.grey[400],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            data.type != null ? data.currentUnit : '—',
            key: ValueKey(data.currentUnit),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: data.type != null ? Colors.blue : Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeGrid() {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: MedicationFormData.medicationTypes.map((type) {
        final isSelected = data.type == type['label'];
        return GestureDetector(
          onTap: () => onTypeChanged(type['label']!),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.blue.withValues(alpha: 0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey[200]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Image.asset(
                    type['asset']!,
                    fit: BoxFit.contain,
                    color: isSelected ? Colors.blue : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                type['label']!,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.blue : Colors.black87,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────
// Step 3 – Frequency + Starting Date
// ─────────────────────────────────────────────
class FrequencyStep extends StatelessWidget {
  const FrequencyStep({
    super.key,
    required this.data,
    required this.freqNumberController,
    required this.freqUnitController,
    required this.onFreqNumberChanged,
    required this.onFreqUnitChanged,
    required this.onDateChanged,
    required this.onBack,
  });

  final MedicationFormData data;
  final FixedExtentScrollController freqNumberController;
  final FixedExtentScrollController freqUnitController;
  final ValueChanged<int> onFreqNumberChanged;
  final ValueChanged<String> onFreqUnitChanged;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onBack;

  String _monthName(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: StepHeader(title: 'Frequency', onBack: onBack),
        ),
        const SizedBox(height: 24),
        _buildFrequencyWheel(),
        const Spacer(),
        _buildStartingDateTile(context),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildFrequencyWheel() {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Center(
              child: Text(
                'Every',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          // Number wheel
          Expanded(
            child: ListWheelScrollView.useDelegate(
              controller: freqNumberController,
              itemExtent: 40,
              perspective: 0.003,
              diameterRatio: 1.4,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (i) => onFreqNumberChanged(i + 1),
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: 30,
                builder: (_, i) {
                  final isSelected = (i + 1) == data.freqNumber;
                  return Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: isSelected ? 22 : 16,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? Colors.black : Colors.grey[400],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Unit wheel
          Expanded(
            child: ListWheelScrollView(
              controller: freqUnitController,
              itemExtent: 40,
              perspective: 0.003,
              diameterRatio: 1.4,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (i) =>
                  onFreqUnitChanged(MedicationFormData.freqUnits[i]),
              children: MedicationFormData.freqUnits.map((unit) {
                final isSelected = unit == data.freqUnit;
                return Center(
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontSize: isSelected ? 22 : 16,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? Colors.black : Colors.grey[400],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartingDateTile(BuildContext context) {
    final date = data.startingDate;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () async {
          final picked = await CalendarModal.show(
            context,
            initialDate: data.startingDate,
          );
          if (picked != null) onDateChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                size: 22,
                color: Colors.black87,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  date == null
                      ? 'Starting Date'
                      : '${date.day} ${_monthName(date.month)} ${date.year}',
                  style: TextStyle(
                    fontSize: 16,
                    color: date == null ? Colors.black87 : Colors.blue,
                    fontWeight: date == null
                        ? FontWeight.normal
                        : FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Step 4 – Set Your Time
// ─────────────────────────────────────────────
class TimeStep extends StatelessWidget {
  const TimeStep({
    super.key,
    required this.data,
    required this.hourController,
    required this.minuteController,
    required this.periodController,
    required this.onHourChanged,
    required this.onMinuteChanged,
    required this.onPeriodChanged,
    required this.onBack,
  });

  final MedicationFormData data;
  final FixedExtentScrollController hourController;
  final FixedExtentScrollController minuteController;
  final FixedExtentScrollController periodController;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onBack;

  static const _quickTimes = [
    (label: '08:00', hour: 8, minute: 0, period: 'AM'),
    (label: '12:00', hour: 12, minute: 0, period: 'PM'),
    (label: '06:00', hour: 6, minute: 0, period: 'PM'),
    (label: '12:00', hour: 12, minute: 0, period: 'AM'),
  ];

  void _applyQuickTime(int hour, int minute, String period) {
    onHourChanged(hour);
    onMinuteChanged(minute);
    onPeriodChanged(period);
    hourController.animateToItem(
      hour - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    minuteController.animateToItem(
      minute,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    periodController.animateToItem(
      period == 'AM' ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: StepHeader(title: 'Set your time', onBack: onBack),
        ),
        const SizedBox(height: 32),
        _buildTimePicker(),
        const SizedBox(height: 24),
        _buildQuickTimeRow(),
        const Spacer(),
      ],
    );
  }

  Widget _buildTimePicker() {
    return SizedBox(
      height: 180,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildHourWheel(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              ':',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),
          _buildMinuteWheel(),
          const SizedBox(width: 12),
          _buildPeriodWheel(),
        ],
      ),
    );
  }

  Widget _buildHourWheel() {
    return SizedBox(
      width: 70,
      child: ListWheelScrollView.useDelegate(
        controller: hourController,
        itemExtent: 50,
        perspective: 0.003,
        diameterRatio: 1.2,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) => onHourChanged(i + 1),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: 12,
          builder: (_, i) {
            final isSelected = (i + 1) == data.hour;
            return WheelItem(
              text: (i + 1).toString().padLeft(2, '0'),
              isSelected: isSelected,
            );
          },
        ),
      ),
    );
  }

  Widget _buildMinuteWheel() {
    return SizedBox(
      width: 70,
      child: ListWheelScrollView.useDelegate(
        controller: minuteController,
        itemExtent: 50,
        perspective: 0.003,
        diameterRatio: 1.2,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onMinuteChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: 60,
          builder: (_, i) {
            final isSelected = i == data.minute;
            return WheelItem(
              text: i.toString().padLeft(2, '0'),
              isSelected: isSelected,
            );
          },
        ),
      ),
    );
  }

  Widget _buildPeriodWheel() {
    return SizedBox(
      width: 60,
      child: ListWheelScrollView(
        controller: periodController,
        itemExtent: 50,
        perspective: 0.003,
        diameterRatio: 1.2,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) => onPeriodChanged(i == 0 ? 'AM' : 'PM'),
        children: ['AM', 'PM'].map((p) {
          final isSelected = p == data.period;
          return WheelItem(
            text: p,
            isSelected: isSelected,
            selectedSize: 24,
            unselectedSize: 16,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildQuickTimeRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _quickTimes
            .map(
              (t) => QuickTimeChip(
                label: t.label,
                onTap: () => _applyQuickTime(t.hour, t.minute, t.period),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Step 5 – Note
// ─────────────────────────────────────────────
class NoteStep extends StatelessWidget {
  const NoteStep({super.key, required this.controller, required this.onBack});

  final TextEditingController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          StepHeader(title: 'Note', onBack: onBack),
          const SizedBox(height: 20),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Optional note about the medication',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
