import '../health/analytics/sleep_analytics.dart';
import '../health/strand_sleep.dart';

class SharedNight {
  const SharedNight({
    required this.date,
    required this.start,
    required this.end,
    required this.bedMinutes,
    required this.wakeMinutes,
    required this.timeInBed,
    required this.hasStageFigures,
    required this.sessionCount,
    this.asleep,
    this.deep,
    this.rem,
    this.light,
    this.awake,
    this.spans = const <SleepStageSpan>[],
    this.metrics,
  });

  final DateTime date;
  final DateTime start;
  final DateTime end;
  final int bedMinutes;
  final int wakeMinutes;
  final Duration timeInBed;
  final Duration? asleep;
  final Duration? deep;
  final Duration? rem;
  final Duration? light;
  final Duration? awake;
  final bool hasStageFigures;
  final int sessionCount;
  final List<SleepStageSpan> spans;
  final NightMetrics? metrics;

  String get dateKey =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  factory SharedNight.fromSummary(NightSummary n) => SharedNight(
        date: n.date,
        start: n.start,
        end: n.end,
        bedMinutes: n.mainStart.hour * 60 + n.mainStart.minute,
        wakeMinutes: n.mainEnd.hour * 60 + n.mainEnd.minute,
        timeInBed: n.timeInBed,
        asleep: n.asleep,
        deep: n.deep,
        rem: n.rem,
        light: n.light,
        awake: n.awake,
        hasStageFigures: n.hasStageFigures,
        sessionCount: n.sessionCount,
        spans: n.spans,
        metrics: n.metrics,
      );

  factory SharedNight.fromMap(Map<String, dynamic> map) {
    final DateTime date = DateTime.parse(map['date'] as String);
    int? ms(String key) => (map[key] as num?)?.toInt();
    Duration? dur(String key) {
      final int? value = ms(key);
      return value == null ? null : Duration(milliseconds: value);
    }

    final List<SleepStageSpan> spans = <SleepStageSpan>[];
    final Object? rawSpans = map['spans'];
    if (rawSpans is List) {
      for (final Object? item in rawSpans) {
        if (item is Map) {
          final SleepStageSpan? s = SleepStageSpan.fromJson(Map<String, dynamic>.from(item));
          if (s != null) spans.add(s);
        }
      }
    }

    return SharedNight(
      date: DateTime(date.year, date.month, date.day),
      start: DateTime.fromMillisecondsSinceEpoch(ms('startMs') ?? 0),
      end: DateTime.fromMillisecondsSinceEpoch(ms('endMs') ?? 0),
      bedMinutes: ms('bedMinutes') ?? 0,
      wakeMinutes: ms('wakeMinutes') ?? 0,
      timeInBed: Duration(milliseconds: ms('timeInBedMs') ?? 0),
      asleep: dur('asleepMs'),
      deep: dur('deepMs'),
      rem: dur('remMs'),
      light: dur('lightMs'),
      awake: dur('awakeMs'),
      hasStageFigures: map['hasStageFigures'] == true,
      sessionCount: ms('sessionCount') ?? 1,
      spans: spans,
      metrics: NightMetrics.fromJson(map['metrics']),
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = <String, dynamic>{
      'date': dateKey,
      'startMs': start.millisecondsSinceEpoch,
      'endMs': end.millisecondsSinceEpoch,
      'bedMinutes': bedMinutes,
      'wakeMinutes': wakeMinutes,
      'timeInBedMs': timeInBed.inMilliseconds,
      'hasStageFigures': hasStageFigures,
      'sessionCount': sessionCount,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (asleep != null) map['asleepMs'] = asleep!.inMilliseconds;
    if (deep != null) map['deepMs'] = deep!.inMilliseconds;
    if (rem != null) map['remMs'] = rem!.inMilliseconds;
    if (light != null) map['lightMs'] = light!.inMilliseconds;
    if (awake != null) map['awakeMs'] = awake!.inMilliseconds;
    if (spans.isNotEmpty) map['spans'] = spans.map((SleepStageSpan s) => s.toJson()).toList();
    if (metrics != null) map['metrics'] = metrics!.toJson();
    return map;
  }

  NightSummary toSummary() {
    final DateTime base = DateTime(date.year, date.month, date.day);
    DateTime bed = DateTime(base.year, base.month, base.day, bedMinutes ~/ 60, bedMinutes % 60);
    if (bedMinutes >= 12 * 60) bed = bed.subtract(const Duration(days: 1));
    DateTime wake = DateTime(base.year, base.month, base.day, wakeMinutes ~/ 60, wakeMinutes % 60);
    if (!wake.isAfter(bed)) wake = wake.add(const Duration(days: 1));

    return NightSummary(
      date: DateTime(date.year, date.month, date.day),
      start: start,
      end: end,
      mainStart: bed,
      mainEnd: wake,
      timeInBed: timeInBed,
      asleep: asleep,
      deep: deep,
      rem: rem,
      light: light,
      awake: awake,
      hasStageFigures: hasStageFigures,
      sessionCount: sessionCount,
      spans: spans,
      metrics: metrics,
    );
  }
}
