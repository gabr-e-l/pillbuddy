// lib/screens/caregiver_add_med_screen.dart
//
// Add / Edit medication for a patient.
//
// Frequency logic:
//   Hour  → single "first dose" time picker + interval description
//   Day   → N time pickers (one per dose per day)
//   Week  → day-of-week chip selector, then one time picker per selected day
//   Month → day-of-month grid selector, then one shared time picker
//
// UPDATED: Wrapped in CaregiverThemeWrapper so dark/HC mode, font scale and
// button scale from CaregiverAccessibilityProvider are fully applied.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/medication_model.dart';
import '../providers/caregiver_accessibility_provider.dart';
import '../services/caregiver_service.dart';
import 'caregiver_theme_wrapper.dart';

class CaregiverAddMedScreen extends StatefulWidget {
  final String patientUid;
  final String patientName;
  final MedicationModel? existingMed;

  const CaregiverAddMedScreen({
    super.key,
    required this.patientUid,
    required this.patientName,
    this.existingMed,
  });

  @override
  State<CaregiverAddMedScreen> createState() =>
      _CaregiverAddMedScreenState();
}

class _CaregiverAddMedScreenState extends State<CaregiverAddMedScreen> {
  final _service        = CaregiverService();
  final _formKey        = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _doseController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  bool _isLoading = false;

  String _selectedType = 'Pill';
  String _selectedUnit = 'mg';
  int    _freqNumber   = 1;
  String _freqUnit     = 'Day';
  DateTime? _startDate;
  DateTime? _stopDate;

  List<Map<String, dynamic>> _intakeTimes = [
    {'hour': 8, 'minute': 0, 'period': 'AM'}
  ];

  List<int> _selectedWeekDays = [];
  final Map<int, Map<String, dynamic>> _weekDayTimes = {};

  List<int> _selectedMonthDays = [];
  Map<String, dynamic> _monthTime = {'hour': 8, 'minute': 0, 'period': 'AM'};

  String? _imageBase64;
  String? _existingImageUrl;

  static const _teal = Color(0xFF2BC8A7);

  static const _types    = ['Pill', 'Capsule', 'Syrup', 'Injection', 'Drop', 'Spray', 'Others'];
  static const _units    = ['mg', 'ml', 'cc', 'drops', 'sprays', 'dose'];
  static const _freqUnits = ['Hour', 'Day', 'Week', 'Month'];

  static const _weekDayShort = {
    1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun',
  };
  static const _weekDayFull = {
    1: 'Monday', 2: 'Tuesday', 3: 'Wednesday', 4: 'Thursday',
    5: 'Friday',  6: 'Saturday', 7: 'Sunday',
  };

  bool get _isEditing => widget.existingMed != null;

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final med = widget.existingMed;
    if (med != null) {
      _nameController.text = med.name;
      _doseController.text =
          med.dose % 1 == 0 ? med.dose.toInt().toString() : med.dose.toString();
      _noteController.text = med.note;
      _selectedType  = med.type;
      _selectedUnit  = med.unit;
      _freqNumber    = med.freqNumber;
      _freqUnit      = med.freqUnit;
      _startDate     = med.startingDate;
      _stopDate      = med.stopDate;
      _existingImageUrl = med.imageUrl;

      if (med.intakeTimes.isNotEmpty) {
        _intakeTimes = List.from(med.intakeTimes);
      } else {
        _intakeTimes = [
          {'hour': med.hour, 'minute': med.minute, 'period': med.period}
        ];
      }

      _selectedWeekDays = List.from(med.selectedWeekDays);
      final sortedDays = List<int>.from(_selectedWeekDays)..sort();
      for (int i = 0; i < sortedDays.length && i < med.intakeTimes.length; i++) {
        _weekDayTimes[sortedDays[i]] = Map.from(med.intakeTimes[i]);
      }
      for (final d in _selectedWeekDays) {
        _weekDayTimes.putIfAbsent(
            d, () => {'hour': 8, 'minute': 0, 'period': 'AM'});
      }

      _selectedMonthDays = List.from(med.selectedMonthDays);
      if (med.freqUnit == 'Month' && med.intakeTimes.isNotEmpty) {
        _monthTime = Map.from(med.intakeTimes.first);
      }
    } else {
      _startDate = DateTime.now();
    }
    _syncDayFrequency();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── Sync helpers ──────────────────────────────────────────────────────────

