import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../health/analytics/sleep_analytics.dart';
import '../../health/presentation/sleep_format.dart';
import '../../health/sleep_controller.dart';
import '../../health/strand_sleep.dart';
import '../display_name.dart';
import '../widgets/friend_comparison.dart';
import 'settings_screen.dart';

/// Home: a greeting, one large number, and eight quiet facts about the night.
///
/// There is no ring here any more. Every figure below comes from the same
/// [NightSummary] the rest of the app reads, and a figure that was not recorded
/// says "No data" rather than becoming a zero.
///
/// The large number is time actually asleep. The sentence under it is the time
/// in bed, not the time since waking — the two used to be confused here, which
/// made a 6h 15m session report "Awake 7h 44m".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Soft, readable pastels. The text on every one of them is black or dark
  // grey, never white, because these are quiet labels rather than alerts.
  static const Color _yellow = Color(0xFFF7EBC8);
  static const Color _orange = Color(0xFFF8DFC8);
  static const Color _coral = Color(0xFFF7D3CF);
  static const Color _blue = Color(0xFFD7E6F6);
  static const Color _mint = Color(0xFFD8EDE0);
  static const Color _lavender = Color(0xFFE5DEF4);
  static const Color _cream = Color(0xFFF3E8D8);
  static const Color _periwinkle = Color(0xFFE1E5F7);

  @override
  Widget build(BuildContext context) {
    final SleepController sleep = SleepScope.of(context);
    return ListenableBuilder(
      listenable: sleep,
      builder: (BuildContext context, Widget? _) {
        final TextTheme t = Theme.of(context).textTheme;
        final double bottomClearance =
            MediaQuery.paddingOf(context).bottom + 110;

        final List<NightSummary> nights = SleepAnalytics.canonicalNights(
          sleep.records,
        );
        final NightSummary? night = nights.isEmpty ? null : nights.first;

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            top: true,
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(28, 22, 28, bottomClearance),
              children: <Widget>[
                _header(t, sleep),
                const SizedBox(height: 38),
                _hero(t, night),
                const SizedBox(height: 34),
                _blocks(night),
                if (night == null) ...<Widget>[
                  const SizedBox(height: 26),
                  _connectButton(sleep),
                ],
                const SizedBox(height: 56),
                FriendComparisonSection(
                  authUid: AuthScope.of(context).account?.uid ?? '',
                  myNights: nights,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(TextTheme t, SleepController sleep) {
    final String name = displayName(AuthScope.of(context).greetingName);
    final String hello = name.isEmpty ? 'Hello' : 'Hello, $name';
    final int hour = DateTime.now().hour;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                hello,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.1,
                  height: 1.12,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _greeting(hour),
                style: t.bodyLarge?.copyWith(
                  fontSize: 14,
                  color: const Color(0xFF3C3C3C),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                formatLongDate(DateTime.now()),
                style: t.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: const Color(0xFF7A7A7A),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _HeaderAction(
              tooltip: 'Settings',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(showBack: true),
                ),
              ),
              child: const Icon(
                Icons.settings_outlined,
                size: 20,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 2),
            _HeaderAction(
              tooltip: 'Refresh sleep data',
              onTap: sleep.busy
                  ? null
                  : () async {
                      await sleep.sync(forceFull: true);
                    },
              child: sleep.busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.3),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      size: 21,
                      color: Colors.black,
                    ),
            ),
          ],
        ),
      ],
    );
  }

  String _greeting(int hour) {
    if (hour < 5) return 'Still awake?';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'About time';
  }

  Widget _hero(TextTheme t, NightSummary? night) {
    final Duration? total = night?.asleep;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'SLEEP DURATION',
          style: t.labelSmall?.copyWith(
            fontSize: 9.5,
            letterSpacing: 2.6,
            color: const Color(0xFF3C3C3C),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          total == null ? 'No data' : formatDuration(total),
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: total == null ? 30 : 58,
            fontWeight: FontWeight.w700,
            height: 1.0,
            letterSpacing: total == null ? -0.6 : -2.8,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          _awakeningLine(night),
          style: t.bodyLarge?.copyWith(
            fontSize: 13.5,
            color: const Color(0xFF5C5C5C),
          ),
        ),
      ],
    );
  }

  Widget _blocks(NightSummary? night) {
    final Map<SleepStage, int> shares = _shares(night);
    final SleepStageSpan? longestDeep = _longestSpan(night, SleepStage.deep);
    final DateTime? firstRem = _firstSpanStart(night, SleepStage.rem);

    String shareOfNight(SleepStage stage) {
      final int? percent = shares[stage];
      return percent == null ? '' : '$percent% of the night';
    }

    String shareOfBed(SleepStage stage) {
      final int? percent = shares[stage];
      return percent == null ? '' : '$percent% of time in bed';
    }

    final int? efficiency =
        night == null ||
            night.asleep == null ||
            night.timeInBed <= Duration.zero
        ? null
        : (night.asleep!.inMilliseconds / night.timeInBed.inMilliseconds * 100)
              .round();

    final String deepDetail = _joinDetails(<String>[
      shareOfNight(SleepStage.deep),
      if (longestDeep != null)
        _unbreakable('longest ${formatDuration(longestDeep.duration)}'),
    ]);
    final String remDetail = _joinDetails(<String>[
      shareOfNight(SleepStage.rem),
      if (firstRem != null) _unbreakable('first at ${formatClock(firstRem)}'),
    ]);

    final List<_MetricTile> tiles = <_MetricTile>[
      _MetricTile(
        label: 'TIME IN BED',
        value: night == null ? 'No data' : formatDuration(night.timeInBed),
        detail: night == null
            ? 'No data'
            : formatSleepPeriod(night.mainStart, night.mainEnd),
        color: _yellow,
      ),
      _MetricTile(
        label: 'ACTUAL SLEEP',
        value: night?.asleep == null
            ? 'No data'
            : formatDuration(night!.asleep!),
        detail: efficiency == null ? 'No data' : '$efficiency% of time in bed',
        color: _orange,
      ),
      _MetricTile(
        label: 'DEEP SLEEP',
        value: night?.deep == null ? 'No data' : formatDuration(night!.deep!),
        detail: deepDetail,
        color: _coral,
      ),
      _MetricTile(
        label: 'REM SLEEP',
        value: night?.rem == null ? 'No data' : formatDuration(night!.rem!),
        detail: remDetail,
        color: _blue,
      ),
      _MetricTile(
        label: 'LIGHT SLEEP',
        value: night?.light == null ? 'No data' : formatDuration(night!.light!),
        detail: _joinDetails(<String>[shareOfNight(SleepStage.light)]),
        color: _mint,
      ),
      _MetricTile(
        label: 'AWAKE',
        value: night?.awake == null ? 'No data' : formatDuration(night!.awake!),
        detail: _joinDetails(<String>[shareOfBed(SleepStage.awake)]),
        color: _lavender,
      ),
      _heartRateTile(night),
      _vitalsTile(night),
    ];

    Widget row(_MetricTile a, _MetricTile b) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        row(tiles[0], tiles[1]),
        const SizedBox(height: 12),
        row(tiles[2], tiles[3]),
        const SizedBox(height: 12),
        row(tiles[4], tiles[5]),
        const SizedBox(height: 12),
        row(tiles[6], tiles[7]),
      ],
    );
  }

  /// Mean heart rate across the samples the source recorded during the night.
  ///
  /// Health Connect sends individual heart-rate readings rather than a summary,
  /// and the source averages every reading that falls inside the session. The
  /// subtext repeats the lowest reading, which is the one figure that says
  /// something about the night beyond the mean.
  static _MetricTile _heartRateTile(NightSummary? night) {
    final NightMetrics? m = night?.metrics;
    final double? average = m?.averageHeartRate;
    if (average == null) {
      return const _MetricTile(
        label: 'AVERAGE HEART RATE',
        value: 'No data',
        detail: 'Not recorded',
        color: _cream,
      );
    }
    final double? lowest = m?.lowestHeartRate;
    return _MetricTile(
      label: 'AVERAGE HEART RATE',
      value: '${average.round()} bpm',
      detail: lowest == null
          ? 'Overnight average'
          : 'Lowest ${lowest.round()} bpm overnight',
      color: _cream,
    );
  }

  /// The last card: measured blood oxygen, or an honest "No data".
  ///
  /// Heart rate now has its own card above this one, so this card stays on the
  /// one metric it names rather than switching to a second heart-rate reading
  /// and making the pair look duplicated.
  static _MetricTile _vitalsTile(NightSummary? night) {
    final NightMetrics? m = night?.metrics;
    if (m != null &&
        m.hasOxygenSaturation &&
        m.oxygenSaturationAverage != null) {
      final int average = m.oxygenSaturationAverage!.round();
      final int? lowest = m.oxygenSaturationLowest?.round();
      return _MetricTile(
        label: 'BLOOD OXYGEN',
        value: '$average%',
        detail: lowest == null
            ? 'Overnight average'
            : 'Lowest $lowest% overnight',
        color: _periwinkle,
      );
    }
    return const _MetricTile(
      label: 'BLOOD OXYGEN',
      value: 'No data',
      detail: 'Not recorded',
      color: _periwinkle,
    );
  }

  Widget _connectButton(SleepController sleep) {
    final bool canRetry =
        sleep.status == SleepStatus.needsPermission ||
        sleep.status == SleepStatus.refused ||
        sleep.status == SleepStatus.failed;
    if (!canRetry) return const SizedBox.shrink();

    return Center(
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: () async {
          await sleep.retry();
        },
        child: Text(
          sleep.status == SleepStatus.needsPermission
              ? 'CONNECT HEALTH DATA'
              : 'TRY AGAIN',
          style: const TextStyle(
            letterSpacing: 2,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static String _joinDetails(List<String> parts) {
    final List<String> kept = parts
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    return kept.isEmpty ? 'No data' : kept.join(' · ');
  }

  /// "You woke up 7 times during the night", or an em dash without stages.
  static String _awakeningLine(NightSummary? night) {
    final int? awakenings = _awakenings(night);
    if (awakenings == null) return 'Awakenings —';
    return 'You woke up $awakenings '
        '${awakenings == 1 ? 'time' : 'times'} during the night';
  }

  /// How many times the source recorded the sleeper waking up.
  ///
  /// The rule is the one Insights already uses for its Awakenings row: an awake
  /// span of at least two minutes, starting after sleep has begun. Health
  /// Connect emits many one-minute flickers that are stage-boundary noise
  /// rather than awakenings, and counting those would report two or three times
  /// the number a sleep app shows.
  static int? _awakenings(NightSummary? night) {
    if (night == null || night.spans.isEmpty) return null;
    DateTime? firstSleep;
    for (final SleepStageSpan span in night.spans) {
      if (span.stage == SleepStage.awake ||
          span.stage == SleepStage.awakeInBed ||
          span.stage == SleepStage.outOfBed) {
        continue;
      }
      if (firstSleep == null || span.start.isBefore(firstSleep)) {
        firstSleep = span.start;
      }
    }
    if (firstSleep == null) return null;

    int count = 0;
    for (final SleepStageSpan span in night.spans) {
      if (span.stage != SleepStage.awake &&
          span.stage != SleepStage.awakeInBed) {
        continue;
      }
      if (span.start.isBefore(firstSleep)) continue;
      if (span.duration >= const Duration(minutes: 2)) count++;
    }
    return count;
  }

  /// Keeps a short phrase on one line when a card's subtext wraps.
  ///
  /// The two-line subtexts are split at the separator; without this, "longest
  /// 28m" and "first at 6:21 AM" could leave a lone "28m" or "AM" on the second
  /// line, which reads as a typo rather than a sentence.
  static String _unbreakable(String value) => value.replaceAll(' ', '\u00A0');

  /// Whole-number shares of time in bed for the four stage cards.
  ///
  /// The denominator is the session, the same basis the sleep-stages chart
  /// uses, so a deep-sleep percentage means the same thing on both pages. When
  /// the four parts tile the session, the fractions lost to truncation go to
  /// light — the largest part — so the cards still read as one complete night.
  static Map<SleepStage, int> _shares(NightSummary? night) {
    if (night == null || night.timeInBed <= Duration.zero) {
      return const <SleepStage, int>{};
    }
    final int bed = night.timeInBed.inMilliseconds;
    int? truncated(Duration? value) =>
        value == null ? null : value.inMilliseconds * 100 ~/ bed;

    final int? deep = truncated(night.deep);
    final int? rem = truncated(night.rem);
    final int? light = truncated(night.light);
    final int? awake = truncated(night.awake);

    int? lightShare = light;
    if (deep != null && rem != null && light != null && awake != null) {
      final Duration parts =
          night.deep! + night.rem! + night.light! + night.awake!;
      if ((parts - night.timeInBed).inMinutes.abs() <= 2) {
        lightShare = (100 - deep - rem - awake).clamp(light, 100);
      }
    }

    return <SleepStage, int>{
      SleepStage.deep: ?deep,
      SleepStage.rem: ?rem,
      SleepStage.light: ?lightShare,
      SleepStage.awake: ?awake,
    };
  }

  static SleepStageSpan? _longestSpan(NightSummary? night, SleepStage stage) {
    if (night == null) return null;
    SleepStageSpan? best;
    for (final SleepStageSpan span in night.spans) {
      if (span.stage != stage) continue;
      if (best == null || span.duration > best.duration) best = span;
    }
    return best;
  }

  static DateTime? _firstSpanStart(NightSummary? night, SleepStage stage) {
    if (night == null) return null;
    DateTime? first;
    for (final SleepStageSpan span in night.spans) {
      if (span.stage != stage) continue;
      if (first == null || span.start.isBefore(first)) first = span.start;
    }
    return first;
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: onTap,
        icon: child,
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Color(0xFF4A4A4A),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: value == 'No data' ? 16 : 21,
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -0.4,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: Color(0xFF3F3F3F),
            ),
          ),
        ],
      ),
    );
  }
}
