import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:health/health.dart';

import 'sleep_source_service.dart';
import 'strand_sleep.dart';

/// Reads sleep from Health Connect.
class HealthConnectSleepSource implements SleepSourceService {
  HealthConnectSleepSource({Health? health}) : _health = health ?? Health();

  final Health _health;

  bool _configured = false;

  @override
  String get displayName => 'Health Connect';

  static const HealthDataType _sessionType = HealthDataType.SLEEP_SESSION;

  static const List<HealthDataType> stageTypes = <HealthDataType>[
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_AWAKE_IN_BED,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_OUT_OF_BED,
    HealthDataType.SLEEP_UNKNOWN,
  ];

  static SleepStage? _stageFor(HealthDataType type) => switch (type) {
    HealthDataType.SLEEP_ASLEEP => SleepStage.asleep,
    HealthDataType.SLEEP_AWAKE => SleepStage.awake,
    HealthDataType.SLEEP_AWAKE_IN_BED => SleepStage.awakeInBed,
    HealthDataType.SLEEP_DEEP => SleepStage.deep,
    HealthDataType.SLEEP_LIGHT => SleepStage.light,
    HealthDataType.SLEEP_REM => SleepStage.rem,
    HealthDataType.SLEEP_OUT_OF_BED => SleepStage.outOfBed,
    HealthDataType.SLEEP_UNKNOWN => SleepStage.unknown,
    _ => null,
  };

