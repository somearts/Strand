/// What Strand holds about one night's sleep.
///
/// Everything above this file — the store, the repository, the controller, every
/// screen — speaks in terms of this model and cannot name a Health Connect type.
/// That separation is the point: a platform record is awkward, versioned, and
/// occasionally wrong, and none of those qualities should reach a widget.
///
/// ## Times are naive local, and that is deliberate
///
/// Every [DateTime] here is local wall-clock with no zone attached. The platform
/// hands Strand instants, the store persists them as UTC, and
/// [StrandSleep.fromJson] converts on the way back in — so nothing above this
/// file ever holds a UTC-flagged value whose `.hour` answers for Greenwich
/// instead of for where the person slept.
///
/// `test/timezone_test.dart` proves that under forced zones, including the
/// midnight-crossing case where reading the wrong zone files a night under the
/// wrong calendar day.
library;

/// One stage, over one stretch of the night.
///
/// A span and not a total, because a night is made of several stretches of the
/// same stage and the difference between "an hour of REM, in three pieces" and
/// "an hour of REM" is the whole of what a hypnogram draws.
class SleepStageSpan {
  const SleepStageSpan({
    required this.stage,
    required this.start,
    required this.end,
  });

  final SleepStage stage;
  final DateTime start;
  final DateTime end;

