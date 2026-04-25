// lib/screens/caregiver_add_med_screen.dart
//
// A focused form for a caregiver to add a new medication for a patient.
// Saves directly to users/{patientUid}/medications via CaregiverService.

import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/caregiver_service.dart';

class CaregiverAddMedScreen extends StatefulWidget {
  final String patientUid;
  final String patientName;

  const CaregiverAddMedScreen({
    super.key,
    required this.patientUid,
    required this.patientName,
  });

  @override
  State<CaregiverAddMedScreen> createState() => _CaregiverAddMedScreenState();
}

class _CaregiverAddMedScreenState extends State<CaregiverAddMedScreen> {
  final _service = CaregiverService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _doseController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  bool _isLoading = false;

  String _selectedType = 'Pill';
  String _selectedUnit = 'mg';
  int _freqNumber = 1;
  String _freqUnit = 'Day';
  int _hour = 8;
  int _minute = 0;
  String _period = 'AM';
  DateTime? _startDate;

  static const _types = ['Pill', 'Capsule', 'Syrup', 'Injection', 'Drop', 'Spray', 'Others'];
  static const _units = ['mg', 'ml', 'cc', 'drops', 'sprays', 'dose'];
  static const _freqUnits = ['Hour', 'Day', 'Week', 'Month'];

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF2BC8A7)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _period == 'AM' ? _hour : _hour + 12,
        minute: _minute,
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF2BC8A7)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _period = picked.hour < 12 ? 'AM' : 'PM';
        _hour = picked.hour % 12 == 0 ? 12 : picked.hour % 12;
        _minute = picked.minute;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final med = MedicationModel(
        name: _nameController.text.trim(),
        type: _selectedType,
        dose: double.tryParse(_doseController.text) ?? 1.0,
        unit: _selectedUnit,
        freqNumber: _freqNumber,
        freqUnit: _freqUnit,
        startingDate: _startDate ?? DateTime.now(),
        hour: _hour,
        minute: _minute,
        period: _period,
        note: _noteController.text.trim(),
        stockCount: 30,
        stockUnit: _selectedUnit,
      );

      await _service.addMedication(widget.patientUid, med);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Medication added for ${widget.patientName}!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              size: 20, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              'Add Medication',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              'for ${widget.patientName}',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Medication name
            _label('Medication Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: _inputDeco(hintText: 'e.g. Metformin'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter a medication name'
                  : null,
            ),

            const SizedBox(height: 20),

            // Type
            _label('Type'),
            const SizedBox(height: 8),
            _DropdownField<String>(
              value: _selectedType,
              items: _types,
              onChanged: (v) => setState(() => _selectedType = v!),
            ),

            const SizedBox(height: 20),

            // Dose + Unit row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Dose'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _doseController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDeco(hintText: '1'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          if (double.tryParse(v) == null) {
                            return 'Enter a number';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Unit'),
                      const SizedBox(height: 8),
                      _DropdownField<String>(
                        value: _selectedUnit,
                        items: _units,
                        onChanged: (v) =>
                            setState(() => _selectedUnit = v!),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Frequency
            _label('Frequency'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () {
                            if (_freqNumber > 1) {
                              setState(() => _freqNumber--);
                            }
                          },
                          icon: const Icon(Icons.remove),
                        ),
                        Text(
                          '$_freqNumber',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _freqNumber++),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DropdownField<String>(
                    value: _freqUnit,
                    items: _freqUnits,
                    onChanged: (v) => setState(() => _freqUnit = v!),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Start date + Time row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Start Date'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 16, color: Colors.black45),
                              const SizedBox(width: 8),
                              Text(
                                _startDate != null
                                    ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                                    : 'Pick date',
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Time'),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time_outlined,
                                  size: 16, color: Colors.black45),
                              const SizedBox(width: 8),
                              Text(
                                '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')} $_period',
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Note
            _label('Note (optional)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _noteController,
              maxLines: 2,
              decoration: _inputDeco(hintText: 'e.g. Take with food'),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2BC8A7),
                  disabledBackgroundColor:
                      const Color(0xFF2BC8A7).withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Medication',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      );

  InputDecoration _inputDeco({required String hintText}) => InputDecoration(
        hintText: hintText,
        hintStyle:
            const TextStyle(color: Colors.black38, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF2BC8A7), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      );
}

class _DropdownField<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(
                      e.toString(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}