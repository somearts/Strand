/// Sleep statistics over real stored nights.
///
/// **This file is pure Dart and Flutter-free on purpose.** It is the arithmetic
/// behind the rings on the homepage and every number on Insights, and keeping
/// it out of a widget is what lets the same calculation serve both pages — and
/// what lets a missing stage stay missing instead of being rounded to zero on
/// the way to a chart.
///
/// The rules it enforces, in one place:
///
/// * **A stage that was not recorded is null, never `Duration.zero`.** A zero
///   is a measurement ("no deep sleep"); null is the absence of one. Averaging
///   the two together is how a dashboard starts lying.
/// * **A night is dated by the morning it ends on.** [StrandSleep.night] already
///   does this, and every calculation here groups on it, so the homepage ring,
///   the period totals and the comparisons cannot disagree about which day a
///   night belongs to.
/// * **Invalid and overlapping records are removed before any arithmetic.**
///   Zero-length sessions, future sessions, and duplicate or overlapping
///   reports of the same night are dropped rather than counted twice.
/// * **Comparisons use equal-length adjacent windows.** A 30-day period is
///   compared with the 30 days immediately before it, not with "whatever came
///   before".
library;

import 'dart:math' as math;

import '../presentation/sleep_format.dart';
import '../strand_sleep.dart';

/// The four windows offered on Insights.
enum SleepRange {
  week('7D', 'Last 7 days'),
  month('30D', 'Last 30 days'),
  quarter('90D', 'Last 90 days'),
  all('ALL', 'All available history');

  const SleepRange(this.shortLabel, this.label);

  /// "7D", for the selector where space is short.
  final String shortLabel;

  /// "Last 7 days", for a caption that can spell it out.
  final String label;

  /// Nights in the window, or 0 for "everything".
  int get days => switch (this) {
    SleepRange.week => 7,
    SleepRange.month => 30,
    SleepRange.quarter => 90,
    SleepRange.all => 0,
  };

  /// Only a bounded window has a preceding window of the same length.
  bool get comparable => this != SleepRange.all;
}

/// One night, after duplicates and overlaps have been resolved.
///
/// This is *not* the same as one [StrandSleep]: a night that a phone and a
/// watch both reported as two records is one night here, and a nap and a main
/// sleep that end on the same morning are summed into one date. Every field is
/// still the sum of real sessions; nothing is estimated.
class NightSummary {
  const NightSummary({
    required this.date,
    required this.start,
    required this.end,
    required this.mainStart,
    required this.mainEnd,
    required this.timeInBed,
    required this.asleep,
    required this.deep,
    required this.rem,
    required this.light,
    required this.awake,
    required this.hasStageFigures,
    required this.sessionCount,
    this.spans = const <SleepStageSpan>[],
    this.metrics,
  });

  /// The local calendar date the night is filed under: the morning it ended.
  final DateTime date;

  /// First fall-asleep moment of any session that night.
  final DateTime start;

  /// Last wake-up moment of any session that night.
  final DateTime end;

  /// When the night's main (longest) session began.
  ///
  /// Bedtime and wake-up are taken from this session rather than from [start]
  /// and [end]: a nap on the same date can begin before the main sleep, and
  /// using the outer bounds would report the nap's start as the bedtime.
  final DateTime mainStart;

  /// When the night's main (longest) session ended.
  final DateTime mainEnd;

  /// Length of the main session.
  Duration get mainWindow => mainEnd.difference(mainStart);

  /// Whether this night has a main sleep long enough to describe a bedtime and
  /// a wake-up. A nap has a start and an end, but it is not a night.
  ///
  /// Duration alone cannot decide: a two-hour lunchtime nap is not a bedtime,
  /// while a genuinely short night is still a night. So the main session must
  /// also run through the small hours or be long enough to be someone's main
  /// sleep. A late bedtime, an early wake, a session crossing midnight and a
  /// shifted schedule each pass one of those tests; an ordinary nap does not.
  bool get tracksClock {
    if (mainWindow < SleepAnalytics.minClockSession) return false;
    final bool throughNight =
        mainStart.day != mainEnd.day || mainStart.hour < 6;
    return throughNight || mainWindow >= SleepAnalytics.longSleepSession;
  }

  /// Sum of the session windows. Always available for a valid night.
  final Duration timeInBed;

  /// Time genuinely asleep, or null when the source reported no breakdown.
  ///
  /// **Null is not zero.** A source that sent a session and no stages has not
  /// measured sleep, and reporting 0h would be inventing a measurement.
  final Duration? asleep;