  /// How long the stage lasted. Zero or negative for a span the source sent
  /// with no width, which is not an error worth hiding but must not be drawn
  /// as if it were time.
  Duration get duration => end.difference(start);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'stage': stage.name,
    'from': start.toUtc().toIso8601String(),
    'to': end.toUtc().toIso8601String(),
  };

  static SleepStageSpan? fromJson(Map<String, dynamic> json) {
    // `.toLocal()` is not optional here, and this is the second time this class
    // has needed saying.
    //
    // [toJson] writes UTC with a trailing `Z`. `DateTime.parse` honours that `Z`
    // and returns a **UTC-flagged** DateTime — the same instant, but a different
    // kind of value. Every `.hour`, `.day` and `.month` on a UTC-flagged
    // DateTime answers for Greenwich, not for where the person slept. On a phone
    // in Asia/Calcutta a night that began at 8:30 in the morning came back
    // reporting hour 3, and Insights printed the hypnogram's axis as "2p" and
    // "3p" directly above a row that said 8:30 AM.
    //
    // Strand's model is naive local time throughout — `night` is built from
    // `end.year/month/day`, `formatClock` reads `.hour`, the chart's grid walks
    // whole hours. Converting on the way *in* is what makes that true again
    // after a restart, and costs nothing on the way out.
    final DateTime? start = DateTime.tryParse('${json['from']}')?.toLocal();
    final DateTime? end = DateTime.tryParse('${json['to']}')?.toLocal();
    final String? name = json['stage'] as String?;
    if (start == null || end == null || name == null) return null;
    for (final SleepStage stage in SleepStage.values) {
      if (stage.name == name) {
        return SleepStageSpan(stage: stage, start: start, end: end);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SleepStageSpan &&
      other.stage == stage &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(stage, start, end);

  @override
  String toString() => 'SleepStageSpan(${stage.name}, $start -> $end)';
}

/// The stages Health Connect can report.
///
/// Names are the platform's own, so a stage on screen can be found by searching
/// for what Health Connect calls it. "REM" is upper case because it is an
/// initialism and "Rem" is a word; "Unclassified" is not "Unknown", because it
/// says what actually happened — the source reported a span without saying which
/// stage it was — where "Unknown" implies Strand failed to find out.
///
/// Two of these labels are deliberately *not* the platform's wording, and the
/// reason is the same for both: the page's vocabulary is fixed, and Health
/// Connect's own names for two of its stages break it.
///
/// - [asleep] is Health Connect's "asleep, stage unspecified". It is real data
///   and it is sleep, so it gets a row — but the row cannot read "Asleep", and
///   it cannot be called plain "Sleep" either, because the card already uses
///   that word for the total. "Sleep, unspecified" keeps the mandated word and
///   still says why the row exists.
/// - [awakeInBed] and [inBed] would print the phrase "in bed", which this page
///   does not use: "Duration" and "Sleep period" already say what the session
///   is. "In session" carries the same meaning — time inside the session window
///   that was not sleep — without reintroducing the phrase.
enum SleepStage {
  awake('Awake'),
  awakeInBed('Awake in session'),
  inBed('In session'),
  light('Light'),
  deep('Deep'),
  rem('REM'),
  asleep('Sleep, unspecified'),
  outOfBed('Out of bed'),
  unknown('Unclassified');

  const SleepStage(this.label);

  /// The word a person reads.
  final String label;

  /// Whether this stage is time spent asleep.
  ///
  /// [SleepStage.asleep] is Health Connect's "asleep, stage unspecified", which
  /// is sleep. [inBed] is emphatically not: a source that reports the in-bed span
  /// usually reports it across the whole night, so counting it would double every
  /// figure on the page.
  bool get asleepLike =>
      this == SleepStage.light ||
      this == SleepStage.deep ||
      this == SleepStage.rem ||
      this == SleepStage.asleep;

  /// Whether this stage is time in bed but not asleep.
  ///
  /// [SleepStage.inBed] is excluded even though it is literally time in bed,
  /// because it normally covers the whole window and would swamp every other
  /// figure. That exclusion is the reason [awakeTotal] is a useful number at all.
  bool get awakeLike =>
      this == SleepStage.awake || this == SleepStage.awakeInBed;
}

/// Totals a source published for a session whose *intervals* it did not publish.
///
/// ## Why this type exists
///
/// [StrandSleep] derived every figure from [StrandSleep.stages], and that was
/// correct for the reader's own nights: Health Connect either sends intervals or it
/// does not, and when it does not there is genuinely nothing to derive. But a
/// *published friend night* has a second channel. A phone can send "I slept 6h 33m,
/// 95m of it deep" without sending a single interval — and Strand's own publisher
/// writes exactly that when the owner's source had no breakdown.
///
/// So a friend night rebuilt out of such a document arrived as a record with no
/// stages at all, and every getter answered null: no sleep figure, no awake figure,
/// no stage table. The friend's *card* was unaffected, because it reads the published
/// totals straight off the entry ([FriendSleepView._slices]). Insights, which reads a
/// `StrandSleep`, was. The same night therefore reported one figure on one screen
/// and a different one on another, which is the exact failure this type closes.
///
/// ## What it is not
///
/// Not a fallback for a reader's own record. Nothing sets it on one, so
/// [StrandSleep.asleepTotal] still answers null there — and *should*: a source that
/// reported a session and no breakdown has measured nothing, and showing the session
/// length under the word "Sleep" would be a claim the record cannot support.
///
/// [byStage] is a composition, not an order. There is no timeline to be had, so
/// [StrandSleep.hasStageData] stays false and nothing draws a hypnogram — a chart
/// invented out of totals would be a picture Strand made up.
class PublishedSleepTotals {
  const PublishedSleepTotals({
    this.sleep,
    this.awake,
    this.byStage = const <SleepStage, Duration>{},
  });

  /// Time asleep, as the owner measured and published it.
  ///
  /// Null when the owner published no sleep figure. The session length is *not* a
  /// substitute: [StrandSleep.asleepTotal] answers null so callers fall back to
  /// [StrandSleep.window] and say which of the two they are showing.
  final Duration? sleep;

  /// Time awake inside the night, if the owner published it.
  final Duration? awake;

  /// Per-stage totals, only the stages the owner actually reported.
  final Map<SleepStage, Duration> byStage;

  bool get isEmpty => sleep == null && awake == null && byStage.isEmpty;

  /// Whether there is anything at all to report.
  ///
  /// Null [byStage] entries are dropped rather than carried as zero, so "no deep
  /// sleep was reported" and "deep sleep was zero" stay distinguishable — the same
  /// rule [StrandSleep.timeByStage] follows.
  PublishedSleepTotals pruned() {
    if (byStage.isEmpty) return this;
    final Map<SleepStage, Duration> kept = <SleepStage, Duration>{
      for (final MapEntry<SleepStage, Duration> e in byStage.entries)
        if (e.value > Duration.zero) e.key: e.value,
    };
    if (kept.length == byStage.length) return this;
    return PublishedSleepTotals(sleep: sleep, awake: awake, byStage: kept);
  }

  @override
  bool operator ==(Object other) {
    if (other is! PublishedSleepTotals) return false;
    if (other.sleep != sleep || other.awake != awake) return false;
    if (other.byStage.length != byStage.length) return false;
    // Written out rather than delegating to `mapEquals` from
    // `package:flutter/foundation.dart`.
    //
    // **This file must stay free of Flutter.** It is the bottom of the app: the
    // store, the repository and every screen speak in terms of it. `timezone_test.dart`
    // runs it under a plain `dart` process with no Flutter engine, to check that a
    // record reads back as the wall clock of whatever zone it is run in — and a single
    // `flutter/foundation.dart` import drags in `dart:ui` and every one of those probes
    // dies with "Dart library 'dart:ui' is not available on this platform".
    for (final MapEntry<SleepStage, Duration> e in byStage.entries) {
      if (other.byStage[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    sleep,
    awake,
    Object.hashAllUnordered(
      byStage.entries.map(
        (MapEntry<SleepStage, Duration> e) => Object.hash(e.key, e.value),
      ),
    ),
  );

  @override
  String toString() =>
      'PublishedSleepTotals($sleep asleep, $awake awake, '
      '${byStage.length} stages)';

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (sleep != null) 'sleepMs': sleep!.inMilliseconds,
    if (awake != null) 'awakeMs': awake!.inMilliseconds,
    if (byStage.isNotEmpty)
      'byStage': <String, dynamic>{
        for (final MapEntry<SleepStage, Duration> e in byStage.entries)
          e.key.name: e.value.inMilliseconds,
      },
  };

  /// Reads totals back, tolerating anything unreadable.
  ///
  /// A dropped figure costs one figure. Returning null for the lot would turn a
  /// partly-written document into a night with nothing on it, which is a worse answer
  /// than the same night with one stage missing.
  static PublishedSleepTotals? fromJson(Object? json) {
    if (json is! Map) return null;
    final Map<Object?, Object?> map = json;

    Duration? positive(Object? raw) {
      final int? ms = raw is num ? raw.toInt() : null;
      if (ms == null || ms <= 0) return null;
      return Duration(milliseconds: ms);
    }

    Duration? named(String key) => positive(map[key]);

    final Map<SleepStage, Duration> byStage = <SleepStage, Duration>{};
    final Object? stages = map['byStage'];
    if (stages is Map) {
      for (final SleepStage stage in SleepStage.values) {
        final Duration? value = positive(stages[stage.name]);
        if (value != null) byStage[stage] = value;
      }
    }

    final PublishedSleepTotals totals = PublishedSleepTotals(
      sleep: named('sleepMs'),
      awake: named('awakeMs'),
      byStage: byStage,
    );
    return totals.isEmpty ? null : totals.pruned();
  }
}

/// Overnight body metrics read from Health Connect for one night.
///
/// Every field is nullable: null means the source did not supply that metric
/// for this night, and the UI shows "Not recorded" rather than a zero.
class NightMetrics {
  const NightMetrics({
    this.heartRateBuckets = const <HeartRateBucket>[],
    this.lowestHeartRate,
    this.averageHeartRate,
    this.restingHeartRate,
    this.hrvAverage,
    this.oxygenSaturationAverage,
    this.oxygenSaturationLowest,
    this.respiratoryRateAverage,
    this.respiratoryRateMin,
    this.respiratoryRateMax,
    this.hasHeartRate = false,
    this.hasRestingHeartRate = false,
    this.hasHrv = false,
    this.hasOxygenSaturation = false,
    this.hasRespiratoryRate = false,
  });

  /// 5-minute buckets of heart rate across the night.
  final List<HeartRateBucket> heartRateBuckets;
  final double? lowestHeartRate;
  final double? averageHeartRate;
  final double? restingHeartRate;
  final double? hrvAverage;
  final double? oxygenSaturationAverage;
  final double? oxygenSaturationLowest;
  final double? respiratoryRateAverage;
  final double? respiratoryRateMin;
  final double? respiratoryRateMax;

  final bool hasHeartRate;
  final bool hasRestingHeartRate;
  final bool hasHrv;
  final bool hasOxygenSaturation;
  final bool hasRespiratoryRate;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (heartRateBuckets.isNotEmpty)
      'hrBuckets': heartRateBuckets.map((HeartRateBucket b) => b.toJson()).toList(),
    if (lowestHeartRate != null) 'hrLow': lowestHeartRate,
    if (averageHeartRate != null) 'hrAvg': averageHeartRate,
    if (restingHeartRate != null) 'rhr': restingHeartRate,
    if (hrvAverage != null) 'hrv': hrvAverage,
    if (oxygenSaturationAverage != null) 'spo2Avg': oxygenSaturationAverage,
    if (oxygenSaturationLowest != null) 'spo2Low': oxygenSaturationLowest,
    if (respiratoryRateAverage != null) 'rrAvg': respiratoryRateAverage,
    if (respiratoryRateMin != null) 'rrMin': respiratoryRateMin,
    if (respiratoryRateMax != null) 'rrMax': respiratoryRateMax,
    'hasHr': hasHeartRate,
    'hasRhr': hasRestingHeartRate,
    'hasHrv': hasHrv,
    'hasSpo2': hasOxygenSaturation,
    'hasRr': hasRespiratoryRate,
  };

  static NightMetrics? fromJson(Object? json) {
    if (json is! Map) return null;
    final Map<Object?, Object?> map = json;
    final List<HeartRateBucket> buckets = <HeartRateBucket>[];
    final Object? rawBuckets = map['hrBuckets'];
    if (rawBuckets is List) {
      for (final Object? item in rawBuckets) {
        if (item is Map) {
          final HeartRateBucket? b = HeartRateBucket.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (b != null) buckets.add(b);
        }
      }
    }
    double? d(String key) {
      final Object? v = map[key];
      return v is num ? v.toDouble() : null;
    }

    final NightMetrics m = NightMetrics(
      heartRateBuckets: buckets,
      lowestHeartRate: d('hrLow'),
      averageHeartRate: d('hrAvg'),
      restingHeartRate: d('rhr'),
      hrvAverage: d('hrv'),
      oxygenSaturationAverage: d('spo2Avg'),
      oxygenSaturationLowest: d('spo2Low'),
      respiratoryRateAverage: d('rrAvg'),
      respiratoryRateMin: d('rrMin'),
      respiratoryRateMax: d('rrMax'),
      hasHeartRate: map['hasHr'] == true,
      hasRestingHeartRate: map['hasRhr'] == true,
      hasHrv: map['hasHrv'] == true,
      hasOxygenSaturation: map['hasSpo2'] == true,
      hasRespiratoryRate: map['hasRr'] == true,
    );
    // Treat as null if nothing was supplied.
    if (!m.hasHeartRate &&
        !m.hasRestingHeartRate &&
        !m.hasHrv &&
        !m.hasOxygenSaturation &&
        !m.hasRespiratoryRate &&
        buckets.isEmpty) {
      return null;
    }
    return m;
  }
}

class HeartRateBucket {
  const HeartRateBucket({
    required this.start,
    required this.min,
    required this.avg,
    required this.max,
  });

  final DateTime start;
  final double min;
  final double avg;
  final double max;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'from': start.toUtc().toIso8601String(),
    'min': min,
    'avg': avg,
    'max': max,
  };

  static HeartRateBucket? fromJson(Map<String, dynamic> json) {
    final DateTime? start = DateTime.tryParse('${json['from']}')?.toLocal();
    final Object? min = json['min'];
    final Object? avg = json['avg'];
    final Object? max = json['max'];
    if (start == null || min is! num || avg is! num || max is! num) {
      return null;
    }
    return HeartRateBucket(
      start: start,
      min: min.toDouble(),
      avg: avg.toDouble(),
      max: max.toDouble(),
    );
  }
}

/// One session, with the stages inside it.
///
/// Immutable, and built twice: once by the repository from a source's raw records
/// and once by [fromJson] from the store. The second build must produce exactly
/// what the first did, which is what [fingerprint] is for and what
/// `test/timezone_test.dart` checks under a forced zone.
class StrandSleep {
  const StrandSleep({
    required this.id,
    required this.start,
    required this.end,
    required this.sourcePackage,
    this.sourceName = '',
    this.deviceId,
    this.stages = const <SleepStageSpan>[],
    this.published,
    this.metrics,
    this.importedAt,
  });

  /// The source record's own id. Also the join key for its stages, and what makes
  /// a second sync replace a record instead of duplicating it.
  final String id;

  final DateTime start;
  final DateTime end;

  /// The writing app's package name — the only origin Health Connect gives for a
  /// sleep record, since the plugin leaves `source_id` empty.
  final String sourcePackage;

  /// The source's display name, when it gave one. Usually empty.
  final String sourceName;

  final String? deviceId;

  /// The stages, as reported. May be empty: plenty of sources record a session
  /// and no breakdown, and that is a real state rather than a failure.
  final List<SleepStageSpan> stages;

  /// Totals the source published for this session without publishing intervals.
  ///
  /// Null on every record of the reader's own, and that is not an oversight: their
  /// source has one channel, and when it sends no intervals there is nothing to
  /// report. It is set only on a friend's night rebuilt from a published document
  /// that carried figures but no timeline — see [PublishedSleepTotals] for why, and
  /// for why a night like that is still not a night Strand will draw a chart for.
  final PublishedSleepTotals? published;
  final NightMetrics? metrics;

  /// When Strand first saw this record, kept for provenance and deliberately
  /// excluded from [fingerprint].
  final DateTime? importedAt;

  /// The length of the session: falling asleep to waking.
  ///
  /// Health Connect's session interval, which normally includes stretches of
  /// simply lying in bed without sleeping. It is emphatically *not* "time asleep"
  /// and the two must never be shown under the same word — which is why the
  /// screen calls this "Session duration" and never "In bed".
  Duration get window => end.difference(start);

  /// Whether this night has any stage detail at all.
  ///
  /// **Intervals, specifically** — not "any stage figure". A session that published
  /// per-stage totals but no intervals has a composition and no timeline, and every
  /// caller of this means "is there a sequence to draw": the ribbon, the hypnogram,
  /// and whether the source said anything about a breakdown.
  bool get hasStageData => stages.isNotEmpty;

  /// Whether this record can name any stage durations at all.
  ///
  /// Weaker than [hasStageData] and used only where a *composition* is wanted — the
  /// stage table, and the percentages beside it. A friend night with published
  /// totals and no intervals answers true here and false above, and that is the
  /// honest shape of the data: the numbers exist, the order does not.
  bool get hasStageFigures => timeByStage.isNotEmpty;

  /// Every distinct span, in the order first seen.
  ///
  /// The dedupe is a backstop. The Health Connect reader removes its own
  /// duplication as it reads — the plugin returns each stage once *per requested
  /// type*, which multiplied every duration on the page by eight — but the model
  /// must not depend on that having happened. A repeated span would make
  /// [asleepTotal] report a night as longer than anyone can sleep in.
  ///
  /// "Distinct" is stage plus exact boundaries. Health Connect does not split a
  /// session into two genuinely identical adjacent spans, so two spans agreeing on
  /// all three fields are the same fact reported twice, not two facts.
  List<SleepStageSpan> get distinctStages {
    final Set<SleepStageSpan> seen = <SleepStageSpan>{};
    return <SleepStageSpan>[
      for (final SleepStageSpan span in stages)
        if (seen.add(span)) span,
    ];
  }

  /// Total time genuinely asleep, or null when the source reported nothing.
  ///
  /// Null is the honest answer when there is neither an interval nor a published
  /// figure, and it is why [window] must not be shown in its place. Returning the
  /// window would report eight hours of sleep for a night with three wake-ups in it.
  ///
  /// **Intervals first, published totals second.** The same order the friend's own
  /// card uses, and deliberately so: a document carrying both must not report two
  /// different sleep figures for one night, and the finer measurement is the one to
  /// believe when they disagree.
  Duration? get asleepTotal {
    if (stages.isEmpty) return published?.sleep;
    Duration sum = Duration.zero;
    for (final SleepStageSpan span in distinctStages) {
      if (span.stage.asleepLike) sum += span.duration;
    }
    return sum;
  }

  /// Time awake inside the night, or null when the source reported nothing.
  ///
  /// Counts [SleepStage.awakeLike] only. The in-bed span is excluded because it
  /// normally covers the whole window and would swamp everything else.
  ///
  /// Intervals first for the same reason [asleepTotal] prefers them.
  Duration? get awakeTotal {
    if (stages.isEmpty) return published?.awake;
    Duration sum = Duration.zero;
    for (final SleepStageSpan span in distinctStages) {
      if (span.stage.awakeLike) sum += span.duration;
    }
    return sum;
  }

  /// Time spent in each stage, summed across the night.
  ///
  /// Only stages the source actually sent appear. A map is used rather than a
  /// full table so "no deep sleep was reported" and "deep sleep was zero" stay
  /// distinguishable.
  Map<SleepStage, Duration> get timeByStage {
    if (stages.isEmpty)
      return published?.byStage ?? const <SleepStage, Duration>{};
    final Map<SleepStage, Duration> out = <SleepStage, Duration>{};
    for (final SleepStageSpan span in distinctStages) {
      out[span.stage] = (out[span.stage] ?? Duration.zero) + span.duration;
    }
    return out;
  }

  /// The total length of every distinct stage span, sleep or not.
  ///
  /// This is *not* the window. A source may report stages for part of a night and
  /// nothing for the rest, and this is how much of the night was actually
  /// described. [stageCoverage] turns it into something a person can read.
  Duration get stagesTotal {
    Duration sum = Duration.zero;
    for (final SleepStageSpan span in distinctStages) {
      sum += span.duration;
    }
    return sum;
  }

  /// How much of [window] the stage data actually describes.
  ///
  /// Null when there are no stages at all, because "nothing was measured" is not
  /// zero coverage — it is the absence of an answer.
  ///
  /// This exists because a night whose stages cover only part of the window is
  /// the case that makes figures quietly wrong. Health Connect's session interval
  /// runs from falling asleep to waking and usually includes stretches of simply
  /// lying in bed, while a wearable's stage records frequently stop earlier than
  /// the session does. Dividing a stage duration by the whole window then makes a
  /// stage look like a small share of a long night when the truth is "we stopped
  /// measuring", and it makes an efficiency figure charge the unmeasured remainder
  /// to the person as awake time. Anything that divides by the night has to know
  /// which of those two it is looking at.
  Duration? get stageCoverage => stages.isEmpty ? null : stagesTotal;

  /// Whether the stage data covers the whole session.
  ///
  /// False for the reason described on [stageCoverage]: a source that reports
  /// stages for part of a night has not measured all of it, and a page must not
  /// present a per-stage share of the whole window as though it were a
  /// measurement of the whole night.
  bool get stagesCoverWholeNight {
    final Duration? covered = stageCoverage;
    if (covered == null) return false;
    // A small tolerance. A source whose stages total within a couple of minutes
    // of the session has described the whole of it, and rounding across a
    // handful of boundaries should not flip the answer.
    const Duration tolerance = Duration(minutes: 2);
    return covered >= window - tolerance && covered <= window + tolerance;
  }

  /// The stages present, in the order Insights lists them.
  ///
  /// A fixed order — deep, rem, light, then the rest — so two nights drawn from
  /// the same source line up, which is most of what makes a history readable.
  ///
  /// Keyed off [timeByStage] rather than off [stages], so a friend night that
  /// published per-stage totals and no intervals lists the stages it published.
  /// That is what makes the stage table agree with the friend's own card: both list
  /// the same stages, out of the same numbers.
  ///
  /// [timeByStage] already dedupes — via [distinctStages] when there are spans — so a
  /// night handed to the model with repeated spans still lists each stage once.
  List<SleepStage> get stagesPresent {
    final Set<SleepStage> seen = timeByStage.keys.toSet();
    return <SleepStage>[
      for (final SleepStage s in <SleepStage>[
        SleepStage.deep,
        SleepStage.rem,
        SleepStage.light,
        SleepStage.asleep,
        SleepStage.awake,
        SleepStage.awakeInBed,
        SleepStage.outOfBed,
        SleepStage.inBed,
        SleepStage.unknown,
      ])
        if (seen.contains(s)) s,
    ];
  }

  /// The night this record belongs to, as a local date.
  ///
  /// Taken from the *end* of the session, because a night is named after the
  /// morning it ends on. A session that starts at 11pm and ends at 7am is the
  /// 7am morning's night, and calling it the previous day would put every
  /// record in the wrong column next to its neighbour.
  DateTime get night => DateTime(end.year, end.month, end.day);

  /// Whether anything about this record would change what the page shows.
  ///
  /// Deliberately excludes [importedAt] and [id]: re-reading an unchanged night
  /// must produce the same fingerprint, or every sync would rewrite every record
  /// and the store would churn for no reason.
  ///
  /// [published] is excluded for the same reason, and on top of it because a figure
  /// is not a measurement: it restates what the intervals already say. Were it in the
  /// fingerprint, the same night arriving once with totals and once without would
  /// occupy two places in the history.
  String get fingerprint {
    final StringBuffer buffer = StringBuffer()
      ..write(start.toUtc().toIso8601String())
      ..write('|')
      ..write(end.toUtc().toIso8601String())
      ..write('|')
      ..write(sourcePackage);
    for (final SleepStageSpan span in distinctStages) {
      buffer
        ..write('|')
        ..write(span.stage.name)
        ..write(':')
        ..write(span.start.toUtc().toIso8601String())
        ..write('-')
        ..write(span.end.toUtc().toIso8601String());
    }
    return buffer.toString();
  }

  /// The same record with its stages attached.
  StrandSleep withStages(List<SleepStageSpan> next) => StrandSleep(
    id: id,
    start: start,
    end: end,
    sourcePackage: sourcePackage,
    sourceName: sourceName,
    deviceId: deviceId,
    stages: next,
    published: published,
    importedAt: importedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    'sourcePackage': sourcePackage,
    'sourceName': sourceName,
    'deviceId': deviceId,
    'stages': stages.map((SleepStageSpan s) => s.toJson()).toList(),
    // Carried so a totals-only record survives a round trip through the store. It is
    // not something Strand ever writes locally — a friend's night is rebuilt from
    // their published document every time — but a record that loses its figures on
    // the way to disk and finds them gone on the way back is a record that changes
    // its own answer depending on where it was read from.
    if (published != null) 'published': published!.toJson(),
    if (metrics != null) 'metrics': metrics!.toJson(),
    'at': importedAt?.toUtc().toIso8601String(),
  };

  /// Rebuilds a record from the store.
  ///
  /// Returns null for a record Strand cannot honestly hold — no id, no times, or
  /// an end before its start — rather than repairing it. A record with a guessed
  /// end time is worse than a missing one, because it would occupy a place in
  /// the history that no real night did.
  static StrandSleep? fromJson(Map<String, dynamic> json) {
    final String? id = json['id'] as String?;
    // `.toLocal()` for the same reason as `SleepStageSpan.fromJson`, and it
    // matters more here: this is where `night` — the date a record is filed
    // under, and therefore whether it collides with its neighbour — is decided.
    // A UTC-flagged `end` can report the previous calendar day, which files a
    // night under the wrong date in the history list.
    final DateTime? start = DateTime.tryParse('${json['start']}')?.toLocal();
    final DateTime? end = DateTime.tryParse('${json['end']}')?.toLocal();
    if (id == null || id.isEmpty || start == null || end == null) return null;
    if (end.isBefore(start)) return null;

    final List<SleepStageSpan> spans = <SleepStageSpan>[];
    final Object? raw = json['stages'];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is Map) {
          final SleepStageSpan? span = SleepStageSpan.fromJson(
            Map<String, dynamic>.from(item),
          );
          // A bad span is dropped, the night is kept. Stage detail is additive:
          // losing one interval still leaves a real record worth showing, and
          // losing the whole night would hide a night that genuinely happened.
          if (span != null) spans.add(span);
        }
      }
    }

    final Object? device = json['deviceId'];
    return StrandSleep(
      id: id,
      start: start,
      end: end,
      sourcePackage: '${json['sourcePackage'] ?? ''}',
      sourceName: '${json['sourceName'] ?? ''}',
      deviceId: device is String && device.isNotEmpty ? device : null,
      stages: spans,
      published: PublishedSleepTotals.fromJson(json['published']),
      metrics: NightMetrics.fromJson(json['metrics']),
      importedAt: DateTime.tryParse('${json['at'] ?? ''}')?.toLocal(),
    );
  }

  /// Newest first, the order the Insights page draws.
  ///
  /// Sorted on the session's **start**, because that is the record's real
  /// position in time and the thing a person is scanning for. Sorting on the end
  /// looks equivalent and is not: a long night that began at 22:00 and a short nap
  /// that began at 14:00 the next day are ordered the same way by either, but an
  /// evening nap followed by a night's sleep is not, and the nap is what happened
  /// last.
  ///
  /// The `id` tie-break matters more than it looks: two sessions can begin in the
  /// same minute, and an unstable order would shuffle the list between launches.
  static int compareNewestFirst(StrandSleep a, StrandSleep b) {
    final int byStart = b.start.compareTo(a.start);
    if (byStart != 0) return byStart;
    final int byEnd = b.end.compareTo(a.end);
    if (byEnd != 0) return byEnd;
    return a.id.compareTo(b.id);
  }

  @override
  String toString() =>
      'StrandSleep($id, $start -> $end, ${stages.length} stages)';
}
