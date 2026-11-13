import 'dart:math';
import '../data/models/cycle_record.dart';
import '../data/models/profile.dart';

class CyclePhase {
  static const String menstrual = 'Menstrual';
  static const String follicular = 'Follicular';
  static const String ovulatory = 'Ovulatory';
  static const String luteal = 'Luteal';
}

class CycleStats {
  final int currentCycleDay;
  final DateTime? lastPeriodStart;
  final DateTime nextPeriodDate;
  final int daysUntilNext;
  final String phase;
  final DateTime ovulationDate;
  final DateTime fertileStart;
  final DateTime fertileEnd;
  final double avgCycleLength;
  final double avgPeriodDuration;
  final double variability; // std dev of cycle lengths
  final int recordedCycles;
  final bool hasEnoughData;
  final int? shortestCycleLength;
  final int? longestCycleLength;
  final double periodVariability;
  final int currentCycleLength;
  final int? currentPeriodDuration;

  CycleStats({
    required this.currentCycleDay,
    required this.lastPeriodStart,
    required this.nextPeriodDate,
    required this.daysUntilNext,
    required this.phase,
    required this.ovulationDate,
    required this.fertileStart,
    required this.fertileEnd,
    required this.avgCycleLength,
    required this.avgPeriodDuration,
    required this.variability,
    required this.recordedCycles,
    required this.hasEnoughData,
    required this.shortestCycleLength,
    required this.longestCycleLength,
    required this.periodVariability,
    required this.currentCycleLength,
    required this.currentPeriodDuration,
  });
}

class CycleEngine {
  static const int defaultCycle = 28;
  static const int defaultDuration = 5;
  static const int lutealLength = 14;

  /// Compute average cycle length from sorted period starts.
  static double averageCycleLength(List<CycleRecord> records, {int fallback = defaultCycle}) {
    final starts = records.map((r) => r.startDate).toList()..sort();
    if (starts.length < 2) return fallback.toDouble();
    final lengths = <int>[];
    for (int i = 1; i < starts.length; i++) {
      lengths.add(starts[i].difference(starts[i - 1]).inDays);
    }
    return lengths.reduce((a, b) => a + b) / lengths.length;
  }

  static double averagePeriodDuration(List<CycleRecord> records, {int fallback = defaultDuration}) {
    if (records.isEmpty) return fallback.toDouble();
    final ds = records.map((r) => r.periodDuration).toList();
    return ds.reduce((a, b) => a + b) / ds.length;
  }

  static double cycleVariability(List<CycleRecord> records) {
    final starts = records.map((r) => r.startDate).toList()..sort();
    if (starts.length < 3) return 0;
    final lengths = <int>[];
    for (int i = 1; i < starts.length; i++) {
      lengths.add(starts[i].difference(starts[i - 1]).inDays);
    }
    final mean = lengths.reduce((a, b) => a + b) / lengths.length;
    final variance = lengths.map((l) => pow(l - mean, 2)).reduce((a, b) => a + b) / lengths.length;
    return sqrt(variance);
  }

