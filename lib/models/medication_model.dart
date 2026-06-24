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

  /// For freqUnit == 'Hour': the absolute datetime of the very first dose.
  /// Used to compute which dose times fall on any given calendar date by
  /// counting forward in [freqNumber]-hour steps from this anchor.
  /// Null for non-Hour frequencies.
  final DateTime? firstDoseDateTime;

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
    this.firstDoseDateTime,
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
      'firstDoseDateTime': firstDoseDateTime != null
          ? Timestamp.fromDate(firstDoseDateTime!)
          : null,
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
      firstDoseDateTime: data['firstDoseDateTime'] != null
          ? (data['firstDoseDateTime'] as Timestamp).toDate()
          : null,
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

    // Hour — active on any date within range that has at least one dose.
    // (The actual slot computation is in doseSlotsForDate.)
    if (freqUnit == 'Hour') {
      return doseSlotsForDate(date).isNotEmpty;
    }

    // Day — active every day within the date range
    return true;
  }

  /// For 'Hour' frequency: computes the list of intake-time maps
  /// {'hour','minute','period','slotIndex'} that fall on [date].
  ///
  /// Starting from [firstDoseDateTime] (or startingDate + legacy hour/minute
  /// as fallback), we step forward by [freqNumber] hours until we pass
  /// midnight of the next day (or stopDate, whichever comes first).
  /// Only steps whose date matches [date] are returned.
  ///
  /// This makes the schedule continuous across day boundaries:
  ///   First dose 1:41 AM June 24, every 5 h, stop June 25:
  ///     June 24 → 01:41, 06:41, 11:41, 16:41, 21:41
  ///     June 25 → 02:41, 07:41, 12:41, 17:41, 22:41  (then stop date ends it)
  ///
  /// Returns [] for non-Hour frequencies (caller should use intakeTimes instead).
  List<Map<String, dynamic>> doseSlotsForDate(DateTime date) {
    if (freqUnit != 'Hour') return [];

    // Anchor: firstDoseDateTime if available, else startingDate + legacy time.
    DateTime anchor;
    if (firstDoseDateTime != null) {
      anchor = firstDoseDateTime!;
    } else if (startingDate != null) {
      // Legacy: reconstruct absolute anchor from startingDate + legacy h/m/period
      final h24 = hour % 12 + (period == 'PM' ? 12 : 0);
      anchor = DateTime(
          startingDate!.year, startingDate!.month, startingDate!.day,
          h24, minute);
    } else {
      // No anchor at all — fall back to intakeTimes (old behaviour)
      return [];
    }

    // We need the stop boundary: midnight at end of stopDate, or far future.
    final stopBoundary = stopDate != null
        ? DateTime(stopDate!.year, stopDate!.month, stopDate!.day, 23, 59, 59)
        : DateTime(9999, 12, 31);

    // Window: midnight-to-midnight for [date]
    final dayStart = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final dayEnd   = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final intervalMinutes = freqNumber * 60;

    // How many steps from anchor to dayStart (round down)?
    final toStart = dayStart.difference(anchor).inMinutes;
    // Start stepping from the first dose ON or AFTER dayStart.
    // If anchor is already after dayEnd, return empty.
    if (anchor.isAfter(dayEnd)) return [];

    // First step index that lands on or after dayStart
    final firstStep = toStart <= 0 ? 0 : (toStart / intervalMinutes).ceil();

    final slots = <Map<String, dynamic>>[];
    int slotIndex = firstStep;
    while (true) {
      final doseTime =
          anchor.add(Duration(minutes: slotIndex * intervalMinutes));
      if (doseTime.isAfter(dayEnd)) break;
      if (doseTime.isAfter(stopBoundary)) break;
      if (!doseTime.isBefore(dayStart)) {
        final h24 = doseTime.hour;
        final dp  = h24 < 12 ? 'AM' : 'PM';
        final dh12 = h24 % 12 == 0 ? 12 : h24 % 12;
        slots.add({
          'hour':      dh12,
          'minute':    doseTime.minute,
          'period':    dp,
          'slotIndex': slotIndex, // global step index (unique per dose ever)
        });
      }
      slotIndex++;
    }
    return slots;
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
    DateTime? firstDoseDateTime,
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
      firstDoseDateTime: firstDoseDateTime ?? this.firstDoseDateTime,
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