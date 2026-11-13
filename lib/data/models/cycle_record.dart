class CycleRecord {
  final DateTime startDate;
  final int periodDuration;

  CycleRecord({required this.startDate, required this.periodDuration});

  Map<String, dynamic> toMap() => {
        'start': startDate.millisecondsSinceEpoch,
        'duration': periodDuration,
      };

  factory CycleRecord.fromMap(Map<String, dynamic> m) => CycleRecord(
        startDate: DateTime.fromMillisecondsSinceEpoch(m['start'] as int),
        periodDuration: (m['duration'] as int?) ?? 5,
      );
}

class Observation {
  final DateTime date;
  final String flow; // light/medium/heavy
  final String cramps; // none/mild/moderate/severe
  final List<String> symptoms;

  Observation({
    required this.date,
    required this.flow,
    required this.cramps,
    this.symptoms = const [],
  });

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'flow': flow,
        'cramps': cramps,
        'symptoms': symptoms,
      };

  factory Observation.fromMap(Map<String, dynamic> m) => Observation(
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        flow: (m['flow'] as String?) ?? 'medium',
        cramps: (m['cramps'] as String?) ?? 'none',
        symptoms: (m['symptoms'] as List?)?.cast<String>() ?? const [],
      );
}