  void _syncDayFrequency() {
    if (_freqUnit != 'Day' && _freqUnit != 'Hour') return;
    // For 'Hour', only one time picker is shown (the first dose time).
    // The full intake times list is computed at save time from that first
    // dose + the interval. For 'Day', show one picker per dose.
    final needed = _freqUnit == 'Hour' ? 1 : _freqNumber;
    while (_intakeTimes.length < needed) {
      _intakeTimes.add({'hour': 8, 'minute': 0, 'period': 'AM'});
    }
    if (_intakeTimes.length > needed) {
      _intakeTimes = _intakeTimes.sublist(0, needed);
    }
  }

  /// For 'Hour' frequency, generate the full list of intake times by
  /// repeatedly adding [_freqNumber] hours starting from the first dose time,
  /// covering all doses that fit within a 24-hour window from the first dose.
  List<Map<String, dynamic>> _buildHourIntakeTimes() {
    final first  = _intakeTimes[0];
    final h12    = first['hour']   as int;
    final minute = first['minute'] as int;
    final period = first['period'] as String;

    // Convert first dose to 24-hour minutes-from-midnight
    final h24            = h12 % 12 + (period == 'PM' ? 12 : 0);
    final startMinutes   = h24 * 60 + minute;
    final intervalMins   = _freqNumber * 60;
    // Include every dose whose offset from the first dose is < 24 hours.
    // ceil gives the correct count: e.g. 24/5 = 4.8 → 5 doses (not 4).
    final dosesPerDay    = (24 / _freqNumber).ceil().clamp(1, 24);

    final times = <Map<String, dynamic>>[];
    for (int i = 0; i < dosesPerDay; i++) {
      final totalMin = (startMinutes + i * intervalMins) % (24 * 60);
      final dh24  = totalMin ~/ 60;
      final dm    = totalMin % 60;
      final dp    = dh24 < 12 ? 'AM' : 'PM';
      final dh12  = dh24 % 12 == 0 ? 12 : dh24 % 12;
      times.add({'hour': dh12, 'minute': dm, 'period': dp, 'slotIndex': i});
    }
    return times;
  }

  List<Map<String, dynamic>> _buildIntakeTimesForSave() {
    if (_freqUnit == 'Week') {
      final sorted = List<int>.from(_selectedWeekDays)..sort();
      return sorted
          .map((d) => Map<String, dynamic>.from(
              _weekDayTimes[d] ?? {'hour': 8, 'minute': 0, 'period': 'AM'}))
          .toList();
    }
    if (_freqUnit == 'Month') return [Map.from(_monthTime)];
    // For Hour, compute all times from the first dose + interval.
    if (_freqUnit == 'Hour') return _buildHourIntakeTimes();
    return _intakeTimes;
  }

