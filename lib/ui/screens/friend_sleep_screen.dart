import 'package:flutter/material.dart';

import '../../health/analytics/sleep_analytics.dart';
import '../../health/presentation/sleep_format.dart';
import '../../health/strand_sleep.dart';
import '../../social/cloud_store.dart';
import '../display_name.dart';
import '../../ui/sleep_colors.dart';
import '../../ui/widgets/concentric_sleep_rings.dart';

/// One friend's shared sleep, clearly attributed to them.
class FriendSleepScreen extends StatefulWidget {
  const FriendSleepScreen({super.key, required this.friend});

  final Friendship friend;

  @override
  State<FriendSleepScreen> createState() => _FriendSleepScreenState();
}

class _FriendSleepScreenState extends State<FriendSleepScreen> {
  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(displayName(widget.friend.otherName), style: t.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<NightSummary>>(
          stream: CloudStore.friendNights(widget.friend.otherUid),
          builder: (BuildContext context,
              AsyncSnapshot<List<NightSummary>> snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  snapshot.error is CloudException
                      ? (snapshot.error as CloudException).message
                      : 'Could not load ${displayName(widget.friend.otherName)}\'s sleep.',
                  style: t.bodyMedium,
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting &&
                (snapshot.data == null || snapshot.data!.isEmpty)) {
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              );
            }
            final List<NightSummary> nights =
                snapshot.data ?? const <NightSummary>[];
            if (nights.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'No nights shared yet.',
                      style: t.headlineLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${displayName(widget.friend.otherName)}\'s records appear here after '
                      'they sync from their device.',
                      style: t.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              );
            }

            final NightSummary latest = nights.first;
            final SleepStats stats = SleepStats.of(nights);
            final List<NightSummary> week = SleepAnalytics.inRange(
              nights,
              SleepRange.week,
            );
            final SleepStats weekStats = SleepStats.of(week);
            final SleepComparison comparison = SleepAnalytics.compare(
              nights,
              SleepRange.week,
            );
            final List<String> observations = comparison.hasEnoughData
                ? SleepAnalytics.observations(
                    comparison.current,
                    comparison.previous,
                    SleepRange.week,
                  )
                : const <String>[];