  /// Returns the latest period start on or before [today].
  static DateTime? lastPeriodStart(List<CycleRecord> records, DateTime today) {
    final starts = records.map((r) => _dateOnly(r.startDate)).toList()..sort();
    DateTime? last;
    for (final s in starts) {
      if (!s.isAfter(_dateOnly(today))) {
        last = s;
      }
    }
    return last;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static CycleStats compute({
    required Profile? profile,
    required List<CycleRecord> records,
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());

    // Build effective records: include profile's lastPeriodStart as a record if missing.
    final effective = List<CycleRecord>.from(records);
    if (profile != null) {
      final pStart = _dateOnly(profile.lastPeriodStart);
      if (!effective.any((r) => _sameDay(r.startDate, pStart))) {
        effective.add(CycleRecord(startDate: pStart, periodDuration: profile.avgPeriodDuration));
      }
    }
    effective.sort((a, b) => a.startDate.compareTo(b.startDate));

    final avgCycle = profile != null
        ? averageCycleLength(effective, fallback: profile.avgCycleLength)
        : averageCycleLength(effective);
    // If profile provided and enough? Use profile default only when no records; averageCycleLength already fallback.
    final avgDur = profile != null
        ? averagePeriodDuration(effective, fallback: profile.avgPeriodDuration)
        : averagePeriodDuration(effective);

    final lastStart = lastPeriodStart(effective, today);
    DateTime baseStart;
    if (lastStart != null) {
      baseStart = lastStart;
    } else if (profile != null) {
      baseStart = _dateOnly(profile.lastPeriodStart);
    } else {
      baseStart = today;
    }

    // If last start is in future, adjust
    if (baseStart.isAfter(today)) {
      // find previous cycle? fallback: subtract avgCycle
      baseStart = baseStart.subtract(Duration(days: avgCycle.round()));
    }

    final currentDay = today.difference(baseStart).inDays + 1;
    // clamp to at least 1
    final day = currentDay < 1 ? 1 : currentDay;

    // next period: advance baseStart by whole cycles until strictly after today
    DateTime next = baseStart.add(Duration(days: avgCycle.round()));
    while (!next.isAfter(today)) {
      next = next.add(Duration(days: avgCycle.round()));
    }

    final daysUntil = next.difference(today).inDays;
    final safeDaysUntil = daysUntil < 0 ? 0 : daysUntil;

    // Ovulation: 14 days before next period
    final ovulation = next.subtract(const Duration(days: lutealLength));
    final fertileStart = ovulation.subtract(const Duration(days: 5));
    final fertileEnd = ovulation.add(const Duration(days: 1));

    final phase = _phaseForDay(day, avgCycle.round(), avgDur.round());

    final hasEnough = effective.length >= 2;

    final cycleLengths = <int>[];
    final sortedStarts = effective.map((r) => _dateOnly(r.startDate)).toList()..sort();
    for (int i = 1; i < sortedStarts.length; i++) {
      cycleLengths.add(sortedStarts[i].difference(sortedStarts[i - 1]).inDays);
    }
    int? shortest = cycleLengths.isEmpty ? null : cycleLengths.reduce((a, b) => a < b ? a : b);
    int? longest = cycleLengths.isEmpty ? null : cycleLengths.reduce((a, b) => a > b ? a : b);

    final periodDurations = effective.map((r) => r.periodDuration).toList();
    double periodVar = 0;
    if (periodDurations.length >= 2) {
      final mean = periodDurations.reduce((a, b) => a + b) / periodDurations.length;
      final variance = periodDurations.map((d) => pow(d - mean, 2)).reduce((a, b) => a + b) / periodDurations.length;
      periodVar = sqrt(variance);
    }

    CycleRecord? currentRecord;
    for (final r in effective) {
      if (_sameDay(r.startDate, baseStart)) {
        currentRecord = r;
        break;
      }
    }

    return CycleStats(
      currentCycleDay: day,
      lastPeriodStart: baseStart,
      nextPeriodDate: next,
      daysUntilNext: safeDaysUntil,
      phase: phase,
      ovulationDate: ovulation,
      fertileStart: fertileStart,
      fertileEnd: fertileEnd,
      avgCycleLength: avgCycle,
      avgPeriodDuration: avgDur,
      variability: cycleVariability(effective),
      recordedCycles: effective.length,
      hasEnoughData: hasEnough,
      shortestCycleLength: shortest,
      longestCycleLength: longest,
      periodVariability: periodVar,
      currentCycleLength: day,
      currentPeriodDuration: currentRecord?.periodDuration,
    );
  }

  static String _phaseForDay(int day, int cycleLen, int periodDur) {
    if (day <= periodDur) return CyclePhase.menstrual;
    final ovulationDay = cycleLen - lutealLength; // e.g. 14 for 28
    if (day >= ovulationDay - 1 && day <= ovulationDay + 1) return CyclePhase.ovulatory;
    if (day < ovulationDay) return CyclePhase.follicular;
    return CyclePhase.luteal;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