  final Duration? deep;
  final Duration? rem;
  final Duration? light;

  /// Time awake inside the session(s). Never part of [asleep].
  final Duration? awake;

  /// Whether every contributing session reported stage figures at all.
  final bool hasStageFigures;

  final int sessionCount;

  /// Stage segments for the hypnogram, when available.
  final List<SleepStageSpan> spans;

  /// Overnight body metrics, when the source supplied them.
  final NightMetrics? metrics;
  /// Whether a total sleep figure can be stated.
  bool get hasSleep => asleep != null;

  /// Whether at least one of the three named sleep stages is available.
  bool get hasNamedStages => deep != null || rem != null || light != null;

  /// One stage's duration, or null when it was not recorded.
  Duration? stageDuration(SleepStage stage) => switch (stage) {
    SleepStage.deep => deep,
    SleepStage.rem => rem,
    SleepStage.light => light,
    SleepStage.awake || SleepStage.awakeInBed => awake,
    _ => null,
  };

  /// One stage's share of total sleep, or null when either figure is unknown.
  double? stageShare(SleepStage stage) {
    final Duration? total = asleep;
    final Duration? part = stageDuration(stage);
    if (total == null || part == null || total <= Duration.zero) return null;
    return (part.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  /// One stage's share of time in bed.
  ///
  /// Used for awake, which is not part of total sleep: dividing it by sleep
  /// would let a restless night report more awake time than sleep and call it
  /// a percentage.
  double? shareOfTimeInBed(SleepStage stage) {
    final Duration? part = stageDuration(stage);
    if (part == null || timeInBed <= Duration.zero) return null;
    return (part.inMilliseconds / timeInBed.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Sleep the source recorded without naming a stage.
  ///
  /// Only answered when the three named stages and the total are all present;
  /// otherwise the remainder is not "unspecified sleep", it is unknown data.
  Duration? get unspecifiedSleep {
    final Duration? total = asleep;
    if (total == null || deep == null || rem == null || light == null) {
      return null;
    }
    final Duration remainder = total - deep! - rem! - light!;
    return remainder.isNegative ? Duration.zero : remainder;
  }
}

/// Circular statistics for a time of day.
///
/// Bedtime wraps at midnight: 23:50 and 00:10 are twenty minutes apart, while
/// their numeric hour values are almost a day apart. A normal average of the
/// two would report noon. This treats a clock as a circle instead, which is the
/// only average that is true for times.
///
/// [spreadMinutes] is the circular standard deviation — the square root of
/// minus twice the log of the mean resultant length — not the linear standard
/// deviation of clock minutes. [minimumMinutes] and [maximumMinutes] are the
/// observed extremes placed on the same circle as the mean, so the displayed
/// average and the drawn range come from one calculation and cannot disagree.
class ClockStats {
  const ClockStats._({
    required this.count,
    required this.meanMinutes,
    required this.spreadMinutes,
    required this.minimumMinutes,
    required this.maximumMinutes,
  });

  const ClockStats.empty()
    : count = 0,
      meanMinutes = null,
      spreadMinutes = null,
      minimumMinutes = null,
      maximumMinutes = null;

  /// How many nights contributed.
  final int count;

  /// Mean time of day, in minutes after midnight (0..1439.99).
  final double? meanMinutes;

  /// Circular standard deviation, in minutes. Null for fewer than two nights.
  final double? spreadMinutes;

  /// Earliest observed time, unwrapped around [meanMinutes].
  ///
  /// May fall below 0 or above 1440; it is a coordinate on the same line as
  /// the mean, not a clock reading. A value modulo 1440 is the clock time.
  final double? minimumMinutes;

  /// Latest observed time, unwrapped around [meanMinutes].
  final double? maximumMinutes;

  bool get hasMean => meanMinutes != null;

  /// Signed shortest distance around the clock, in minutes, in (-720, 720].
  static double _wrap(double difference) {
    double value = difference % 1440;
    if (value > 720) value -= 1440;
    return value;
  }

  static ClockStats from(List<double> minutesOfDay) {
    if (minutesOfDay.isEmpty) return const ClockStats.empty();
    double sin = 0;
    double cos = 0;
    for (final double m in minutesOfDay) {
      final double angle = 2 * math.pi * m / 1440.0;
      sin += math.sin(angle);
      cos += math.cos(angle);
    }
    final double n = minutesOfDay.length.toDouble();
    final double meanAngle = math.atan2(sin / n, cos / n);
    double mean = meanAngle * 1440.0 / (2 * math.pi);
    if (mean < 0) mean += 1440;
    mean %= 1440;

    // Place every observation on the side of the clock nearest the mean, so
    // 23:50 and 00:10 sit 20 minutes apart instead of a day apart.
    double lowest = double.infinity;
    double highest = double.negativeInfinity;
    for (final double m in minutesOfDay) {
      final double placed = mean + _wrap(m - mean);
      if (placed < lowest) lowest = placed;
      if (placed > highest) highest = placed;
    }

    double? spread;
    if (minutesOfDay.length >= 2) {
      final double r = math.sqrt(
        (sin / n) * (sin / n) + (cos / n) * (cos / n),
      );
      if (r <= 1e-9) {
        // Maximally scattered: the deviation is effectively a full day.
        spread = 720;
      } else {
        spread = math.sqrt(-2 * math.log(r)) * 1440.0 / (2 * math.pi);
        if (spread.isNaN || spread.isInfinite) spread = 720;
      }
    }
    return ClockStats._(
      count: minutesOfDay.length,
      meanMinutes: mean,
      spreadMinutes: spread,
      minimumMinutes: lowest,
      maximumMinutes: highest,
    );
  }
}

/// Every figure Insights needs for one period, computed once.
class SleepStats {
  SleepStats._({
    required this.nights,
    required this.averageSleep,
    required this.sleepNights,
    required this.averageTimeInBed,
    required this.averageDeep,
    required this.deepNights,
    required this.averageRem,
    required this.remNights,
    required this.averageLight,
    required this.lightNights,
    required this.averageAwake,
    required this.awakeNights,
    required this.distributionNights,
    required this.distributionSleep,
    required this.distributionDeep,
    required this.distributionRem,
    required this.distributionLight,
    required this.distributionDeepShare,
    required this.distributionRemShare,
    required this.distributionLightShare,
    required this.averageAwakeShare,
    required this.clockNights,
    required this.longestSleep,
    required this.longestSleepDate,
    required this.sleepStdDevMinutes,
    required this.bedtime,
    required this.wake,
  });

  final List<NightSummary> nights;

  final Duration? averageSleep;

  /// How many nights contributed to [averageSleep].
  final int sleepNights;

  final Duration? averageTimeInBed;

  final Duration? averageDeep;
  final int deepNights;
  final Duration? averageRem;
  final int remNights;
  final Duration? averageLight;
  final int lightNights;
  final Duration? averageAwake;
  final int awakeNights;

  /// Nights where total sleep and all three named stages were recorded.
  ///
  /// The stage distribution is computed over exactly these nights, so deep,
  /// REM and light shares come from one common set of measurements and add up
  /// to at most 100%. Averaging each stage over its own differing set of
  /// nights can produce shares that total more than the whole.
  final int distributionNights;
  final Duration? distributionSleep;
  final Duration? distributionDeep;
  final Duration? distributionRem;
  final Duration? distributionLight;

  final double? distributionDeepShare;
  final double? distributionRemShare;
  final double? distributionLightShare;
  final double? averageAwakeShare;

  /// Whole percentages for the three named stages, rounded together so the
  /// three labels add up to the same total as the underlying distribution.
  ///
  /// Null unless all three stages were recorded on every contributing night.
  /// The values use total sleep as their denominator — never time in bed.
  List<int>? get distributionPercents {
    final double? deep = distributionDeepShare;
    final double? rem = distributionRemShare;
    final double? light = distributionLightShare;
    if (deep == null || rem == null || light == null) return null;
    final List<double> exact = <double>[deep * 100, rem * 100, light * 100];
    final List<int> whole = <int>[for (final double v in exact) v.floor()];
    final int target = ((deep + rem + light) * 100).round().clamp(0, 100);
    int missing = target - (whole[0] + whole[1] + whole[2]);
    final List<int> order = <int>[0, 1, 2]
      ..sort(
        (int a, int b) =>
            (exact[b] - whole[b]).compareTo(exact[a] - whole[a]),
      );
    int step = 0;
    while (missing > 0) {
      whole[order[step % 3]]++;
      missing--;
      step++;
    }
    return whole;
  }

  /// The share of the distribution's total sleep that no named stage covered.
  ///
  /// Null when there is no complete distribution. A value of 0 means every
  /// measured minute was named; it does not mean the stage was missing.
  int? get distributionUnnamedPercent {
    final List<int>? percents = distributionPercents;
    if (percents == null) return null;
    return (100 - (percents[0] + percents[1] + percents[2])).clamp(0, 100);
  }

  /// Nights with a main sleep long enough to describe a bedtime and wake-up.
  final int clockNights;

  final Duration? longestSleep;
  final DateTime? longestSleepDate;

  /// Standard deviation of nightly total sleep, in minutes.
  final double? sleepStdDevMinutes;

  final ClockStats bedtime;
  final ClockStats wake;

  /// Number of recorded nights in the period.
  int get nightCount => nights.length;

  /// Nights that could contribute a total sleep figure.
  int get nightsWithSleep => sleepNights;

  /// Nights with at least one named stage.
  int get nightsWithStages =>
      nights.where((NightSummary n) => n.hasNamedStages).length;

  bool get isEmpty => nights.isEmpty;

  /// Not enough nights for a statement that deserves to be called a trend.
  bool get isSparse => nights.length < 3;

  static SleepStats of(List<NightSummary> nights) {
    final List<NightSummary> ordered = List<NightSummary>.of(nights)
      ..sort((NightSummary a, NightSummary b) => a.date.compareTo(b.date));

    Duration? averageOf(Iterable<Duration?> values) {
      int count = 0;
      int millis = 0;
      for (final Duration? value in values) {
        if (value == null) continue;
        count++;
        millis += value.inMilliseconds;
      }
      if (count == 0) return null;
      return Duration(milliseconds: millis ~/ count);
    }

    int countOf(Iterable<Duration?> values) =>
        values.where((Duration? d) => d != null).length;

    final List<Duration> sleepValues = <Duration>[
      for (final NightSummary n in ordered)
        if (n.asleep != null) n.asleep!,
    ];

    Duration? longest;
    DateTime? longestDate;
    for (final NightSummary n in ordered) {
      if (n.asleep == null) continue;
      if (longest == null || n.asleep! > longest) {
        longest = n.asleep;
        longestDate = n.date;
      }
    }

    final List<double> sleepMinutes = <double>[
      for (final Duration d in sleepValues) d.inMilliseconds / 60000.0,
    ];

    // Bedtime and wake-up come from each night's main (longest) session, not
    // from the night's outer bounds: a nap filed on the same date must not
    // become the bedtime. A main session shorter than the minimum is a nap
    // rather than a night and is left out of the clock statistics entirely.
    final List<NightSummary> clock = ordered
        .where((NightSummary n) => n.tracksClock)
        .toList();

    final List<double> bedtimes = <double>[
      for (final NightSummary n in clock)
        n.mainStart.hour * 60.0 +
            n.mainStart.minute +
            n.mainStart.second / 60.0,
    ];
    final List<double> wakes = <double>[
      for (final NightSummary n in clock)
        n.mainEnd.hour * 60.0 +
            n.mainEnd.minute +
            n.mainEnd.second / 60.0,
    ];

    // Nights with a complete named breakdown. Shares are computed over this
    // one set so the distribution adds up: averaging deep over 18 nights and
    // light over 28 can report 106% of a night's sleep. A night whose stages
    // add up to more than its total sleep is malformed and is not used for
    // the distribution (it is still counted in the individual averages).
    final List<NightSummary> full = <NightSummary>[
      for (final NightSummary n in ordered)
        if (n.asleep != null &&
            n.asleep! > Duration.zero &&
            n.deep != null &&
            n.rem != null &&
            n.light != null &&
            (n.deep! + n.rem! + n.light!) <= n.asleep! * 1.005)
          n,
    ];

    final Duration? distributionSleep = averageOf(
      full.map((NightSummary n) => n.asleep),
    );
    final Duration? distributionDeep = averageOf(
      full.map((NightSummary n) => n.deep),
    );
    final Duration? distributionRem = averageOf(
      full.map((NightSummary n) => n.rem),
    );
    final Duration? distributionLight = averageOf(
      full.map((NightSummary n) => n.light),
    );

    double? shareOf(Duration? part, Duration? whole) {
      if (part == null || whole == null || whole <= Duration.zero) return null;
      return (part.inMilliseconds / whole.inMilliseconds).clamp(0.0, 1.0);
    }

    // Guard against stages that overlap or exceed the total by more than
    // rounding: scale the three shares back onto the whole so a malformed
    // breakdown cannot produce a distribution above 100%.
    double namedScale = 1;
    if (distributionSleep != null &&
        distributionSleep > Duration.zero &&
        distributionDeep != null &&
        distributionRem != null &&
        distributionLight != null) {
      final int namedMillis =
          distributionDeep.inMilliseconds +
          distributionRem.inMilliseconds +
          distributionLight.inMilliseconds;
      final double raw = namedMillis / distributionSleep.inMilliseconds;
      if (raw > 1) namedScale = 1 / raw;
    }

    double? scaledShare(Duration? part, Duration? whole) {
      final double? share = shareOf(part, whole);
      return share == null ? null : share * namedScale;
    }

    double? averageShare(
      Iterable<NightSummary> source,
      double? Function(NightSummary) part,
    ) {
      int count = 0;
      double sum = 0;
      for (final NightSummary n in source) {
        final double? value = part(n);
        if (value == null) continue;
        count++;
        sum += value;
      }
      if (count == 0) return null;
      return sum / count;
    }

    return SleepStats._(
      nights: ordered,
      averageSleep: averageOf(sleepValues),
      sleepNights: sleepValues.length,
      averageTimeInBed: averageOf(
        ordered.map((NightSummary n) => n.timeInBed),
      ),
      averageDeep: averageOf(ordered.map((NightSummary n) => n.deep)),
      deepNights: countOf(ordered.map((NightSummary n) => n.deep)),
      averageRem: averageOf(ordered.map((NightSummary n) => n.rem)),
      remNights: countOf(ordered.map((NightSummary n) => n.rem)),
      averageLight: averageOf(ordered.map((NightSummary n) => n.light)),
      lightNights: countOf(ordered.map((NightSummary n) => n.light)),
      averageAwake: averageOf(ordered.map((NightSummary n) => n.awake)),
      awakeNights: countOf(ordered.map((NightSummary n) => n.awake)),
      distributionNights: full.length,
      distributionSleep: distributionSleep,
      distributionDeep: distributionDeep,
      distributionRem: distributionRem,
      distributionLight: distributionLight,
      distributionDeepShare: scaledShare(
        distributionDeep,
        distributionSleep,
      ),
      distributionRemShare: scaledShare(
        distributionRem,
        distributionSleep,
      ),
      distributionLightShare: scaledShare(
        distributionLight,
        distributionSleep,
      ),
      averageAwakeShare: averageShare(
        ordered,
        (NightSummary n) => n.shareOfTimeInBed(SleepStage.awake),
      ),
      clockNights: clock.length,
      longestSleep: longest,
      longestSleepDate: longestDate,
      sleepStdDevMinutes: _sampleStdDev(sleepMinutes),
      bedtime: ClockStats.from(bedtimes),
      wake: ClockStats.from(wakes),
    );
  }
}

/// A single historical slice for a stacked stage chart.
class StageBucket {
  const StageBucket({
    required this.start,
    required this.end,
    required this.nights,
    required this.deep,
    required this.rem,
    required this.light,
  });

  final DateTime start;
  final DateTime end;
  final int nights;

  /// Mean nightly minutes for each stage across the nights in the bucket that
  /// actually reported it. Null when no night did.
  final Duration? deep;
  final Duration? rem;
  final Duration? light;

  bool get hasAny => deep != null || rem != null || light != null;
}

/// How a set of nights is compared with the previous window.
class SleepComparison {
  const SleepComparison({
    required this.range,
    required this.current,
    required this.previous,
  });

  final SleepRange range;
  final SleepStats current;
  final SleepStats previous;

  /// A comparison is stated only when both windows have enough nights to make
  /// one. Two nights against two nights is a coincidence, not a comparison.
  bool get hasEnoughData =>
      range.comparable &&
      current.nightCount >= SleepAnalytics.minNightsForComparison &&
      previous.nightCount >= SleepAnalytics.minNightsForComparison;
}

/// The arithmetic behind the homepage rings and the Insights dashboard.
abstract final class SleepAnalytics {
  /// Fewer than this many nights in either window: no comparison, no trend.
  static const int minNightsForComparison = 3;

  /// A session shorter than this is a nap, not a night, for bedtime and
  /// wake-up statistics. Main-sleep selection already prefers the longest
  /// session on a date, so this only excludes dates that hold nothing but a nap.
  static const Duration minClockSession = Duration(minutes: 90);

  /// A main session at least this long counts as a night even when it does not
  /// run through the small hours, so a shifted sleep schedule still has a
  /// bedtime and a wake-up. Shorter daytime naps stay out of clock statistics.
  static const Duration longSleepSession = Duration(hours: 4);

  /// Sessions longer than this are treated as malformed rather than as sleep.
  static const Duration maxPlausibleSession = Duration(hours: 24);

  /// Canonical nights, newest first.
  ///
  /// Resolution order:
  /// 1. drop sessions with no duration, an end before their start, or an
  ///    implausible length;
  /// 2. drop exact duplicates (same start, end and source);
  /// 3. collapse overlapping reports to one session, preferring the record with
  ///    a stage breakdown and then the longer window;
  /// 4. group the survivors by the morning they end on and sum them.
  static List<NightSummary> canonicalNights(List<StrandSleep> records) {
    final List<StrandSleep> valid = <StrandSleep>[];
    final Set<String> fingerprints = <String>{};
    for (final StrandSleep record in records) {
      final Duration window = record.window;
      if (window <= Duration.zero) continue;
      if (window > maxPlausibleSession) continue;
      if (!fingerprints.add(record.fingerprint)) continue;
      valid.add(record);
    }

    valid.sort((StrandSleep a, StrandSleep b) {
      final int byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return a.id.compareTo(b.id);
    });

    final List<StrandSleep> kept = <StrandSleep>[];
    int index = 0;
    while (index < valid.length) {
      final List<StrandSleep> cluster = <StrandSleep>[valid[index]];
      DateTime clusterEnd = valid[index].end;
      int next = index + 1;
      while (next < valid.length && valid[next].start.isBefore(clusterEnd)) {
        cluster.add(valid[next]);
        if (valid[next].end.isAfter(clusterEnd)) clusterEnd = valid[next].end;
        next++;
      }
      cluster.sort(_bestReportFirst);
      kept.add(cluster.first);
      index = next;
    }

    final Map<DateTime, List<StrandSleep>> byNight =
        <DateTime, List<StrandSleep>>{};
    for (final StrandSleep record in kept) {
      byNight.putIfAbsent(record.night, () => <StrandSleep>[]).add(record);
    }

    final List<NightSummary> nights = byNight.entries
        .map(
          (MapEntry<DateTime, List<StrandSleep>> entry) =>
              _summarise(entry.key, entry.value),
        )
        .toList()
      ..sort((NightSummary a, NightSummary b) => b.date.compareTo(a.date));
    return nights;
  }

  /// The latest completed night in an already canonical list.
  static NightSummary? latestNight(List<StrandSleep> records) {
    final List<NightSummary> nights = canonicalNights(records);
    return nights.isEmpty ? null : nights.first;
  }

  /// The nights inside [range], ending today.
  ///
  /// Future-dated sessions are excluded: a night that has not finished cannot
  /// contribute to an average of completed nights.
  static List<NightSummary> inRange(
    List<NightSummary> nights,
    SleepRange range, {
    DateTime? now,
  }) {
    final DateTime today = _dateOnly(now ?? DateTime.now());
    if (range == SleepRange.all) {
      return nights
          .where((NightSummary n) => !n.date.isAfter(today))
          .toList();
    }
    final DateTime start = today.subtract(Duration(days: range.days - 1));
    return nights
        .where(
          (NightSummary n) =>
              !n.date.isAfter(today) && !n.date.isBefore(start),
        )
        .toList();
  }

  /// The equally long window immediately before [range].
  static List<NightSummary> previousRange(
    List<NightSummary> nights,
    SleepRange range, {
    DateTime? now,
  }) {
    if (!range.comparable) return const <NightSummary>[];
    final DateTime today = _dateOnly(now ?? DateTime.now());
    final DateTime currentStart = today.subtract(
      Duration(days: range.days - 1),
    );
    final DateTime previousEnd = currentStart.subtract(const Duration(days: 1));
    final DateTime previousStart = previousEnd.subtract(
      Duration(days: range.days - 1),
    );
    return nights
        .where(
          (NightSummary n) =>
              !n.date.isAfter(previousEnd) && !n.date.isBefore(previousStart),
        )
        .toList();
  }

  /// Builds a comparison for the selected window.
  static SleepComparison compare(
    List<NightSummary> allNights,
    SleepRange range, {
    DateTime? now,
  }) {
    return SleepComparison(
      range: range,
      current: SleepStats.of(inRange(allNights, range, now: now)),
      previous: SleepStats.of(previousRange(allNights, range, now: now)),
    );
  }

  /// Nights grouped into at most [maxBuckets] consecutive slices for a stage
  /// chart. With 90 nights on a phone, one bar per night is 3 pixels wide; a
  /// bucket is an honest average rather than an unreadable smear.
  static List<StageBucket> stageBuckets(
    List<NightSummary> nights, {
    int maxBuckets = 26,
  }) {
    if (nights.isEmpty) return const <StageBucket>[];
    final List<NightSummary> ordered = List<NightSummary>.of(nights)
      ..sort((NightSummary a, NightSummary b) => a.date.compareTo(b.date));
    final int size = (ordered.length / maxBuckets).ceil().clamp(1, ordered.length);
    final List<StageBucket> buckets = <StageBucket>[];
    for (int i = 0; i < ordered.length; i += size) {
      final List<NightSummary> slice = ordered.sublist(
        i,
        math.min(i + size, ordered.length),
      );
      Duration? mean(Duration? Function(NightSummary) pick) {
        int count = 0;
        int millis = 0;
        for (final NightSummary n in slice) {
          final Duration? value = pick(n);
          if (value == null) continue;
          count++;
          millis += value.inMilliseconds;
        }
        if (count == 0) return null;
        return Duration(milliseconds: millis ~/ count);
      }

      buckets.add(
        StageBucket(
          start: slice.first.date,
          end: slice.last.date,
          nights: slice.length,
          deep: mean((NightSummary n) => n.deep),
          rem: mean((NightSummary n) => n.rem),
          light: mean((NightSummary n) => n.light),
        ),
      );
    }
    return buckets;
  }

  /// Observations that the data actually supports.
  ///
  /// Every sentence below is guarded by the figure it talks about. Nothing is
  /// generated from a missing stage, and no statement is made about health:
  /// these describe duration and regularity, which is what was measured.
  static List<String> observations(
    SleepStats current,
    SleepStats previous,
    SleepRange range,
  ) {
    final List<String> out = <String>[];
    if (current.isSparse) return out;

    final bool canCompare =
        range.comparable &&
        previous.nightCount >= minNightsForComparison;

    // 1. Average total sleep, against the previous window when there is one.
    final Duration? sleep = current.averageSleep;
    if (sleep != null) {
      final Duration? before = canCompare ? previous.averageSleep : null;
      if (before != null) {
        final Duration delta = sleep - before;
        if (delta.abs() < const Duration(minutes: 5)) {
          out.add(
            'Average sleep is about the same as the previous '
            '${range.days} days.',
          );
        } else {
          out.add(
            'Average sleep is ${formatDuration(delta.abs())} '
            '${delta.isNegative ? 'shorter' : 'longer'} than the previous '
            '${range.days} days.',
          );
        }
      } else {
        out.add(
          'Average sleep across ${current.sleepNights} '
          '${current.sleepNights == 1 ? 'night' : 'nights'} is '
          '${formatDuration(sleep)}.',
        );
      }
    }

    // 2. Bedtime regularity.
    final double? bedSpread = current.bedtime.spreadMinutes;
    if (bedSpread != null && current.bedtime.count >= 3) {
      final double? before = canCompare
          ? previous.bedtime.spreadMinutes
          : null;
      if (before != null && (bedSpread - before).abs() >= 10) {
        out.add(
          'Bedtimes are ${bedSpread < before ? 'more' : 'less'} consistent '
          'than the previous ${range.days} days '
          '(±${bedSpread.round()} min, previously ±${before.round()} min).',
        );
      } else {
        out.add(
          'Bedtime varied by about ±${bedSpread.round()} minutes across '
          '${current.bedtime.count} nights.',
        );
      }
    }

    // 3. REM, only when both windows measured it.
    final Duration? rem = current.averageRem;
    final Duration? remBefore = canCompare ? previous.averageRem : null;
    if (rem != null && remBefore != null) {
      final Duration delta = rem - remBefore;
      if (delta.abs() >= const Duration(minutes: 5)) {
        out.add(
          'Average REM sleep is ${formatDuration(delta.abs())} '
          '${delta.isNegative ? 'shorter' : 'longer'} than the previous '
          '${range.days} days.',
        );
      }
    }

    // 4. Wake-up regularity.
    final double? wakeSpread = current.wake.spreadMinutes;
    final double? wakeBefore = canCompare ? previous.wake.spreadMinutes : null;
    if (wakeSpread != null &&
        wakeBefore != null &&
        current.wake.count >= 3 &&
        (wakeSpread - wakeBefore).abs() >= 10) {
      out.add(
        'Wake-up times are ${wakeSpread < wakeBefore ? 'less' : 'more'} '
        'variable than the previous ${range.days} days '
        '(±${wakeSpread.round()} min, previously ±${wakeBefore.round()} min).',
      );
    }

    // 5. The longest night in the window, which needs no comparison at all.
    if (current.longestSleep != null && current.longestSleepDate != null) {
      out.add(
        'The longest sleep in this period was '
        '${formatDuration(current.longestSleep!)} on '
        '${formatSleepDate(current.longestSleepDate!)}.',
      );
    }

    // 6. Night-to-night duration stability, when the previous window allows a
    //    statement about change.
    final double? spread = current.sleepStdDevMinutes;
    final double? spreadBefore = canCompare
        ? previous.sleepStdDevMinutes
        : null;
    if (spread != null &&
        spreadBefore != null &&
        current.sleepNights >= 3 &&
        (spread - spreadBefore).abs() >= 10) {
      out.add(
        'Nightly sleep duration is ${spread < spreadBefore ? 'steadier' : 'more variable'} '
        'than the previous ${range.days} days '
        '(±${spread.round()} min, previously ±${spreadBefore.round()} min).',
      );
    }

    return out.take(5).toList();
  }

  /// The first and last date of a window, for a caption.
  static String rangeCaption(
    List<NightSummary> nights,
    SleepRange range,
  ) {
    if (nights.isEmpty) return range.label;
    final List<NightSummary> ordered = List<NightSummary>.of(nights)
      ..sort((NightSummary a, NightSummary b) => a.date.compareTo(b.date));
    final DateTime first = ordered.first.date;
    final DateTime last = ordered.last.date;
    if (first == last) return formatSleepDateShort(first);
    return '${formatShortDate(first)} – ${formatShortDate(last)}';
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Sort helper: the report of a session most worth keeping.
int _bestReportFirst(StrandSleep a, StrandSleep b) {
  if (a.hasStageFigures != b.hasStageFigures) {
    return a.hasStageFigures ? -1 : 1;
  }
  final int byWindow = b.window.compareTo(a.window);
  if (byWindow != 0) return byWindow;
  return a.id.compareTo(b.id);
}

/// Sums the sessions filed under one night date.
NightSummary _summarise(DateTime date, List<StrandSleep> sessions) {
  final List<StrandSleep> ordered = List<StrandSleep>.of(sessions)
    ..sort((StrandSleep a, StrandSleep b) => a.start.compareTo(b.start));

  DateTime start = ordered.first.start;
  DateTime end = ordered.first.end;
  Duration timeInBed = Duration.zero;
  for (final StrandSleep session in ordered) {
    timeInBed += session.window;
    if (session.start.isBefore(start)) start = session.start;
    if (session.end.isAfter(end)) end = session.end;
  }

  // The main session decides bedtime and wake-up. The longest window is the
  // night's real sleep; a shorter nap on the same date is not.
  final List<StrandSleep> byLength = List<StrandSleep>.of(ordered)
    ..sort((StrandSleep a, StrandSleep b) {
      final int byWindow = b.window.compareTo(a.window);
      if (byWindow != 0) return byWindow;
      return a.start.compareTo(b.start);
    });
  final StrandSleep main = byLength.first;

  final bool allFigures = ordered.every(
    (StrandSleep s) => s.hasStageFigures,
  );

  Duration? sumStage(SleepStage stage) {
    if (!allFigures) return null;
    Duration sum = Duration.zero;
    for (final StrandSleep session in ordered) {
      final Duration? value = session.timeByStage[stage];
      // A stage one contributing session never reported is unavailable for the
      // night, not zero for it.
      if (value == null) return null;
      sum += value;
    }
    return sum;
  }

  Duration? sumOf(Duration? Function(StrandSleep) pick) {
    Duration sum = Duration.zero;
    for (final StrandSleep session in ordered) {
      final Duration? value = pick(session);
      if (value == null) return null;
      sum += value;
    }
    return sum;
  }

  return NightSummary(
    date: date,
    start: start,
    end: end,
    mainStart: main.start,
    mainEnd: main.end,
    timeInBed: timeInBed,
    asleep: sumOf((StrandSleep s) => s.asleepTotal),
    deep: sumStage(SleepStage.deep),
    rem: sumStage(SleepStage.rem),
    light: sumStage(SleepStage.light),
    awake: sumOf((StrandSleep s) => s.awakeTotal),
    hasStageFigures: allFigures,
    sessionCount: ordered.length,
    spans: <SleepStageSpan>[
      for (final StrandSleep s in ordered) ...s.stages,
    ],
    metrics: main.metrics,
  );
}

/// Sample standard deviation (n−1), in the same unit as the input. Null for
/// fewer than two values, because one value has no spread to report.
double? _sampleStdDev(List<double> values) {
  if (values.length < 2) return null;
  final double mean = values.reduce((double a, double b) => a + b) / values.length;
  double sum = 0;
  for (final double value in values) {
    final double diff = value - mean;
    sum += diff * diff;
  }
  return math.sqrt(sum / (values.length - 1));
}
