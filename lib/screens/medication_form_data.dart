// medication_form_data.dart

class MedicationFormData {
  String name = '';
  String? type;
  double dose = 0.5;
  int freqNumber = 1;
  String freqUnit = 'Day';
  DateTime? startingDate;
  int hour = 1;
  int minute = 0;
  String period = 'AM';
  String note = '';

  static const List<Map<String, String>> medicationTypes = [
    {'label': 'Capsule', 'asset': 'assets/images/capsule.png', 'unit': 'mg'},
    {'label': 'Pill', 'asset': 'assets/images/Pills.png', 'unit': 'mg'},
    {'label': 'Injection', 'asset': 'assets/images/Injection.png', 'unit': 'cc'},
    {'label': 'Spray', 'asset': 'assets/images/Sprayer.png', 'unit': 'sprays'},
    {'label': 'Drop', 'asset': 'assets/images/Eye Dropper.png', 'unit': 'drops'},
    {'label': 'Syrup', 'asset': 'assets/images/Syrup.png', 'unit': 'ml'},
    {'label': 'Others', 'asset': 'assets/images/more-horizontal.png', 'unit': 'dose'},
  ];

  static const List<String> freqUnits = ['Hour', 'Day', 'Week', 'Month'];

  String get currentUnit {
    final match = medicationTypes.firstWhere(
      (t) => t['label'] == type,
      orElse: () => {'unit': 'dose'},
    );
    return match['unit'] ?? 'dose';
  }
}
