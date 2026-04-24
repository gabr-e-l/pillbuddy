// lib/screens/add_medication.dart
//
// Multi-step medication form.
// On the final step the form data is saved to Firestore via MedicationService.

import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/medication_service.dart';
import 'medication_form_data.dart';
import 'add_medication_steps.dart';
import 'shared_widgets.dart';

class AddMedication extends StatefulWidget {
  const AddMedication({super.key});

  @override
  State<AddMedication> createState() => _AddMedicationState();
}

class _AddMedicationState extends State<AddMedication> {
  // ── Navigation ────────────────────────────────────────────────────────────
  int _currentStep = 0;
  static const int _totalSteps = 5;

  // ── Services ──────────────────────────────────────────────────────────────
  final _medicationService = MedicationService();

  // ── Form data ─────────────────────────────────────────────────────────────
  final _formData = MedicationFormData();

  // ── Text controllers ──────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  // ── Wheel scroll controllers ──────────────────────────────────────────────
  late final FixedExtentScrollController _doseController;
  late final FixedExtentScrollController _freqNumberController;
  late final FixedExtentScrollController _freqUnitController;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isSaving = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _doseController = FixedExtentScrollController(initialItem: 0);
    _freqNumberController = FixedExtentScrollController(initialItem: 0);
    _freqUnitController = FixedExtentScrollController(
      initialItem: MedicationFormData.freqUnits.indexOf(_formData.freqUnit),
    );
    _hourController = FixedExtentScrollController(initialItem: 0);
    _minuteController = FixedExtentScrollController(initialItem: 0);
    _periodController = FixedExtentScrollController(initialItem: 0);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _doseController.dispose();
    _freqNumberController.dispose();
    _freqUnitController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  // ── Step validation ───────────────────────────────────────────────────────
  bool get _canProceed => switch (_currentStep) {
        0 => _nameController.text.trim().isNotEmpty,
        1 => _formData.type != null,
        2 => _formData.startingDate != null,
        _ => true,
      };

  // ── Navigation helpers ────────────────────────────────────────────────────
  void _goNext() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    }
  }

  void _goBack() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  /// Called on the last step. Saves to Firestore and resets the form.
  Future<void> _saveAndFinish() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final med = MedicationModel(
        name: _nameController.text.trim(),
        type: _formData.type ?? 'Pill',
        dose: _formData.dose,
        unit: _formData.currentUnit,
        freqNumber: _formData.freqNumber,
        freqUnit: _formData.freqUnit,
        startingDate: _formData.startingDate,
        hour: _formData.hour,
        minute: _formData.minute,
        period: _formData.period,
        note: _noteController.text.trim(),
      );

      await _medicationService.addMedication(med);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medication saved!'),
          backgroundColor: Colors.green,
        ),
      );

      // Reset the form for next use
      _resetForm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving medication: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm() {
    _nameController.clear();
    _noteController.clear();
    _formData.name = '';
    _formData.type = null;
    _formData.dose = 0.5;
    _formData.freqNumber = 1;
    _formData.freqUnit = 'Day';
    _formData.startingDate = null;
    _formData.hour = 1;
    _formData.minute = 0;
    _formData.period = 'AM';
    _formData.note = '';
    setState(() => _currentStep = 0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isLastStep = _currentStep == _totalSteps - 1;

    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        body: Column(
          children: [
            _buildProgressBar(),
            Expanded(child: _buildCurrentStep()),
            NextButton(
              label: isLastStep ? (_isSaving ? 'Saving…' : 'Save') : 'Next',
              onPressed: _isSaving
                  ? null
                  : isLastStep
                      ? (_canProceed ? _saveAndFinish : null)
                      : (_canProceed ? _goNext : null),
            ),
          ],
        ),
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────
  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: List.generate(_totalSteps, (i) {
          return Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i < _totalSteps - 1 ? 4 : 0),
              decoration: BoxDecoration(
                color: i <= _currentStep ? Colors.blue : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Step router ───────────────────────────────────────────────────────────
  Widget _buildCurrentStep() {
    return switch (_currentStep) {
      0 => NameStep(
          controller: _nameController,
          onChanged: () => setState(() => _formData.name = _nameController.text),
        ),
      1 => DoseTypeStep(
          data: _formData,
          doseController: _doseController,
          onDoseChanged: (v) => setState(() => _formData.dose = v),
          onTypeChanged: (v) => setState(() => _formData.type = v),
          onBack: _goBack,
        ),
      2 => FrequencyStep(
          data: _formData,
          freqNumberController: _freqNumberController,
          freqUnitController: _freqUnitController,
          onFreqNumberChanged: (v) => setState(() => _formData.freqNumber = v),
          onFreqUnitChanged: (v) => setState(() => _formData.freqUnit = v),
          onDateChanged: (v) => setState(() => _formData.startingDate = v),
          onBack: _goBack,
        ),
      3 => TimeStep(
          data: _formData,
          hourController: _hourController,
          minuteController: _minuteController,
          periodController: _periodController,
          onHourChanged: (v) => setState(() => _formData.hour = v),
          onMinuteChanged: (v) => setState(() => _formData.minute = v),
          onPeriodChanged: (v) => setState(() => _formData.period = v),
          onBack: _goBack,
        ),
      4 => NoteStep(controller: _noteController, onBack: _goBack),
      _ => const SizedBox.shrink(),
    };
  }
}

