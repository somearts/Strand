class Profile {
  final String name;
  final DateTime dateOfBirth;
  final DateTime lastPeriodStart;
  final int avgCycleLength;
  final int avgPeriodDuration;

  Profile({
    required this.name,
    required this.dateOfBirth,
    required this.lastPeriodStart,
    this.avgCycleLength = 28,
    this.avgPeriodDuration = 5,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'dob': dateOfBirth.millisecondsSinceEpoch,
        'lastPeriodStart': lastPeriodStart.millisecondsSinceEpoch,
        'avgCycleLength': avgCycleLength,
        'avgPeriodDuration': avgPeriodDuration,
      };

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        name: m['name'] as String,
        dateOfBirth: DateTime.fromMillisecondsSinceEpoch(m['dob'] as int),
        lastPeriodStart: DateTime.fromMillisecondsSinceEpoch(m['lastPeriodStart'] as int),
        avgCycleLength: (m['avgCycleLength'] as int?) ?? 28,
        avgPeriodDuration: (m['avgPeriodDuration'] as int?) ?? 5,
      );
}