            return ListView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 96),
              children: <Widget>[
                Text(
                  'SHARED WITH YOU',
                  style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '${displayName(widget.friend.otherName)}\'s sleep',
                  style: t.headlineLarge,
                ),
                const SizedBox(height: 4),
                Text(widget.friend.otherEmail, style: t.bodySmall),
                const SizedBox(height: 24),
                _latest(t, latest),
                const SizedBox(height: 28),
                _averages(t, stats, weekStats, nights.length),
                const SizedBox(height: 28),
                _consistency(t, stats),
                if (observations.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 28),
                  _insights(t, observations),
                ],
                const SizedBox(height: 28),
                _history(t, nights),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _latest(TextTheme t, NightSummary night) {
    final SleepRingData rings = SleepRingData.fromNight(night);
    final Duration? total = night.asleep;
    final bool hasTotal = total != null;
    final String centerLabel = hasTotal ? formatDuration(total) : '—';
    final String centerCaption = hasTotal
        ? 'TOTAL SLEEP'
        : night.hasSleep
            ? 'TOTAL SLEEP UNAVAILABLE'
            : 'TOTAL SLEEP';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('LATEST NIGHT', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5)),
        const SizedBox(height: 4),
        Text(
          '${displayName(widget.friend.otherName)} — ${formatSleepDateShort(night.date)}',
          style: t.bodySmall,
        ),
        const SizedBox(height: 16),
        Center(
          child: ConcentricSleepRings(
            data: rings,
            size: 260,
            centerLabel: centerLabel,
            centerCaption: centerCaption,
          ),
        ),
        const SizedBox(height: 18),
        _breakdown(t, night),
      ],
    );
  }

  Widget _breakdown(TextTheme t, NightSummary night) {
    final double? deepShare = night.stageShare(SleepStage.deep);
    final double? remShare = night.stageShare(SleepStage.rem);
    final double? lightShare = night.stageShare(SleepStage.light);
    final double? awakeShare = night.shareOfTimeInBed(SleepStage.awake);

    Widget card(String label, Color color, Duration? value, double? share, String suffix) {
      return SizedBox(
        width: (MediaQuery.of(context).size.width - 56 - 10) / 2,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE6E6E6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(width: 8, height: 8, color: color),
                  const SizedBox(width: 6),
                  Text(label, style: t.labelSmall?.copyWith(fontSize: 9, letterSpacing: 1.4)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value == null ? '—' : formatDuration(value),
                style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                share == null ? 'not recorded' : '${(share * 100).round()}% $suffix',
                style: t.bodySmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        card('DEEP', SleepPalette.deep, night.deep, deepShare, 'of sleep'),
        card('REM', SleepPalette.rem, night.rem, remShare, 'of sleep'),
        card('LIGHT', SleepPalette.light, night.light, lightShare, 'of sleep'),
        card('AWAKE', SleepPalette.awake, night.awake, awakeShare, 'of time in bed'),
      ],
    );
  }

  Widget _averages(TextTheme t, SleepStats stats, SleepStats weekStats, int totalNights) {
    String d(Duration? v) => v == null ? '—' : formatDuration(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('AVERAGES', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5)),
        const SizedBox(height: 10),
        _row(t, 'Nights with data', '$totalNights'),
        _row(t, 'Average total sleep (all)', d(stats.averageSleep)),
        _row(t, 'Average total sleep (7D)', d(weekStats.averageSleep)),
        _row(t, 'Average time in bed', d(stats.averageTimeInBed)),
        _row(t, 'Average deep sleep', d(stats.averageDeep)),
        _row(t, 'Average REM sleep', d(stats.averageRem)),
        _row(t, 'Average light sleep', d(stats.averageLight)),
        _row(t, 'Average awake time', d(stats.averageAwake)),
        _row(
          t,
          'Awake share of time in bed',
          stats.averageAwakeShare == null
              ? '—'
              : '${(stats.averageAwakeShare! * 100).round()}%',
        ),
      ],
    );
  }

  Widget _consistency(TextTheme t, SleepStats stats) {
    String clock(double? minutes) {
      if (minutes == null) return '—';
      final int m = minutes.round().clamp(0, 1439);
      final DateTime d = DateTime(2000, 1, 1).add(Duration(minutes: m));
      return formatClock(d);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('CONSISTENCY', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5)),
        const SizedBox(height: 10),
        _row(t, 'Bedtime', clock(stats.bedtime.meanMinutes)),
        _row(
          t,
          'Bedtime variation',
          stats.bedtime.spreadMinutes == null
              ? '—'
              : '±${stats.bedtime.spreadMinutes!.round()}m',
        ),
        _row(t, 'Wake-up', clock(stats.wake.meanMinutes)),
        _row(
          t,
          'Wake-up variation',
          stats.wake.spreadMinutes == null
              ? '—'
              : '±${stats.wake.spreadMinutes!.round()}m',
        ),
        _row(
          t,
          'Sleep duration variation',
          stats.sleepStdDevMinutes == null
              ? '—'
              : '±${stats.sleepStdDevMinutes!.round()}m',
        ),
        _row(t, 'Nights with a main sleep', '${stats.clockNights}'),
      ],
    );
  }

  Widget _insights(TextTheme t, List<String> observations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('INSIGHTS', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5)),
        const SizedBox(height: 10),
        for (final String sentence in observations)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(sentence, style: t.bodyMedium?.copyWith(height: 1.5)),
          ),
      ],
    );
  }

  Widget _history(TextTheme t, List<NightSummary> nights) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('HISTORY', style: t.labelSmall?.copyWith(letterSpacing: 2, fontSize: 9.5)),
        const SizedBox(height: 10),
        for (final NightSummary n in nights.take(30))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE6E6E6)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(formatSleepDateShort(n.date), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'Deep ${n.deep == null ? '—' : formatDuration(n.deep!)} · '
                        'REM ${n.rem == null ? '—' : formatDuration(n.rem!)} · '
                        'Light ${n.light == null ? '—' : formatDuration(n.light!)} · '
                        'Awake ${n.awake == null ? '—' : formatDuration(n.awake!)}',
                        style: t.bodySmall?.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                Text(
                  n.asleep == null ? '—' : formatDuration(n.asleep!),
                  style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(TextTheme t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: t.bodySmall?.copyWith(fontSize: 12)),
          Text(value, style: t.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