  // ── Date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickStartDate() async {
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: (_startDate != null && !_startDate!.isBefore(first))
          ? _startDate!
          : first,
      firstDate: first,
      lastDate: DateTime(2040),
      builder: _tealTheme,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_stopDate != null && _stopDate!.isBefore(_startDate!)) {
          _stopDate = null;
        }
      });
    }
  }

  Future<void> _pickStopDate() async {
    final earliest = _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (_stopDate != null && !_stopDate!.isBefore(earliest))
          ? _stopDate!
          : earliest.add(const Duration(days: 1)),
      firstDate: earliest.add(const Duration(days: 1)),
      lastDate: DateTime(2040),
      builder: _tealTheme,
    );
    if (picked != null) setState(() => _stopDate = picked);
  }

  // ── Time pickers ──────────────────────────────────────────────────────────

  Future<void> _pickDayTime(int index) async {
    final picked = await _showTimePicker(_intakeTimes[index]);
    if (picked != null) setState(() => _intakeTimes[index] = _todToMap(picked));
  }

  Future<void> _pickWeekDayTime(int weekday) async {
    final current =
        _weekDayTimes[weekday] ?? {'hour': 8, 'minute': 0, 'period': 'AM'};
    final picked = await _showTimePicker(current);
    if (picked != null) setState(() => _weekDayTimes[weekday] = _todToMap(picked));
  }

  Future<void> _pickMonthTime() async {
    final picked = await _showTimePicker(_monthTime);
    if (picked != null) setState(() => _monthTime = _todToMap(picked));
  }

  Future<TimeOfDay?> _showTimePicker(Map<String, dynamic> current) {
    final h12    = current['hour'] as int;
    final period = current['period'] as String;
    final h24    = period == 'AM'
        ? (h12 == 12 ? 0 : h12)
        : (h12 == 12 ? 12 : h12 + 12);
    return showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h24, minute: current['minute'] as int),
      builder: _tealTheme,
    );
  }

  Map<String, dynamic> _todToMap(TimeOfDay t) => {
        'hour':   t.hour % 12 == 0 ? 12 : t.hour % 12,
        'minute': t.minute,
        'period': t.hour < 12 ? 'AM' : 'PM',
      };

  // ── Image ─────────────────────────────────────────────────────────────────

  void _pickImage() {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Medicine Photo',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: _teal),
              title: Text('Take a Photo',
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(ctx);
                _captureImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _teal),
              title: Text('Choose from Gallery',
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(ctx);
                _captureImage(ImageSource.gallery);
              },
            ),
            if (_imageBase64 != null || _existingImageUrl != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _imageBase64      = null;
                    _existingImageUrl = null;
                  });
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _captureImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file   = await picker.pickImage(
          source: source, maxWidth: 600, maxHeight: 600, imageQuality: 70);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _imageBase64      = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        _existingImageUrl = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not load image: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null) {
      _snack('Please pick a start date', Colors.orange);
      return;
    }
    if (_freqUnit == 'Week' && _selectedWeekDays.isEmpty) {
      _snack('Please select at least one day of the week', Colors.orange);
      return;
    }
    if (_freqUnit == 'Month' && _selectedMonthDays.isEmpty) {
      _snack('Please select at least one day of the month', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final times   = _buildIntakeTimesForSave();
      final primary = times.isNotEmpty
          ? times.first
          : {'hour': 8, 'minute': 0, 'period': 'AM'};

      final effectiveFreqNumber = _freqUnit == 'Week'
          ? _selectedWeekDays.length
          : _freqUnit == 'Month'
              ? _selectedMonthDays.length
              : _freqNumber; // For Hour: this IS the interval (e.g. 3 = every 3 hours)

      // For 'Hour' frequency, compute the absolute firstDoseDateTime so the
      // patient home can calculate continuous cross-day dose slots.
      // Anchor = startDate (or today) at the first-dose hour:minute.
      DateTime? firstDoseDateTime;
      if (_freqUnit == 'Hour') {
        final anchorDate = _startDate ?? DateTime.now();
        final first = _intakeTimes[0];
        final fh12   = first['hour']   as int;
        final fmin   = first['minute'] as int;
        final fper   = first['period'] as String;
        final fh24   = fh12 % 12 + (fper == 'PM' ? 12 : 0);
        firstDoseDateTime = DateTime(
            anchorDate.year, anchorDate.month, anchorDate.day, fh24, fmin);
      }

      final med = MedicationModel(
        id:               widget.existingMed?.id,
        name:             _nameController.text.trim(),
        type:             _selectedType,
        dose:             double.tryParse(_doseController.text) ?? 1.0,
        unit:             _selectedUnit,
        freqNumber:       effectiveFreqNumber,
        freqUnit:         _freqUnit,
        startingDate:     _startDate,
        stopDate:         _stopDate,
        intakeTimes:      times,
        firstDoseDateTime: firstDoseDateTime,
        selectedWeekDays: _selectedWeekDays,
        selectedMonthDays: _selectedMonthDays,
        hour:             primary['hour']   as int,
        minute:           primary['minute'] as int,
        period:           primary['period'] as String,
        note:             _noteController.text.trim(),
        stockCount:       30,
        stockUnit:        _selectedUnit,
        imageUrl:         _imageBase64 ?? _existingImageUrl,
      );

      if (_isEditing) {
        await _service.updateMedication(widget.patientUid, med.id!, med);
      } else {
        await _service.addMedication(widget.patientUid, med);
      }

      if (!mounted) return;
      Navigator.pop(context);
      _snack(
        _isEditing
            ? 'Medication updated!'
            : 'Medication added for ${widget.patientName}!',
        Colors.green,
      );
    } catch (e) {
      if (mounted) _snack('Error saving: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: color));

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _timeLabel(Map<String, dynamic> t) =>
      '${(t['hour'] as int).toString().padLeft(2, '0')}:'
      '${(t['minute'] as int).toString().padLeft(2, '0')} ${t['period']}';

  Widget _tealTheme(BuildContext ctx, Widget? child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme:
                const ColorScheme.light(primary: _teal)),
        child: child!,
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CaregiverThemeWrapper(
      builder: (ctx, acc) {
        final cs      = Theme.of(ctx).colorScheme;
        final isDark  = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor    = isDark ? const Color(0xFF121212) : const Color(0xFFF4F7FF);
        final cardColor  = isDark ? const Color(0xFF1E1E2E) : Colors.white;
        final onSurface  = cs.onSurface;
        final hintColor  = isDark ? Colors.white38 : Colors.black38;
        final labelColor = isDark ? Colors.white70 : Colors.black87;
        final sublabelColor = isDark ? Colors.white54 : Colors.black54;
        final btnH = 52.0 * acc.buttonScaleFactor;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, size: 20, color: onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(children: [
              Text(
                _isEditing ? 'Edit Medication' : 'Add Medication',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: onSurface),
              ),
              Text('for ${widget.patientName}',
                  style: TextStyle(
                      fontSize: 12,
                      color: onSurface.withValues(alpha: 0.45))),
            ]),
            centerTitle: true,
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [

                // ── Image ─────────────────────────────────────────────
                _label('Medicine Photo (Optional)', labelColor),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: cs.primary.withValues(alpha: 0.35)),
                    ),
                    child: _buildImagePreview(isDark, cs),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Name ──────────────────────────────────────────────
                _label('Medication Name', labelColor),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: TextStyle(color: onSurface, fontSize: 14),
                  decoration: _inputDeco(
                      hintText: 'e.g. Metformin',
                      cardColor: cardColor,
                      hintColor: hintColor,
                      primary: cs.primary,
                      isDark: isDark),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a medication name'
                      : null,
                ),

                const SizedBox(height: 20),

                // ── Type ──────────────────────────────────────────────
                _label('Type', labelColor),
                const SizedBox(height: 8),
                _DropdownField<String>(
                  value: _selectedType,
                  items: _types,
                  cardColor: cardColor,
                  onSurface: onSurface,
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),

                const SizedBox(height: 20),

                // ── Dose + Unit ────────────────────────────────────────
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Dose', labelColor),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _doseController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style:
                                TextStyle(color: onSurface, fontSize: 14),
                            decoration: _inputDeco(
                                hintText: '1',
                                cardColor: cardColor,
                                hintColor: hintColor,
                                primary: cs.primary,
                                isDark: isDark),
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
                        ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Unit', labelColor),
                          const SizedBox(height: 8),
                          _DropdownField<String>(
                            value: _selectedUnit,
                            items: _units,
                            cardColor: cardColor,
                            onSurface: onSurface,
                            onChanged: (v) =>
                                setState(() => _selectedUnit = v!),
                          ),
                        ]),
                  ),
                ]),

                const SizedBox(height: 20),

                // ── Frequency ─────────────────────────────────────────
                _label('Frequency', labelColor),
                const SizedBox(height: 8),
                _buildFrequencySection(
                    cardColor, labelColor, sublabelColor, onSurface, cs),

                const SizedBox(height: 20),

                // ── Start Date ────────────────────────────────────────
                _label('Start Date', labelColor),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickStartDate,
                  child: _dateBox(
                    icon: Icons.calendar_today_outlined,
                    text: _startDate != null
                        ? _formatDate(_startDate!)
                        : 'Pick start date',
                    cardColor: cardColor,
                    onSurface: onSurface,
                  ),
                ),

                const SizedBox(height: 12),

                // ── Stop Date ─────────────────────────────────────────
                _label('Stop Date (Optional)', labelColor),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickStopDate,
                      child: _dateBox(
                        icon: Icons.event_available_outlined,
                        text: _stopDate != null
                            ? _formatDate(_stopDate!)
                            : 'No stop date',
                        cardColor: cardColor,
                        onSurface: onSurface,
                      ),
                    ),
                  ),
                  if (_stopDate != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _stopDate = null),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.close,
                              size: 18,
                              color:
                                  onSurface.withValues(alpha: 0.45)),
                        ),
                      ),
                    ),
                ]),

                const SizedBox(height: 20),

                // ── Time section ──────────────────────────────────────
                ..._buildTimeSection(
                    cardColor, labelColor, sublabelColor, onSurface, cs),

                const SizedBox(height: 20),

                // ── Note ──────────────────────────────────────────────
                _label('Note (optional)', labelColor),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  style: TextStyle(color: onSurface, fontSize: 14),
                  decoration: _inputDeco(
                      hintText: 'e.g. Take with food',
                      cardColor: cardColor,
                      hintColor: hintColor,
                      primary: cs.primary,
                      isDark: isDark),
                ),

                const SizedBox(height: 32),

                // ── Save button ───────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: btnH,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      disabledBackgroundColor:
                          cs.primary.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : Text(
                            _isEditing
                                ? 'Update Medication'
                                : 'Save Medication',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Frequency section ─────────────────────────────────────────────────────

  Widget _buildFrequencySection(Color cardColor, Color labelColor,
      Color sublabelColor, Color onSurface, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab selector
        Container(
          decoration: BoxDecoration(
              color: cardColor, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: _freqUnits.map((unit) {
              final sel = _freqUnit == unit;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _freqUnit   = unit;
                    _freqNumber = 1;
                    _syncDayFrequency();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? cs.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      unit,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel
                            ? Colors.white
                            : onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // Hour / Day counter
        if (_freqUnit == 'Hour' || _freqUnit == 'Day')
          Container(
            decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12)),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _freqNumber > 1
                      ? () => setState(() {
                            _freqNumber--;
                            _syncDayFrequency();
                          })
                      : null,
                  icon: Icon(Icons.remove_circle_outline,
                      color: _freqNumber > 1
                          ? cs.primary
                          : onSurface.withValues(alpha: 0.3)),
                ),
                Expanded(
                  child: Text(
                    _freqUnit == 'Hour'
                        ? 'Every $_freqNumber hour${_freqNumber > 1 ? 's' : ''}'
                        : '$_freqNumber time${_freqNumber > 1 ? 's' : ''} a day',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: onSurface),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _freqNumber++;
                    _syncDayFrequency();
                  }),
                  icon:
                      Icon(Icons.add_circle_outline, color: cs.primary),
                ),
              ],
            ),
          ),

        // Week — chip row
        if (_freqUnit == 'Week') ...[
          Text('Select days of the week:',
              style: TextStyle(fontSize: 12, color: sublabelColor)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [1, 2, 3, 4, 5, 6, 7].map((day) {
              final sel = _selectedWeekDays.contains(day);
              return GestureDetector(
                onTap: () => setState(() {
                  if (sel) {
                    _selectedWeekDays.remove(day);
                    _weekDayTimes.remove(day);
                  } else {
                    _selectedWeekDays.add(day);
                    _weekDayTimes.putIfAbsent(
                        day,
                        () => {'hour': 8, 'minute': 0, 'period': 'AM'});
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: sel ? cs.primary : cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel
                          ? cs.primary
                          : onSurface.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _weekDayShort[day]!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sel
                            ? Colors.white
                            : onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (_selectedWeekDays.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${_selectedWeekDays.length} day${_selectedWeekDays.length > 1 ? 's' : ''} per week selected',
              style:
                  TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
            ),
          ],
        ],

        // Month — day grid
        if (_freqUnit == 'Month') ...[
          Text('Select days of the month:',
              style: TextStyle(fontSize: 12, color: sublabelColor)),
          const SizedBox(height: 10),
          _buildMonthDayGrid(cardColor, onSurface, cs),
          if (_selectedMonthDays.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${_selectedMonthDays.length} day${_selectedMonthDays.length > 1 ? 's' : ''} per month selected',
              style:
                  TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildMonthDayGrid(
      Color cardColor, Color onSurface, ColorScheme cs) {
    // Determine the minimum selectable day:
    //  • If start date is in the current month → days before start day are past
    //  • If start date is in a future month → all 31 days are selectable
    //  • If no start date → use today as the reference
    final now       = DateTime.now();
    final ref       = _startDate ?? now;
    final int minDay;
    if (ref.year == now.year && ref.month == now.month) {
      // Start date is this month — days before today's day-of-month are past
      minDay = ref.day;
    } else if (ref.isBefore(DateTime(now.year, now.month, 1))) {
      // Start date is in a past month — all days already past; still allow all
      // so the caregiver can edit existing schedules.
      minDay = 1;
    } else {
      // Future month — all days valid
      minDay = 1;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: cardColor, borderRadius: BorderRadius.circular(12)),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemCount: 31,
        itemBuilder: (_, i) {
          final day      = i + 1;
          final sel      = _selectedMonthDays.contains(day);
          final disabled = day < minDay;
          return GestureDetector(
            onTap: disabled
                ? null
                : () => setState(() {
                      if (sel) {
                        _selectedMonthDays.remove(day);
                      } else {
                        _selectedMonthDays.add(day);
                      }
                    }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: disabled
                    ? onSurface.withValues(alpha: 0.03)
                    : sel
                        ? cs.primary
                        : onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: disabled
                        ? onSurface.withValues(alpha: 0.2)
                        : sel
                            ? Colors.white
                            : onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Time section ──────────────────────────────────────────────────────────

  List<Widget> _buildTimeSection(Color cardColor, Color labelColor,
      Color sublabelColor, Color onSurface, ColorScheme cs) {
    switch (_freqUnit) {
      case 'Hour':
        // Preview the computed schedule so the caregiver can confirm
        // the times before saving.
        final preview = _buildHourIntakeTimes();
        final previewStr = preview.length <= 4
            ? preview.map((t) => _timeLabel(t)).join(', ')
            : '${preview.sublist(0, 3).map((t) => _timeLabel(t)).join(', ')} … (${preview.length} doses/day)';
        return [
          _label('First Dose Time', labelColor),
          const SizedBox(height: 8),
          _timeTile(
            label: 'First dose at ${_timeLabel(_intakeTimes[0])}, then every $_freqNumber hour${_freqNumber > 1 ? 's' : ''}',
            onTap: () => _pickDayTime(0),
            cardColor: cardColor,
            onSurface: onSurface,
            primary: cs.primary,
          ),
          const SizedBox(height: 6),
          Text(
            'Schedule: $previewStr',
            style: TextStyle(fontSize: 12, color: sublabelColor),
          ),
        ];

      case 'Day':
        return [
          _label(
              _intakeTimes.length == 1
                  ? 'Intake Time'
                  : 'Intake Times ($_freqNumber times/day)',
              labelColor),
          const SizedBox(height: 8),
          ...List.generate(
            _intakeTimes.length,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _timeTile(
                label: _intakeTimes.length == 1 ? 'Time' : 'Dose ${i + 1}',
                trailing: _timeLabel(_intakeTimes[i]),
                onTap: () => _pickDayTime(i),
                cardColor: cardColor,
                onSurface: onSurface,
                primary: cs.primary,
              ),
            ),
          ),
        ];

      case 'Week':
        if (_selectedWeekDays.isEmpty) {
          return [
            _label('Intake Time per Day', labelColor),
            const SizedBox(height: 8),
            _timeTile(
              label: 'Select days above to set intake times',
              onTap: null,
              cardColor: cardColor,
              onSurface: onSurface,
              primary: cs.primary,
            ),
          ];
        }
        final sorted = List<int>.from(_selectedWeekDays)..sort();
        return [
          _label('Intake Time per Day', labelColor),
          const SizedBox(height: 8),
          ...sorted.map((day) {
            final t = _weekDayTimes[day] ??
                {'hour': 8, 'minute': 0, 'period': 'AM'};
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _timeTile(
                label: _weekDayFull[day]!,
                trailing: _timeLabel(t),
                onTap: () => _pickWeekDayTime(day),
                cardColor: cardColor,
                onSurface: onSurface,
                primary: cs.primary,
              ),
            );
          }),
        ];

      case 'Month':
        return [
          _label('Intake Time', labelColor),
          const SizedBox(height: 8),
          _timeTile(
            label: _selectedMonthDays.isEmpty
                ? 'Select month days above first'
                : 'All selected days at',
            trailing: _selectedMonthDays.isEmpty
                ? null
                : _timeLabel(_monthTime),
            onTap: _selectedMonthDays.isEmpty ? null : _pickMonthTime,
            cardColor: cardColor,
            onSurface: onSurface,
            primary: cs.primary,
          ),
        ];

      default:
        return [];
    }
  }

  Widget _timeTile({
    required String label,
    String? trailing,
    VoidCallback? onTap,
    required Color cardColor,
    required Color onSurface,
    required Color primary,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.access_time_outlined,
                size: 16,
                color: onTap == null
                    ? onSurface.withValues(alpha: 0.2)
                    : onSurface.withValues(alpha: 0.45)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 13,
                    color: onTap == null
                        ? onSurface.withValues(alpha: 0.3)
                        : onSurface),
              ),
            ),
            if (trailing != null) ...[
              Text(trailing,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: primary)),
              const SizedBox(width: 4),
            ],
            if (onTap != null)
              Icon(Icons.chevron_right,
                  size: 16,
                  color: onSurface.withValues(alpha: 0.3)),
          ]),
        ),
      );

  // ── Image preview ─────────────────────────────────────────────────────────

  Widget _buildImagePreview(bool isDark, ColorScheme cs) {
    final url = _imageBase64 ?? _existingImageUrl;
    if (url != null && url.startsWith('data:')) {
      try {
        final b64 = url.contains(',') ? url.split(',').last : url;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(fit: StackFit.expand, children: [
            Image.memory(base64Decode(b64), fit: BoxFit.cover),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => setState(() {
                  _imageBase64      = null;
                  _existingImageUrl = null;
                }),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.close,
                      size: 16, color: Colors.white),
                ),
              ),
            ),
          ]),
        );
      } catch (_) {}
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.add_a_photo_outlined,
              color: cs.primary, size: 26),
        ),
        const SizedBox(height: 8),
        Text('Tap to add medicine photo',
            style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.45))),
        Text('Take photo or choose from gallery',
            style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.35))),
      ],
    );
  }

  // ── Small widget helpers ──────────────────────────────────────────────────

  Widget _label(String text, Color color) => Text(
        text,
        style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: color),
      );

  Widget _dateBox({
    required IconData icon,
    required String text,
    required Color cardColor,
    required Color onSurface,
  }) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
            color: cardColor, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 16, color: onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(fontSize: 14, color: onSurface)),
        ]),
      );

  InputDecoration _inputDeco({
    required String hintText,
    required Color cardColor,
    required Color hintColor,
    required Color primary,
    required bool isDark,
  }) =>
      InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: hintColor, fontSize: 14),
        filled: true,
        fillColor: cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: isDark
                ? BorderSide(color: Colors.white.withValues(alpha: 0.08))
                : BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Colors.redAccent, width: 1.2)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Colors.redAccent, width: 1.5)),
      );
}

// ── Reusable dropdown ─────────────────────────────────────────────────────────

class _DropdownField<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final Color cardColor;
  final Color onSurface;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.cardColor,
    required this.onSurface,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
          color: cardColor, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          style: TextStyle(color: onSurface, fontSize: 14),
          dropdownColor: cardColor,
          iconEnabledColor: onSurface.withValues(alpha: 0.5),
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(e.toString(),
                        style:
                            TextStyle(color: onSurface, fontSize: 14)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}