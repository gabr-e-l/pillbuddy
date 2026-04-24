// lib/models/medication_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationModel {
  final String? id; // Firestore document ID
  final String name;
  final String type;
  final double dose;
  final String unit;
  final int freqNumber;
  final String freqUnit;
  final DateTime? startingDate;
  final int hour;
  final int minute;
  final String period;
  final String note;
  final int stockCount;
  final String stockUnit;
  final DateTime createdAt;

  MedicationModel({
    this.id,
    required this.name,
    required this.type,
    required this.dose,
    required this.unit,
    required this.freqNumber,
    required this.freqUnit,
    this.startingDate,
    required this.hour,
    required this.minute,
    required this.period,
    this.note = '',
    this.stockCount = 30,
    this.stockUnit = 'Pills',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Convert to a plain Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'dose': dose,
      'unit': unit,
      'freqNumber': freqNumber,
      'freqUnit': freqUnit,
      'startingDate': startingDate != null
          ? Timestamp.fromDate(startingDate!)
          : null,
      'hour': hour,
      'minute': minute,
      'period': period,
      'note': note,
      'stockCount': stockCount,
      'stockUnit': stockUnit,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Build from a Firestore DocumentSnapshot
  factory MedicationModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MedicationModel(
      id: doc.id,
      name: data['name'] ?? '',
      type: data['type'] ?? 'Pill',
      dose: (data['dose'] as num?)?.toDouble() ?? 1.0,
      unit: data['unit'] ?? 'mg',
      freqNumber: data['freqNumber'] ?? 1,
      freqUnit: data['freqUnit'] ?? 'Day',
      startingDate: data['startingDate'] != null
          ? (data['startingDate'] as Timestamp).toDate()
          : null,
      hour: data['hour'] ?? 8,
      minute: data['minute'] ?? 0,
      period: data['period'] ?? 'AM',
      note: data['note'] ?? '',
      stockCount: data['stockCount'] ?? 30,
      stockUnit: data['stockUnit'] ?? 'Pills',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// Human-readable time string, e.g. "08:30 AM | Daily"
  String get timeLabel {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    final freq = freqNumber == 1 ? freqUnit : 'Every $freqNumber ${freqUnit}s';
    return '$h:$m $period | $freq';
  }

  /// Human-readable dose string, e.g. "1.5 mg"
  String get doseLabel {
    final d = dose % 1 == 0 ? dose.toInt().toString() : dose.toString();
    return '$d $unit';
  }

  /// Create a copy with updated fields
  MedicationModel copyWith({
    String? id,
    String? name,
    String? type,
    double? dose,
    String? unit,
    int? freqNumber,
    String? freqUnit,
    DateTime? startingDate,
    int? hour,
    int? minute,
    String? period,
    String? note,
    int? stockCount,
    String? stockUnit,
  }) {
    return MedicationModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      dose: dose ?? this.dose,
      unit: unit ?? this.unit,
      freqNumber: freqNumber ?? this.freqNumber,
      freqUnit: freqUnit ?? this.freqUnit,
      startingDate: startingDate ?? this.startingDate,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      period: period ?? this.period,
      note: note ?? this.note,
      stockCount: stockCount ?? this.stockCount,
      stockUnit: stockUnit ?? this.stockUnit,
      createdAt: this.createdAt,
    );
  }
}