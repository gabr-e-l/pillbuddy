// lib/screens/med_details_data.dart
//
// Holds all mutable state for MedDetailsScreen.
// Added fromModel() so the screen can be initialised from a MedicationModel
// without needing a raw Map.

import '../models/medication_model.dart';
import 'medication_form_data.dart';

class MedDetailsData {
  String name;
  String type;
  double doseAmount;
  String doseForm;
  int freqNumber;
  String freqUnit;
  DateTime? startDate;
  int hour;
  int minute;
  String period;
  String note;
  int stockCount;
  String stockUnit;
  bool isActive;

  MedDetailsData({
    required this.name,
    required this.type,
    required this.doseAmount,
    required this.doseForm,
    required this.freqNumber,
    required this.freqUnit,
    this.startDate,
    required this.hour,
    required this.minute,
    required this.period,
    this.note = '',
    this.stockCount = 30,
    this.stockUnit = 'Pills',
    this.isActive = true,
  });

  // ── Initialisers ───────────────────────────────────────────────────────────

  /// Build from a [MedicationModel] (Firestore-backed).
  factory MedDetailsData.fromModel(MedicationModel m) {
    return MedDetailsData(
      name: m.name,
      type: m.type,
      doseAmount: m.dose,
      doseForm: m.unit,
      freqNumber: m.freqNumber,
      freqUnit: m.freqUnit,
      startDate: m.startingDate,
      hour: m.hour,
      minute: m.minute,
      period: m.period,
      note: m.note,
      stockCount: m.stockCount,
      stockUnit: m.stockUnit,
      isActive: true,
    );
  }

  /// Legacy: build from a raw Map (kept for backwards-compat if needed).
  factory MedDetailsData.fromMap(Map<String, dynamic> map) {
    return MedDetailsData(
      name: map['name'] ?? '',
      type: map['type'] ?? 'Pill',
      doseAmount: (map['doseAmount'] as num?)?.toDouble() ?? 1.0,
      doseForm: map['doseForm'] ?? 'mg',
      freqNumber: map['freqNumber'] ?? 1,
      freqUnit: map['freqUnit'] ?? 'Day',
      startDate: map['startDate'] as DateTime?,
      hour: map['hour'] ?? 8,
      minute: map['minute'] ?? 0,
      period: map['period'] ?? 'AM',
      note: map['note'] ?? '',
      stockCount: map['stockCount'] ?? 30,
      stockUnit: map['stockUnit'] ?? 'Pills',
      isActive: map['isActive'] ?? true,
    );
  }

  // ── Asset helper ───────────────────────────────────────────────────────────

  String get asset {
    final match = MedicationFormData.medicationTypes.firstWhere(
      (t) => t['label']?.toLowerCase() == type.toLowerCase(),
      orElse: () => {'asset': 'assets/images/Pills.png'},
    );
    return match['asset'] ?? 'assets/images/Pills.png';
  }

  // ── Display helpers ────────────────────────────────────────────────────────

  String get formattedDate {
    if (startDate == null) return 'Not set';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${startDate!.day} ${months[startDate!.month - 1]} ${startDate!.year}';
  }

  String get formattedTime {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  String get formattedFreq =>
      freqNumber == 1 ? freqUnit : 'Every $freqNumber ${freqUnit}s';

  String get formattedDose {
    final d = doseAmount % 1 == 0
        ? doseAmount.toInt().toString()
        : doseAmount.toString();
    return '$d $doseForm';
  }

  String get formattedStock => '$stockCount $stockUnit';
}