  List<RawSleepStage> orphanStages = const <RawSleepStage>[];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<SleepSourceAvailability> availability() async {
    if (!Platform.isAndroid) return SleepSourceAvailability.unsupported;
    try {
      await _ensureConfigured();
    } catch (_) {
      return SleepSourceAvailability.unknown;
    }
    try {
      if (await _health.isHealthConnectAvailable()) {
        return SleepSourceAvailability.ready;
      }
      return SleepSourceAvailability.notInstalled;
    } catch (_) {
      return SleepSourceAvailability.unknown;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      await _ensureConfigured();
      final bool? result = await _health.hasPermissions(permissionTypes);
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      const MethodChannel channel = MethodChannel('strand/health');
      final bool? granted =
          await channel.invokeMethod<bool>('requestPermissions');
      if (granted == true) return true;
    } catch (_) {}
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(permissionTypes);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openSystemPermissions() async {
    try {
      await _ensureConfigured();
      await _health.getHealthConnectSdkStatus();
    } catch (_) {}
  }

  @override
  Future<void> installSource() async {
    try {
      await _ensureConfigured();
      await _health.installHealthConnect();
    } catch (_) {}
  }

  @override
  Future<void> openSourceApp() => openSystemPermissions();

  static final List<HealthDataType> permissionTypes = <HealthDataType>[
    _sessionType,
    ...stageTypes,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESPIRATORY_RATE,
  ];

  @override
  Future<bool> historyAuthorized() async {
    try {
      await _ensureConfigured();
      return await _health.isHealthDataHistoryAuthorized();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestHistoryAuthorization() async {
    try {
      await _ensureConfigured();
      return await _health.requestHealthDataHistoryAuthorization();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<RawSleepSession>> readSessions(DateTime from, DateTime to) async {
    await _ensureConfigured();
    final List<HealthDataPoint> points = await _health.getHealthDataFromTypes(
      types: <HealthDataType>[_sessionType],
      startTime: from,
      endTime: to,
    );

    // Prefer Samsung Health when several apps wrote overlapping sessions.
    final List<RawSleepSession> raw = <RawSleepSession>[];
    for (final HealthDataPoint point in points) {
      if (point.type != _sessionType) continue;
      final String uuid = point.uuid;
      if (uuid.isEmpty) continue;
      if (point.dateTo.isBefore(point.dateFrom)) continue;
      raw.add(
        RawSleepSession(
          sessionId: uuid,
          start: point.dateFrom,
          end: point.dateTo,
          sourcePackage: point.sourceName,
          sourceName: point.sourceId,
          deviceId: point.sourceDeviceId.isEmpty ? null : point.sourceDeviceId,
        ),
      );
    }

    // Deduplicate overlapping sessions, preferring Samsung Health origin.
    final List<RawSleepSession> deduped = <RawSleepSession>[];
    for (final RawSleepSession s in raw) {
      final int idx = deduped.indexWhere((RawSleepSession existing) {
        final DateTime overlapStart =
            s.start.isAfter(existing.start) ? s.start : existing.start;
        final DateTime overlapEnd =
            s.end.isBefore(existing.end) ? s.end : existing.end;
        return overlapEnd.isAfter(overlapStart);
      });
      if (idx >= 0) {
        final RawSleepSession existing = deduped[idx];
        final bool sIsSamsung =
            s.sourcePackage == 'com.sec.android.app.shealth';
        final bool existingIsSamsung =
            existing.sourcePackage == 'com.sec.android.app.shealth';
        if (sIsSamsung && !existingIsSamsung) {
          deduped[idx] = s;
        }
      } else {
        deduped.add(s);
      }
    }

    // Read body metrics for the whole window once.
    final Map<HealthDataType, List<HealthDataPoint>> metricPoints =
        <HealthDataType, List<HealthDataPoint>>{};
    for (final HealthDataType type in <HealthDataType>[
      HealthDataType.HEART_RATE,
      HealthDataType.RESTING_HEART_RATE,
      HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      HealthDataType.BLOOD_OXYGEN,
      HealthDataType.RESPIRATORY_RATE,
      HealthDataType.SKIN_TEMPERATURE,
    ]) {
      try {
        metricPoints[type] = await _health.getHealthDataFromTypes(
          types: <HealthDataType>[type],
          startTime: from,
          endTime: to,
        );
      } catch (_) {
        metricPoints[type] = const <HealthDataPoint>[];
      }
    }

    final List<RawSleepSession> out = <RawSleepSession>[];
    for (final RawSleepSession session in deduped) {
      final NightMetrics metrics = _aggregateMetrics(session, metricPoints);
      out.add(
        RawSleepSession(
          sessionId: session.sessionId,
          start: session.start,
          end: session.end,
          sourcePackage: session.sourcePackage,
          sourceName: session.sourceName,
          deviceId: session.deviceId,
          metrics: metrics,
        ),
      );
    }
    return out;
  }

  NightMetrics _aggregateMetrics(
    RawSleepSession session,
    Map<HealthDataType, List<HealthDataPoint>> metricPoints,
  ) {
    bool inWindow(HealthDataPoint p) =>
        !p.dateFrom.isBefore(session.start) && !p.dateTo.isAfter(session.end);

    final List<HealthDataPoint> hrPoints =
        (metricPoints[HealthDataType.HEART_RATE] ?? const <HealthDataPoint>[])
            .where(inWindow)
            .toList();
    final List<HeartRateBucket> buckets = <HeartRateBucket>[];
    if (hrPoints.isNotEmpty) {
      DateTime cursor = session.start;
      while (cursor.isBefore(session.end)) {
        final DateTime bucketEnd = cursor.add(const Duration(minutes: 5));
        final List<HealthDataPoint> inBucket = hrPoints
            .where((HealthDataPoint p) =>
                !p.dateFrom.isBefore(cursor) && p.dateFrom.isBefore(bucketEnd))
            .toList();
        if (inBucket.isNotEmpty) {
          double min = double.infinity;
          double max = double.negativeInfinity;
          double sum = 0;
          int count = 0;
          for (final HealthDataPoint p in inBucket) {
            final num? v = (p.value as NumericHealthValue?)?.numericValue;
            if (v == null) continue;
            final double val = v.toDouble();
            if (val < min) min = val;
            if (val > max) max = val;
            sum += val;
            count++;
          }
          if (count > 0) {
            buckets.add(HeartRateBucket(
              start: cursor,
              min: min,
              avg: sum / count,
              max: max,
            ));
          }
        }
        cursor = bucketEnd;
      }
    }

    double? lowestHr;
    double? avgHr;
    if (hrPoints.isNotEmpty) {
      double min = double.infinity;
      double sum = 0;
      int count = 0;
      for (final HealthDataPoint p in hrPoints) {
        final num? v = (p.value as NumericHealthValue?)?.numericValue;
        if (v == null) continue;
        final double val = v.toDouble();
        if (val < min) min = val;
        sum += val;
        count++;
      }
      if (count > 0) {
        lowestHr = min;
        avgHr = sum / count;
      }
    }

    double? rhr;
    final List<HealthDataPoint> rhrPoints =
        (metricPoints[HealthDataType.RESTING_HEART_RATE] ?? const <HealthDataPoint>[])
            .where(inWindow)
            .toList();
    if (rhrPoints.isNotEmpty) {
      HealthDataPoint closest = rhrPoints.first;
      int bestDiff = closest.dateFrom.difference(session.start).inSeconds.abs();
      for (final HealthDataPoint p in rhrPoints) {
        final int diff = p.dateFrom.difference(session.start).inSeconds.abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          closest = p;
        }
      }
      final num? v = (closest.value as NumericHealthValue?)?.numericValue;
      if (v != null) rhr = v.toDouble();
    }

    double? hrvAvg;
    final List<HealthDataPoint> hrvPoints =
        (metricPoints[HealthDataType.HEART_RATE_VARIABILITY_RMSSD] ?? const <HealthDataPoint>[])
            .where(inWindow)
            .toList();
    if (hrvPoints.isNotEmpty) {
      double sum = 0;
      int count = 0;
      for (final HealthDataPoint p in hrvPoints) {
        final num? v = (p.value as NumericHealthValue?)?.numericValue;
        if (v == null) continue;
        sum += v.toDouble();
        count++;
      }
      if (count > 0) hrvAvg = sum / count;
    }

    double? spo2Avg;
    double? spo2Low;
    final List<HealthDataPoint> spo2Points =
        (metricPoints[HealthDataType.BLOOD_OXYGEN] ?? const <HealthDataPoint>[])
            .where(inWindow)
            .toList();
    if (spo2Points.isNotEmpty) {
      double sum = 0;
      double min = double.infinity;
      int count = 0;
      for (final HealthDataPoint p in spo2Points) {
        final num? v = (p.value as NumericHealthValue?)?.numericValue;
        if (v == null) continue;
        final double val = v.toDouble();
        sum += val;
        if (val < min) min = val;
        count++;
      }
      if (count > 0) {
        spo2Avg = sum / count;
        spo2Low = min;
      }
    }

    double? rrAvg;
    double? rrMin;
    double? rrMax;
    final List<HealthDataPoint> rrPoints =
        (metricPoints[HealthDataType.RESPIRATORY_RATE] ?? const <HealthDataPoint>[])
            .where(inWindow)
            .toList();
    if (rrPoints.isNotEmpty) {
      double sum = 0;
      double min = double.infinity;
      double max = double.negativeInfinity;
      int count = 0;
      for (final HealthDataPoint p in rrPoints) {
        final num? v = (p.value as NumericHealthValue?)?.numericValue;
        if (v == null) continue;
        final double val = v.toDouble();
        sum += val;
        if (val < min) min = val;
        if (val > max) max = val;
        count++;
      }
      if (count > 0) {
        rrAvg = sum / count;
        rrMin = min;
        rrMax = max;
      }
    }

    return NightMetrics(
      heartRateBuckets: buckets,
      lowestHeartRate: lowestHr,
      averageHeartRate: avgHr,
      restingHeartRate: rhr,
      hrvAverage: hrvAvg,
      oxygenSaturationAverage: spo2Avg,
      oxygenSaturationLowest: spo2Low,
      respiratoryRateAverage: rrAvg,
      respiratoryRateMin: rrMin,
      respiratoryRateMax: rrMax,
      hasHeartRate: hrPoints.isNotEmpty,
      hasRestingHeartRate: rhrPoints.isNotEmpty,
      hasHrv: hrvPoints.isNotEmpty,
      hasOxygenSaturation: spo2Points.isNotEmpty,
      hasRespiratoryRate: rrPoints.isNotEmpty,
    );
  }

  @override
  Future<List<RawSleepStage>> readStages(DateTime from, DateTime to) async {
    await _ensureConfigured();
    final List<HealthDataPoint> points = await _health.getHealthDataFromTypes(
      types: stageTypes,
      startTime: from,
      endTime: to,
    );

    final List<RawSleepStage> out = <RawSleepStage>[];
    final Set<String> seen = <String>{};

    for (final HealthDataPoint point in points) {
      final SleepStage? stage = _stageFor(point.type);
      if (stage == null) continue;
      final String uuid = point.uuid;
      if (uuid.isEmpty) continue;
      if (point.dateTo.isBefore(point.dateFrom)) continue;

      final String key =
          '$uuid|${stage.name}|'
          '${point.dateFrom.toUtc().microsecondsSinceEpoch}|'
          '${point.dateTo.toUtc().microsecondsSinceEpoch}';
      if (!seen.add(key)) continue;

      out.add(
        RawSleepStage(
          sessionId: uuid,
          stage: stage,
          start: point.dateFrom,
          end: point.dateTo,
        ),
      );
    }
    return out;
  }
}
