import 'package:flutter/material.dart';

import '../../health/analytics/sleep_analytics.dart';
import '../../health/presentation/sleep_format.dart';
import '../../health/sleep_controller.dart';
import '../../health/strand_sleep.dart';
import '../../ui/sleep_colors.dart';
import '../../ui/widgets/simple_line_chart.dart';

/// The Insights body, reusable for the user's own data and a friend's.
class InsightsView extends StatefulWidget {
  const InsightsView({
    super.key,
    required this.nights,
    required this.ownerName,
    this.showStatusCard = false,
    this.sleepController,
    this.onBack,
  });

  final List<NightSummary> nights;
  final String ownerName;
  final bool showStatusCard;
  final SleepController? sleepController;
  final VoidCallback? onBack;

  @override
  State<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends State<InsightsView> {
  SleepRange _range = SleepRange.week;
  int _selectedIndex = 0;

  List<NightSummary> get _nights => widget.nights;
  NightSummary? get _selected {
    if (_nights.isEmpty) return null;
    final int i = _selectedIndex.clamp(0, _nights.length - 1);
    return _nights[i];
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final List<NightSummary> nights = _nights;

    if (nights.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Text('No sleep nights yet.', style: t.bodyMedium),
      );
    }

    final NightSummary night = _selected!;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        28,
        20,
        28,
        100 + MediaQuery.of(context).padding.bottom,
      ),
      children: <Widget>[
        if (widget.onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 20, color: Colors.black),
            ),
          ),
        if (widget.showStatusCard && widget.sleepController != null)
          _statusCard(t, widget.sleepController!),
        _nightHeader(t, nights),
        const SizedBox(height: 24),
        _hypnogram(t, night),
        const SizedBox(height: 32),
        _stageBreakdown(t, night),
        const SizedBox(height: 32),
        _sleepTiming(t, night),
        const SizedBox(height: 32),
        _bodyMetrics(t, night),
        const SizedBox(height: 32),
        _comparedWithUsual(t, night, nights),
        const SizedBox(height: 32),
        _whatStoodOut(t, night, nights),
        const SizedBox(height: 36),
        const Divider(height: 1, thickness: 0.8, color: Color(0xFFE6E6E6)),
        const SizedBox(height: 32),
        _trends(t, nights),
        const SizedBox(height: 32),
        _consistency(t, nights),
        const SizedBox(height: 28),
        Text(
          'Data from Health Connect. Not medical advice.',
          style: t.bodySmall?.copyWith(fontSize: 10.5),
        ),
      ],
    );
  }

  List<SleepStageSpan> _spansFor(NightSummary night) {
    if (night.spans.isNotEmpty) return night.spans;
    final SleepController? sc = widget.sleepController;
    if (sc == null) return const <SleepStageSpan>[];
    return sc.records
        .where(
          (StrandSleep r) =>
              r.start.year == night.date.year &&
              r.start.month == night.date.month &&
              r.start.day == night.date.day,
        )
        .expand((StrandSleep r) => r.stages)
        .toList();
  }

  Widget _statusCard(TextTheme t, SleepController sleep) {
    String? message;
    String? buttonLabel;
    VoidCallback? action;
    if (sleep.status == SleepStatus.notInstalled) {
      message = 'Health Connect is not installed on this phone.';
      buttonLabel = 'INSTALL HEALTH CONNECT';
      action = () => sleep.installSource();
    } else if (sleep.status == SleepStatus.needsPermission ||
        sleep.status == SleepStatus.refused) {
      message = 'Strand needs permission to read your sleep.';
      buttonLabel = 'OPEN PERMISSIONS';
      action = () => sleep.requestAccess();
    } else if (widget.nights.isEmpty) {
      message = 'No sleep data found in the last 7 days.';
      buttonLabel = 'SYNC SLEEP DATA';
      action = () => sleep.sync();
    } else {
      final NightSummary latest = widget.nights.first;
      if (!latest.hasStageFigures) {
        message = 'Sleep data found, but no stage breakdown.';
        buttonLabel = 'OPEN HEALTH CONNECT';
        action = () => sleep.openSourceApp();
      }
    }
    if (message == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(message, style: t.bodyMedium),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onPressed: action,
              child: Text(
                buttonLabel!,
                style: const TextStyle(
                  letterSpacing: 2,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nightHeader(TextTheme t, List<NightSummary> nights) {
    final NightSummary night = _selected!;
    final int idx = _selectedIndex.clamp(0, nights.length - 1);
    final bool canPrev = idx < nights.length - 1;
    final bool canNext = idx > 0;
    final Duration? total = night.asleep;
    final String totalStr = total == null ? '—' : formatDuration(total);
    final String efficiency =
        (night.asleep != null && night.timeInBed > Duration.zero)
        ? '${(night.asleep!.inMilliseconds / night.timeInBed.inMilliseconds * 100).round()}%'
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            IconButton(
              onPressed: canPrev
                  ? () => setState(() => _selectedIndex = idx + 1)
                  : null,
              icon: const Icon(Icons.chevron_left, color: Colors.black),
            ),
            // A friend's name makes this line longer than the space between the
            // two chevrons. It scales down instead of spilling past the right
            // edge, so the row never paints an overflow stripe.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.ownerName == 'You'
                      ? formatSleepDate(night.date)
                      : '${widget.ownerName} — ${formatSleepDate(night.date)}',
                  style: t.headlineMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            IconButton(
              onPressed: canNext
                  ? () => setState(() => _selectedIndex = idx - 1)
                  : null,
              icon: const Icon(Icons.chevron_right, color: Colors.black),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            '${formatClock(night.mainStart)} – ${formatClock(night.mainEnd)}',
            style: t.bodySmall,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(totalStr, style: t.displayLarge?.copyWith(fontSize: 44)),
                  Text(
                    'TOTAL SLEEP',
                    style: t.labelSmall?.copyWith(
                      letterSpacing: 2,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(formatDuration(night.timeInBed), style: t.titleLarge),
                Text(
                  'TIME IN BED',
                  style: t.labelSmall?.copyWith(
                    letterSpacing: 2,
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(efficiency, style: t.titleLarge),
                Text(
                  'EFFICIENCY',
                  style: t.labelSmall?.copyWith(
                    letterSpacing: 2,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _hypnogram(TextTheme t, NightSummary night) {
    final List<SleepStageSpan> spans = _spansFor(night);
    if (spans.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'HYPNOGRAM',
            style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
          ),
          const SizedBox(height: 12),
          Container(
            height: 60,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE6E6E6)),
            ),
            child: Center(
              child: Text(
                'No stage timeline for this night',
                style: t.bodySmall,
              ),
            ),
          ),
        ],
      );
    }
    final Duration total = night.end.difference(night.start);
    final int totalMs = total.inMilliseconds <= 0 ? 1 : total.inMilliseconds;
    Color colorFor(SleepStage s) => switch (s) {
      SleepStage.deep => SleepPalette.deep,
      SleepStage.rem => SleepPalette.rem,
      SleepStage.light => SleepPalette.light,
      SleepStage.awake || SleepStage.awakeInBed => SleepPalette.awake,
      _ => SleepPalette.track,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'HYPNOGRAM',
          style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ClipRect(
            child: Row(
              children: <Widget>[
                for (final SleepStageSpan span in spans)
                  Expanded(
                    flex: (span.duration.inMilliseconds * 1000 / totalMs)
                        .round()
                        .clamp(1, 100000),
                    child: Container(color: colorFor(span.stage)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              formatClock(night.start),
              style: t.bodySmall?.copyWith(fontSize: 10),
            ),
            Text(
              formatClock(night.end),
              style: t.bodySmall?.copyWith(fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stageBreakdown(TextTheme t, NightSummary night) {
    final double? deepShare = night.stageShare(SleepStage.deep);
    final double? remShare = night.stageShare(SleepStage.rem);
    final double? lightShare = night.stageShare(SleepStage.light);
    final double? awakeShare = night.shareOfTimeInBed(SleepStage.awake);
    Widget row(String label, Color color, Duration? value, double? share) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: <Widget>[
            Container(width: 10, height: 10, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: t.bodyMedium)),
            Text(
              value == null ? '—' : formatDuration(value),
              style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                share == null ? '—' : '${(share * 100).round()}%',
                textAlign: TextAlign.right,
                style: t.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'STAGE BREAKDOWN',
          style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
        ),
        const SizedBox(height: 12),
        if (deepShare != null || remShare != null || lightShare != null)
          Container(
            height: 16,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE6E6E6)),
            ),
            child: Row(
              children: <Widget>[
                if (deepShare != null)
                  Expanded(
                    flex: (deepShare * 1000).round(),
                    child: Container(color: SleepPalette.deep),
                  ),
                if (remShare != null)
                  Expanded(
                    flex: (remShare * 1000).round(),
                    child: Container(color: SleepPalette.rem),
                  ),
                if (lightShare != null)
                  Expanded(
                    flex: (lightShare * 1000).round(),
                    child: Container(color: SleepPalette.light),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        row('Deep', SleepPalette.deep, night.deep, deepShare),
        row('REM', SleepPalette.rem, night.rem, remShare),
        row('Light', SleepPalette.light, night.light, lightShare),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Container(width: 10, height: 10, color: SleepPalette.awake),
            const SizedBox(width: 8),
            Expanded(child: Text('Awake', style: t.bodyMedium)),
            Text(
              night.awake == null ? '—' : formatDuration(night.awake!),
              style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                awakeShare == null ? '—' : '${(awakeShare * 100).round()}%',
                textAlign: TextAlign.right,
                style: t.bodySmall,
              ),
            ),
          ],
        ),
        Text(
          'Awake is a share of time in bed, not of sleep.',
          style: t.bodySmall?.copyWith(fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _sleepTiming(TextTheme t, NightSummary night) {
    final List<SleepStageSpan> spans = _spansFor(night);
    String fmt(Duration d) => formatDuration(d);
    Duration? sleepOnset;
    int awakenings = 0;
    Duration waso = Duration.zero;
    Duration? timeToFirstDeep;
    DateTime? firstSleep;
    for (final SleepStageSpan s in spans) {
      if (s.stage != SleepStage.awake &&
          s.stage != SleepStage.awakeInBed &&
          s.stage != SleepStage.outOfBed) {
        if (firstSleep == null || s.start.isBefore(firstSleep))
          firstSleep = s.start;
      }
    }
    if (firstSleep != null) {
      sleepOnset = firstSleep.difference(night.start);
      if (sleepOnset.isNegative) sleepOnset = Duration.zero;
    }
    if (firstSleep != null) {
      for (final SleepStageSpan s in spans) {
        if ((s.stage == SleepStage.awake || s.stage == SleepStage.awakeInBed) &&
            !s.start.isBefore(firstSleep) &&
            s.duration >= const Duration(minutes: 2)) {
          awakenings++;
          waso += s.duration;
        }
      }
    }
    DateTime? firstDeep;
    for (final SleepStageSpan s in spans) {
      if (s.stage == SleepStage.deep) {
        if (firstDeep == null || s.start.isBefore(firstDeep))
          firstDeep = s.start;
      }
    }
    if (firstDeep != null && firstSleep != null) {
      timeToFirstDeep = firstDeep.difference(firstSleep);
      if (timeToFirstDeep.isNegative) timeToFirstDeep = Duration.zero;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'SLEEP TIMING',
          style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
        ),
        const SizedBox(height: 12),
        _timingRow(
          t,
          'Time to fall asleep',
          sleepOnset == null ? '—' : fmt(sleepOnset),
        ),
        _timingRow(t, 'Awakenings', spans.isEmpty ? '—' : '$awakenings'),
        _timingRow(
          t,
          'Awake after sleep onset',
          spans.isEmpty ? '—' : fmt(waso),
        ),
        _timingRow(
          t,
          'Time to first deep sleep',
          timeToFirstDeep == null ? '—' : fmt(timeToFirstDeep),
        ),
      ],
    );
  }

  Widget _timingRow(TextTheme t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: t.bodyMedium),
          Text(
            value,
            style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _bodyMetrics(TextTheme t, NightSummary night) {
    final NightMetrics? m = night.metrics;
    if (m == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'OVERNIGHT BODY METRICS',
            style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
          ),
          const SizedBox(height: 12),
          Text('Not recorded for this night.', style: t.bodySmall),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'OVERNIGHT BODY METRICS',
          style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
        ),
        const SizedBox(height: 12),
        if (m.hasHeartRate) ...<Widget>[
          Text('Heart rate', style: t.bodyMedium),
          Text(
            'Lowest ${m.lowestHeartRate?.round() ?? '—'} · Avg ${m.averageHeartRate?.round() ?? '—'} bpm',
            style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (m.heartRateBuckets.length >= 2)
            SimpleLineChart(
              values: m.heartRateBuckets
                  .map((HeartRateBucket b) => b.avg)
                  .toList(),
              height: 60,
            ),
          const SizedBox(height: 10),
        ],
        _metricTile(
          t,
          'Resting heart rate',
          m.hasRestingHeartRate
              ? '${m.restingHeartRate?.round()} bpm'
              : 'Not recorded',
        ),
        _metricTile(
          t,
          'HRV (RMSSD)',
          m.hasHrv ? '${m.hrvAverage?.round()} ms' : 'Not recorded',
        ),
        _metricTile(
          t,
          'Blood oxygen',
          m.hasOxygenSaturation
              ? 'Avg ${m.oxygenSaturationAverage?.round()}% · Low ${m.oxygenSaturationLowest?.round()}%'
              : 'Not recorded',
        ),
        _metricTile(
          t,
          'Respiratory rate',
          m.hasRespiratoryRate
              ? 'Avg ${m.respiratoryRateAverage?.toStringAsFixed(1)} · ${m.respiratoryRateMin?.round()}–${m.respiratoryRateMax?.round()} /min'
              : 'Not recorded',
        ),
      ],
    );
  }

  Widget _metricTile(TextTheme t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: t.bodyMedium),
          Text(
            value,
            style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _comparedWithUsual(
    TextTheme t,
    NightSummary night,
    List<NightSummary> nights,
  ) {
    final SleepStats stats = SleepStats.of(nights);
    if (nights.length < 5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'COMPARED WITH MY USUAL',
            style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
          ),
          const SizedBox(height: 12),
          Text('Building your baseline', style: t.bodyMedium),
        ],
      );
    }
    String delta(Duration? a, Duration? b) {
      if (a == null || b == null) return '—';
      final Duration d = a - b;
      if (d.abs() < const Duration(minutes: 2)) return 'same';
      return '${d.isNegative ? '↓' : '↑'} ${formatDuration(d.abs())}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'COMPARED WITH MY USUAL',
          style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
        ),
        const SizedBox(height: 12),
        _metricTile(t, 'Total sleep', delta(night.asleep, stats.averageSleep)),
        _metricTile(t, 'Deep sleep', delta(night.deep, stats.averageDeep)),
        _metricTile(t, 'REM sleep', delta(night.rem, stats.averageRem)),
        _metricTile(t, 'Light sleep', delta(night.light, stats.averageLight)),
      ],
    );
  }

  Widget _whatStoodOut(
    TextTheme t,
    NightSummary night,
    List<NightSummary> nights,
  ) {
    final SleepStats stats = SleepStats.of(nights);
    final List<SleepStageSpan> spans = _spansFor(night);
    final List<String> observations = <String>[];
    if (night.deep != null && stats.averageDeep != null) {
      if (night.deep! > stats.averageDeep! + const Duration(minutes: 15))
        observations.add(
          'Deep sleep was ${formatDuration(night.deep! - stats.averageDeep!)} more than your usual.',
        );
      else if (night.deep! < stats.averageDeep! - const Duration(minutes: 15))
        observations.add(
          'Deep sleep was ${formatDuration(stats.averageDeep! - night.deep!)} less than your usual.',
        );
    }
    if (night.rem != null && stats.averageRem != null) {
      if (night.rem! > stats.averageRem! + const Duration(minutes: 15))
        observations.add(
          'REM sleep was ${formatDuration(night.rem! - stats.averageRem!)} more than your usual.',
        );
      else if (night.rem! < stats.averageRem! - const Duration(minutes: 15))
        observations.add(
          'REM sleep was ${formatDuration(stats.averageRem! - night.rem!)} less than your usual.',
        );
    }
    if (night.asleep != null && night.timeInBed > Duration.zero) {
      final double eff =
          night.asleep!.inMilliseconds / night.timeInBed.inMilliseconds;
      if (eff < 0.85)
        observations.add(
          'Sleep efficiency was ${(eff * 100).round()}%, below 85%.',
        );
    }
    DateTime? firstSleep;
    for (final SleepStageSpan s in spans) {
      if (s.stage != SleepStage.awake &&
          s.stage != SleepStage.awakeInBed &&
          s.stage != SleepStage.outOfBed) {
        if (firstSleep == null || s.start.isBefore(firstSleep))
          firstSleep = s.start;
      }
    }
    if (firstSleep != null) {
      final Duration onset = firstSleep.difference(night.start);
      if (onset > const Duration(minutes: 30))
        observations.add('It took ${formatDuration(onset)} to fall asleep.');
    }
    int awakenings = 0;
    if (firstSleep != null) {
      for (final SleepStageSpan s in spans) {
        if ((s.stage == SleepStage.awake || s.stage == SleepStage.awakeInBed) &&
            !s.start.isBefore(firstSleep) &&
            s.duration >= const Duration(minutes: 2))
          awakenings++;
      }
    }
    if (awakenings >= 4)
      observations.add('$awakenings awakenings during the night.');
    final NightMetrics? m = night.metrics;
    if (m != null &&
        m.hasOxygenSaturation &&
        m.oxygenSaturationLowest != null) {
      final List<double> lows = nights
          .map((NightSummary n) => n.metrics?.oxygenSaturationLowest)
          .whereType<double>()
          .toList();
      if (lows.length >= 5) {
        final double norm = lows.reduce((a, b) => a + b) / lows.length;
        if (m.oxygenSaturationLowest! < norm - 2)
          observations.add(
            'Lowest blood oxygen was ${m.oxygenSaturationLowest!.round()}%, below your usual ${norm.round()}%.',
          );
      }
    }
    if (m != null && m.hasRestingHeartRate && m.restingHeartRate != null) {
      final List<double> rhrs = nights
          .map((NightSummary n) => n.metrics?.restingHeartRate)
          .whereType<double>()
          .toList();
      if (rhrs.length >= 5) {
        final double norm = rhrs.reduce((a, b) => a + b) / rhrs.length;
        if (m.restingHeartRate! > norm + 5)
          observations.add(
            'Resting heart rate was ${m.restingHeartRate!.round()} bpm, above your usual ${norm.round()} bpm.',
          );
      }
    }
    final double? bedMean = stats.bedtime.meanMinutes;
    if (bedMean != null) {
      final double bedMin =
          night.mainStart.hour * 60 + night.mainStart.minute.toDouble();
      double diff = (bedMin - bedMean).abs();
      if (diff > 720) diff = 1440 - diff;
      if (diff > 60)
        observations.add(
          'Bedtime moved ${diff.round()} minutes from your usual.',
        );
    }
    if (observations.isEmpty)
      observations.add('This night was within your usual range.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'WHAT STOOD OUT',
          style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
        ),
        const SizedBox(height: 12),
        for (final String o in observations.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(o, style: t.bodyMedium?.copyWith(height: 1.5)),
          ),
      ],
    );
  }

  /// Three plain words, one small underline. No pill, no container, no
  /// second row of chrome. The only thing that moves is the underline.
  Widget _rangeSelector() {
    const List<SleepRange> ranges = <SleepRange>[
      SleepRange.week,
      SleepRange.month,
      SleepRange.quarter,
    ];
    return Row(
      children: <Widget>[
        for (final SleepRange r in ranges)
          Semantics(
            button: true,
            selected: _range == r,
            label: r.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _range = r),
              child: Padding(
                padding: const EdgeInsets.only(right: 22, top: 2, bottom: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      r.shortLabel,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: _range == r
                            ? FontWeight.w600
                            : FontWeight.w400,
                        letterSpacing: 1.4,
                        color: _range == r
                            ? Colors.black
                            : const Color(0xFF9A9A9A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 1.2,
                      width: 16,
                      color: _range == r ? Colors.black : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _trends(TextTheme t, List<NightSummary> nights) {
    final List<NightSummary> ranged = SleepAnalytics.inRange(nights, _range);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'TRENDS',
          style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
        ),
        const SizedBox(height: 14),
        _rangeSelector(),
        const SizedBox(height: 12),
        Text(
          '${ranged.length} nights in ${_range.label.toLowerCase()}',
          style: t.bodySmall,
        ),
        const SizedBox(height: 12),
        if (ranged.length >= 2)
          SimpleLineChart(
            values: ranged.reversed
                .map((NightSummary n) => n.asleep?.inMinutes.toDouble() ?? 0)
                .toList(),
            height: 90,
          ),
      ],
    );
  }

  Widget _consistency(TextTheme t, List<NightSummary> nights) {
    final SleepStats stats = SleepStats.of(nights);
    String clock(double? m) {
      if (m == null) return '—';
      final int mins = m.round().clamp(0, 1439);
      final DateTime d = DateTime(2000, 1, 1).add(Duration(minutes: mins));
      return formatClock(d);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'SLEEP CONSISTENCY',
          style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
        ),
        const SizedBox(height: 12),
        _timingRow(t, 'Bedtime', clock(stats.bedtime.meanMinutes)),
        _timingRow(
          t,
          'Bedtime variation',
          stats.bedtime.spreadMinutes == null
              ? '—'
              : '±${stats.bedtime.spreadMinutes!.round()}m',
        ),
        _timingRow(t, 'Wake-up', clock(stats.wake.meanMinutes)),
        _timingRow(
          t,
          'Wake-up variation',
          stats.wake.spreadMinutes == null
              ? '—'
              : '±${stats.wake.spreadMinutes!.round()}m',
        ),
        _timingRow(
          t,
          'Sleep duration variation',
          stats.sleepStdDevMinutes == null
              ? '—'
              : '±${stats.sleepStdDevMinutes!.round()}m',
        ),
      ],
    );
  }
}
