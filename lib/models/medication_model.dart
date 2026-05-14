// lib/models/medication_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationModel {
  final String? id;
  final String name;
  final String type;
  final double dose;
  final String unit;
  final int freqNumber;
  final String freqUnit;
  final DateTime? startingDate;
  final DateTime? stopDate;
  final List<Map<String, dynamic>> intakeTimes;

  /// For freqUnit == 'Week': list of weekday ints (1=Mon … 7=Sun, per DateTime.weekday)
  final List<int> selectedWeekDays;

  /// For freqUnit == 'Month': list of month-day ints (1–31)
  final List<int> selectedMonthDays;

  // Legacy single-time fields (kept for backward compat)
  final int hour;
  final int minute;
  final String period;
  final String note;
  final int stockCount;
  final String stockUnit;
  final DateTime createdAt;
  final String? imageUrl;

  MedicationModel({
    this.id,
    required this.name,
    required this.type,
    required this.dose,
    required this.unit,
    required this.freqNumber,
    required this.freqUnit,
    this.startingDate,
    this.stopDate,
    List<Map<String, dynamic>>? intakeTimes,
    List<int>? selectedWeekDays,
    List<int>? selectedMonthDays,
    required this.hour,
    required this.minute,
    required this.period,
    this.note = '',
    this.stockCount = 30,
    this.stockUnit = 'Pills',
    DateTime? createdAt,
    this.imageUrl,
  })  : intakeTimes = intakeTimes ?? [],
        selectedWeekDays = selectedWeekDays ?? [],
        selectedMonthDays = selectedMonthDays ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'dose': dose,
      'unit': unit,
      'freqNumber': freqNumber,
      'freqUnit': freqUnit,
      'startingDate':
          startingDate != null ? Timestamp.fromDate(startingDate!) : null,
      'stopDate': stopDate != null ? Timestamp.fromDate(stopDate!) : null,
      'intakeTimes': intakeTimes,
      'selectedWeekDays': selectedWeekDays,
      'selectedMonthDays': selectedMonthDays,
      'hour': hour,
      'minute': minute,
      'period': period,
      'note': note,
      'stockCount': stockCount,
      'stockUnit': stockUnit,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory MedicationModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    List<Map<String, dynamic>> times = [];
    if (data['intakeTimes'] != null) {
      times = List<Map<String, dynamic>>.from(
        (data['intakeTimes'] as List).map((e) => Map<String, dynamic>.from(e)),
      );
    }

    List<int> weekDays = [];
    if (data['selectedWeekDays'] != null) {
      weekDays = List<int>.from(data['selectedWeekDays'] as List);
    }

    List<int> monthDays = [];
    if (data['selectedMonthDays'] != null) {
      monthDays = List<int>.from(data['selectedMonthDays'] as List);
    }

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
      stopDate: data['stopDate'] != null
          ? (data['stopDate'] as Timestamp).toDate()
          : null,
      intakeTimes: times,
      selectedWeekDays: weekDays,
      selectedMonthDays: monthDays,
      hour: data['hour'] ?? 8,
      minute: data['minute'] ?? 0,
      period: data['period'] ?? 'AM',
      note: data['note'] ?? '',
      stockCount: data['stockCount'] ?? 30,
      stockUnit: data['stockUnit'] ?? 'Pills',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      imageUrl: data['imageUrl'] as String?,
    );
  }

  String get timeLabel {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  String get doseLabel {
    final d = dose % 1 == 0 ? dose.toInt().toString() : dose.toString();
    return '$d $unit';
  }

  Map<String, dynamic> get primaryTime {
    if (intakeTimes.isNotEmpty) return intakeTimes.first;
    return {'hour': hour, 'minute': minute, 'period': period};
  }

  /// Returns true if this medication should be taken on [date].
  bool isActiveOn(DateTime date) {
    final sel = DateTime(date.year, date.month, date.day);

    // Check start date
    if (startingDate != null) {
      final s = DateTime(
          startingDate!.year, startingDate!.month, startingDate!.day);
      if (sel.isBefore(s)) return false;
    }

    // Check stop date
    if (stopDate != null) {
      final e =
          DateTime(stopDate!.year, stopDate!.month, stopDate!.day);
      if (sel.isAfter(e)) return false;
    }

    // Weekly schedule
    if (freqUnit == 'Week' && selectedWeekDays.isNotEmpty) {
      return selectedWeekDays.contains(date.weekday);
    }

    // Monthly schedule
    if (freqUnit == 'Month' && selectedMonthDays.isNotEmpty) {
      return selectedMonthDays.contains(date.day);
    }

    // Hour / Day — active every day within the date range
    return true;
  }

  MedicationModel copyWith({
    String? id,
    String? name,
    String? type,
    double? dose,
    String? unit,
    int? freqNumber,
    String? freqUnit,
    DateTime? startingDate,
    DateTime? stopDate,
    List<Map<String, dynamic>>? intakeTimes,
    List<int>? selectedWeekDays,
    List<int>? selectedMonthDays,
    int? hour,
    int? minute,
    String? period,
    String? note,
    int? stockCount,
    String? stockUnit,
    String? imageUrl,
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
      stopDate: stopDate ?? this.stopDate,
      intakeTimes: intakeTimes ?? this.intakeTimes,
      selectedWeekDays: selectedWeekDays ?? this.selectedWeekDays,
      selectedMonthDays: selectedMonthDays ?? this.selectedMonthDays,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      period: period ?? this.period,
      note: note ?? this.note,
      stockCount: stockCount ?? this.stockCount,
      stockUnit: stockUnit ?? this.stockUnit,
      createdAt: this.createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}