import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../health/analytics/sleep_analytics.dart';
import '../../health/presentation/sleep_format.dart';
import '../../health/strand_sleep.dart';
import '../../social/cloud_store.dart';
import '../display_name.dart';
import '../theme.dart';

/// The sleep-sharing block on Home: one comparison per friend.
///
/// Everything here is computed from the same two nights the rest of the app
/// already holds — the reader's own [NightSummary] and the friend's published
/// one — so no figure on this section is a sample. When a friend has not
/// published last night yet the block says so and draws nothing else.
class FriendComparisonSection extends StatelessWidget {
  const FriendComparisonSection({
    super.key,
    required this.authUid,
    required this.myNights,
  });

  final String authUid;
  final List<NightSummary> myNights;

  @override
  Widget build(BuildContext context) {
    if (authUid.isEmpty) return const SizedBox.shrink();
    final TextTheme t = Theme.of(context).textTheme;

    return StreamBuilder<List<Friendship>>(
      stream: CloudStore.friends(authUid),
      builder: (BuildContext context, AsyncSnapshot<List<Friendship>> snap) {
        final List<Friendship> friends = snap.data ?? const <Friendship>[];
        // No friends, no section at all — not even the heading.
        if (friends.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Let\'s see how your friends did today',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < friends.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 24),
              _FriendComparison(
                key: ValueKey<String>(
                  '${friends[i].id}|${friends[i].otherUid}',
                ),
                friend: friends[i],
                myNights: myNights,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One friend's block: title bar, shared-night card, delta chips.
class _FriendComparison extends StatelessWidget {
  const _FriendComparison({
    super.key,
    required this.friend,
    required this.myNights,
  });

  final Friendship friend;
  final List<NightSummary> myNights;

  @override
  Widget build(BuildContext context) {
    final _CompareColors c = _CompareColors.of(context);
    final String name = _firstName(friend.otherName);
    final NightSummary? mine = myNights.isEmpty ? null : myNights.first;

    return StreamBuilder<List<NightSummary>>(
      stream: CloudStore.friendNights(friend.otherUid),
      builder:
          (BuildContext context, AsyncSnapshot<List<NightSummary>> snapshot) {
            final List<NightSummary>? theirs = snapshot.data;
            final NightSummary? sameNight = mine == null || theirs == null
                ? null
                : _nightOn(theirs, mine.date);

            if (mine == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ComparisonTitleBar(
                    title: 'You and $name',
                    score: null,
                    colors: c,
                  ),
                  const SizedBox(height: 10),
                  _MutedCard(message: 'Your night isn\'t in yet', colors: c),
                ],
              );
            }

            if (sameNight == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ComparisonTitleBar(
                    title: 'You and $name',
                    score: null,
                    colors: c,
                  ),
                  const SizedBox(height: 10),
                  _MutedCard(
                    message: theirs == null
                        ? 'Checking $name\'s night…'
                        : '$name\'s night isn\'t in yet',
                    colors: c,
                  ),
                ],
              );
            }

            final _ComparisonData data = _ComparisonData(mine, sameNight);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ComparisonTitleBar(
                  title: 'You and $name',
                  score: data.score,
                  colors: c,
                ),
                const SizedBox(height: 10),
                _SharedNightCard(data: data, friendName: name, colors: c),
                const SizedBox(height: 10),
                _DeltaChips(data: data, friendName: name, colors: c),
              ],
            );
          },
    );
  }
}

/// "You and Sakshi", outlined rather than floating, with the sync score at the
/// far right on the same centre line.
class _ComparisonTitleBar extends StatelessWidget {
  const _ComparisonTitleBar({
    required this.title,
    required this.score,
    required this.colors,
  });

  final String title;
  final int? score;
  final _CompareColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.fg,
              ),
            ),
          ),
        ),
        if (score != null) ...<Widget>[
          const SizedBox(width: 12),
          _SyncRing(score: score!, colors: colors),
        ],
      ],
    );
  }
}

/// A 52 px ring showing how much of the night the two people shared.
class _SyncRing extends StatelessWidget {
  const _SyncRing({required this.score, required this.colors});

  final int score;
  final _CompareColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sync score',
      value: '$score out of 100',
      child: SizedBox(
        width: 52,
        height: 52,
        child: CustomPaint(
          painter: _SyncRingPainter(
            score: score,
            track: colors.border,
            progress: _CompareColors.syncGreen,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$score',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                    color: colors.fg,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'sync',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                    color: colors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncRingPainter extends CustomPainter {
  const _SyncRingPainter({
    required this.score,
    required this.track,
    required this.progress,
  });

  final int score;
  final Color track;
  final Color progress;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 5;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.shortestSide - stroke) / 2;
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    final Paint filled = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = progress;

    canvas.drawCircle(center, radius, base);
    if (score <= 0) return;
    final double sweep = 2 * math.pi * (score.clamp(0, 100) / 100);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      filled,
    );
  }

  @override
  bool shouldRepaint(_SyncRingPainter old) =>
      old.score != score || old.track != track || old.progress != progress;
}

/// The raised card: shared total, the timeline, the legend and the scrubber
/// readout. The selected minute lives here because the timeline and the readout
/// underneath must always show the same moment.
class _SharedNightCard extends StatefulWidget {
  const _SharedNightCard({
    required this.data,
    required this.friendName,
    required this.colors,
  });

  final _ComparisonData data;
  final String friendName;
  final _CompareColors colors;

  @override
  State<_SharedNightCard> createState() => _SharedNightCardState();
}

class _SharedNightCardState extends State<_SharedNightCard> {
  late double _selected = widget.data.defaultMinutes;

  @override
  void didUpdateWidget(covariant _SharedNightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.axisStart != widget.data.axisStart ||
        oldWidget.data.axisEnd != widget.data.axisEnd) {
      _selected = widget.data.defaultMinutes;
    }
  }

  DateTime get _selectedMoment => widget.data.momentAt(_selected);

  @override
  Widget build(BuildContext context) {
    final _CompareColors c = widget.colors;
    final String mineStage = widget.data.stageAt(
      widget.data.mine,
      _selectedMoment,
    );
    final String friendStage = widget.data.stageAt(
      widget.data.theirs,
      _selectedMoment,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Asleep together',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c.secondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatDuration(widget.data.shared),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 24,
              fontWeight: FontWeight.w500,
              height: 1.1,
              letterSpacing: -0.5,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 14),
          _SharedTimeline(
            data: widget.data,
            friendName: widget.friendName,
            colors: c,
            selectedMinutes: _selected,
            mineStage: mineStage,
            friendStage: friendStage,
            moment: _selectedMoment,
            onSelected: (double minutes) {
              setState(
                () => _selected = minutes.clamp(0.0, widget.data.axisMinutes),
              );
            },
          ),
          const SizedBox(height: 10),
          _Legend(friendName: widget.friendName, colors: c),
          const SizedBox(height: 12),
          Container(height: 1, color: c.border),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(Icons.touch_app, size: 14, color: c.secondary),
              const SizedBox(width: 6),
              Text(
                formatClock(_selectedMoment),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You: $mineStage · ${widget.friendName}: $friendStage',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The two-band strip, its hour axis, and the draggable scrubber.
class _SharedTimeline extends StatefulWidget {
  const _SharedTimeline({
    required this.data,
    required this.friendName,
    required this.colors,
    required this.selectedMinutes,
    required this.mineStage,
    required this.friendStage,
    required this.moment,
    required this.onSelected,
  });

  final _ComparisonData data;
  final String friendName;
  final _CompareColors colors;
  final double selectedMinutes;
  final String mineStage;
  final String friendStage;
  final DateTime moment;
  final ValueChanged<double> onSelected;

  @override
  State<_SharedTimeline> createState() => _SharedTimelineState();
}

class _SharedTimelineState extends State<_SharedTimeline> {
  final FocusNode _focus = FocusNode(debugLabel: 'shared-night-scrubber');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _move(double minutes) {
    widget.onSelected(minutes.clamp(0.0, widget.data.axisMinutes));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(widget.selectedMinutes - 5);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(widget.selectedMinutes + 5);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final _CompareColors c = widget.colors;
    final _ComparisonData data = widget.data;
    final String readout =
        '${formatClock(widget.moment)}. You: ${widget.mineStage}. '
        '${widget.friendName}: ${widget.friendStage}';

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double total = data.axisMinutes;

        void selectFrom(double dx) {
          if (total <= 0 || width <= 0) return;
          _move(dx.clamp(0.0, width) / width * total);
        }

        return Semantics(
          container: true,
          label: 'Shared night timeline for you and ${widget.friendName}',
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails d) {
                  _focus.requestFocus();
                  selectFrom(d.localPosition.dx);
                },
                onHorizontalDragStart: (DragStartDetails d) {
                  _focus.requestFocus();
                  selectFrom(d.localPosition.dx);
                },
                onHorizontalDragUpdate: (DragUpdateDetails d) =>
                    selectFrom(d.localPosition.dx),
                child: Semantics(
                  label: 'Timeline scrubber',
                  value: readout,
                  increasedValue: 'Five minutes later',
                  decreasedValue: 'Five minutes earlier',
                  onIncrease: () => _move(widget.selectedMinutes + 5),
                  onDecrease: () => _move(widget.selectedMinutes - 5),
                  child: SizedBox(
                    height: 90,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: 64,
                          child: CustomPaint(
                            painter: _TimelinePainter(
                              data: data,
                              selectedMinutes: widget.selectedMinutes,
                              handleFill: c.surface,
                              handleBorder: c.secondary,
                              handleLine: c.secondary,
                            ),
                          ),
                        ),
                        ..._hourLabels(data, c, width),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _hourLabels(
    _ComparisonData data,
    _CompareColors c,
    double width,
  ) {
    final List<Widget> labels = <Widget>[];
    DateTime tick = data.axisStart;
    while (!tick.isAfter(data.axisEnd)) {
      final double f = data.axisMinutes <= 0
          ? 0
          : data.minutesOf(tick) / data.axisMinutes;
      final double x = f.clamp(0.0, 1.0) * width;
      labels.add(
        Positioned(
          left: (x - 22).clamp(0.0, math.max(0.0, width - 44)),
          top: 70,
          width: 44,
          child: Text(
            _hourLabel(tick),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: c.secondary,
            ),
          ),
        ),
      );
      tick = tick.add(const Duration(hours: 2));
    }
    return labels;
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.data,
    required this.selectedMinutes,
    required this.handleFill,
    required this.handleBorder,
    required this.handleLine,
  });

  final _ComparisonData data;
  final double selectedMinutes;
  final Color handleFill;
  final Color handleBorder;
  final Color handleLine;

  static const double _bandHeight = 22;
  static const double _userTop = 12;
  static const double _gap = 6;
  static const double _friendTop = _userTop + _bandHeight + _gap;
  static const double _bottom = _friendTop + _bandHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double total = data.axisMinutes;
    if (total <= 0 || size.width <= 0) return;

    double x(DateTime moment) =>
        (data.minutesOf(moment) / total).clamp(0.0, 1.0) * size.width;

    final RRect userBand = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        x(data.mine.mainStart),
        _userTop,
        x(data.mine.mainEnd),
        _userTop + _bandHeight,
      ),
      const Radius.circular(_bandHeight / 2),
    );
    final RRect friendBand = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        x(data.theirs.mainStart),
        _friendTop,
        x(data.theirs.mainEnd),
        _bottom,
      ),
      const Radius.circular(_bandHeight / 2),
    );

    canvas.drawRRect(userBand, Paint()..color = _CompareColors.userBand);
    canvas.drawRRect(friendBand, Paint()..color = _CompareColors.friendBand);

    // The shared stretch, tinted across both bands so the overlap reads as one
    // block of time rather than two separate slivers.
    final Paint overlap = Paint()
      ..color = _CompareColors.syncGreen.withValues(alpha: 0.12);
    for (final DateTimeRange range in data.overlap) {
      canvas.drawRect(
        Rect.fromLTRB(x(range.start), _userTop, x(range.end), _bottom),
        overlap,
      );
    }

    final Paint dot = Paint();
    for (final DateTime moment in data.myWakeups) {
      dot.color = _CompareColors.userDot;
      canvas.drawCircle(Offset(x(moment), _userTop + _bandHeight / 2), 3, dot);
    }
    for (final DateTime moment in data.friendWakeups) {
      dot.color = _CompareColors.friendDot;
      canvas.drawCircle(
        Offset(x(moment), _friendTop + _bandHeight / 2),
        3,
        dot,
      );
    }

    final double sx = (selectedMinutes / total).clamp(0.0, 1.0) * size.width;
    final Paint line = Paint()
      ..color = handleLine.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (double y = _userTop - 4; y < _bottom; y += 7) {
      canvas.drawLine(
        Offset(sx, y),
        Offset(sx, math.min(y + 4, _bottom)),
        line,
      );
    }
    final Offset handle = Offset(sx, 5);
    canvas.drawCircle(handle, 5, Paint()..color = handleFill);
    canvas.drawCircle(
      handle,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = handleBorder,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.data != data ||
      old.selectedMinutes != selectedMinutes ||
      old.handleFill != handleFill;
}

/// "You" and the friend, keyed by dot colour.
class _Legend extends StatelessWidget {
  const _Legend({required this.friendName, required this.colors});

  final String friendName;
  final _CompareColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const _LegendDot(color: Color(0xFF7F77DD)),
        const SizedBox(width: 5),
        _legendText('You'),
        const SizedBox(width: 14),
        const _LegendDot(color: _CompareColors.syncGreen),
        const SizedBox(width: 5),
        _legendText(friendName),
      ],
    );
  }

  Widget _legendText(String text) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: colors.secondary,
    ),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Four tinted chips, always two columns wide.
class _DeltaChips extends StatelessWidget {
  const _DeltaChips({
    required this.data,
    required this.friendName,
    required this.colors,
  });

  final _ComparisonData data;
  final String friendName;
  final _CompareColors colors;

  @override
  Widget build(BuildContext context) {
    final List<_ChipData> chips = <_ChipData>[
      _bedtimeChip(),
      _wakeChip(),
      _sleepChip(),
      _wakeupChip(),
    ];

    Widget row(_ChipData a, _ChipData b) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _DeltaChip(data: a, colors: colors),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DeltaChip(data: b, colors: colors),
            ),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        row(chips[0], chips[1]),
        const SizedBox(height: 10),
        row(chips[2], chips[3]),
      ],
    );
  }

  _ChipData _bedtimeChip() {
    final Duration difference = data.theirs.mainStart
        .difference(data.mine.mainStart)
        .abs();
    if (difference.inMinutes < 5) {
      return const _ChipData(
        icon: Icons.remove,
        value: 'Same',
        label: 'Same bedtime',
        tone: _ChipTone.blue,
      );
    }
    final bool friendLater = data.theirs.mainStart.isAfter(data.mine.mainStart);
    return _ChipData(
      icon: friendLater ? Icons.south_east : Icons.north_east,
      value: _chipDuration(difference),
      label: friendLater
          ? '$friendName slept later'
          : '$friendName slept earlier',
      tone: _ChipTone.blue,
    );
  }

  _ChipData _wakeChip() {
    final Duration difference = data.theirs.mainEnd
        .difference(data.mine.mainEnd)
        .abs();
    if (difference.inMinutes < 5) {
      return const _ChipData(
        icon: Icons.remove,
        value: 'Same',
        label: 'Same wake time',
        tone: _ChipTone.amber,
      );
    }
    final bool friendEarlier = data.theirs.mainEnd.isBefore(data.mine.mainEnd);
    return _ChipData(
      icon: friendEarlier ? Icons.north_east : Icons.south_east,
      value: _chipDuration(difference),
      label: friendEarlier
          ? '$friendName woke earlier'
          : '$friendName woke later',
      tone: _ChipTone.amber,
    );
  }

  _ChipData _sleepChip() {
    final Duration? mine = data.mine.asleep;
    final Duration? theirs = data.theirs.asleep;
    if (mine == null || theirs == null) {
      return const _ChipData(
        icon: Icons.bedtime_outlined,
        value: '—',
        label: 'Sleep not recorded',
        tone: _ChipTone.green,
      );
    }
    final Duration difference = theirs - mine;
    if (difference.inMinutes.abs() < 5) {
      return const _ChipData(
        icon: Icons.remove,
        value: 'Same',
        label: 'Same sleep',
        tone: _ChipTone.green,
      );
    }
    return _ChipData(
      icon: Icons.bedtime_outlined,
      value: _chipDuration(difference.abs()),
      label: difference.isNegative
          ? 'Less sleep than you'
          : 'More sleep than you',
      tone: _ChipTone.green,
    );
  }

  _ChipData _wakeupChip() {
    final int mine = data.myWakeups.length;
    final int theirs = data.friendWakeups.length;
    if (data.mine.spans.isEmpty || data.theirs.spans.isEmpty) {
      return const _ChipData(
        icon: Icons.bedtime_off,
        value: '—',
        label: 'Wake-ups not recorded',
        tone: _ChipTone.red,
      );
    }
    if (mine == theirs) {
      return const _ChipData(
        icon: Icons.bedtime_off,
        value: 'Same',
        label: 'Same wake-ups',
        tone: _ChipTone.red,
      );
    }
    final bool mineMore = mine > theirs;
    return _ChipData(
      icon: Icons.bedtime_off,
      value: '${(mine - theirs).abs()} more',
      label: mineMore ? 'Wake-ups for you' : 'Wake-ups for $friendName',
      tone: _ChipTone.red,
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.data, required this.colors});

  final _ChipData data;
  final _CompareColors colors;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color ink) = colors.chip(data.tone);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(data.icon, size: 16, color: ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                    letterSpacing: -0.3,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipData {
  const _ChipData({
    required this.icon,
    required this.value,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String value;
  final String label;
  final _ChipTone tone;
}

enum _ChipTone { blue, amber, green, red }

class _MutedCard extends StatelessWidget {
  const _MutedCard({required this.message, required this.colors});

  final String message;
  final _CompareColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.mutedSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: colors.secondary,
        ),
      ),
    );
  }
}

/// Everything the block draws, derived once from the pair of nights.
class _ComparisonData {
  _ComparisonData(this.mine, this.theirs) {
    final DateTime earlierBed = mine.mainStart.isBefore(theirs.mainStart)
        ? mine.mainStart
        : theirs.mainStart;
    final DateTime laterWake = mine.mainEnd.isAfter(theirs.mainEnd)
        ? mine.mainEnd
        : theirs.mainEnd;
    axisStart = _floorHour(earlierBed.subtract(const Duration(minutes: 30)));
    axisEnd = _ceilHour(laterWake.add(const Duration(minutes: 30)));
    if (!axisEnd.isAfter(axisStart)) {
      axisEnd = axisStart.add(const Duration(hours: 2));
    }

    myAsleep = _asleepRanges(mine);
    friendAsleep = _asleepRanges(theirs);
    overlap = _intersection(myAsleep, friendAsleep);
    final List<DateTimeRange> union = _merge(<DateTimeRange>[
      ...myAsleep,
      ...friendAsleep,
    ]);

    final int sharedMs = overlap.fold<int>(
      0,
      (int sum, DateTimeRange range) => sum + range.duration.inMilliseconds,
    );
    final int unionMs = union.fold<int>(
      0,
      (int sum, DateTimeRange range) => sum + range.duration.inMilliseconds,
    );
    shared = Duration(milliseconds: sharedMs);
    score = unionMs <= 0 ? 0 : (100 * sharedMs / unionMs).round().clamp(0, 100);

    myWakeups = _wakeMoments(mine);
    friendWakeups = _wakeMoments(theirs);
  }

  final NightSummary mine;
  final NightSummary theirs;

  late final DateTime axisStart;
  late final DateTime axisEnd;
  late final List<DateTimeRange> myAsleep;
  late final List<DateTimeRange> friendAsleep;
  late final List<DateTimeRange> overlap;
  late final List<DateTime> myWakeups;
  late final List<DateTime> friendWakeups;
  late final Duration shared;
  late final int score;

  double get axisMinutes => axisEnd.difference(axisStart).inSeconds / 60;

  double minutesOf(DateTime moment) =>
      moment.difference(axisStart).inSeconds / 60;

  DateTime momentAt(double minutes) =>
      axisStart.add(Duration(seconds: (minutes * 60).round()));

  /// The middle of the longest stretch both people were asleep, or the axis
  /// centre when their nights did not overlap at all.
  ///
  /// The longest *interval* rather than the midpoint of the whole overlap:
  /// a night broken by a shared awake gap would otherwise open the scrubber
  /// inside that gap, where neither person has a stage to report.
  double get defaultMinutes {
    if (overlap.isEmpty || axisMinutes <= 0) return axisMinutes / 2;
    DateTimeRange longest = overlap.first;
    for (final DateTimeRange range in overlap) {
      if (range.duration > longest.duration) longest = range;
    }
    return (minutesOf(longest.start) + minutesOf(longest.end)) / 2;
  }

  /// The stage a person was in at [moment], in the four words the card uses.
  String stageAt(NightSummary night, DateTime moment) {
    for (final SleepStageSpan span in night.spans) {
      if (moment.isBefore(span.start) || !moment.isBefore(span.end)) continue;
      final SleepStage stage = span.stage;
      if (stage == SleepStage.deep) return 'Deep';
      if (stage == SleepStage.rem) return 'REM';
      if (stage == SleepStage.light) return 'Light';
      if (stage.asleepLike) return 'Sleep';
      if (stage.awakeLike) return 'Awake';
      if (stage == SleepStage.inBed || stage == SleepStage.outOfBed) {
        return 'Awake';
      }
      return 'Not asleep';
    }
    return 'Not asleep';
  }
}

/// The intervals a person actually slept, clipped to the main session.
///
/// When a source sends no stage intervals at all, the session is used as the
/// best available window: it is the only span that source published, and
/// showing no overlap at all would be a stronger false claim than the
/// approximation.
List<DateTimeRange> _asleepRanges(NightSummary night) {
  final DateTime from = night.mainStart;
  final DateTime to = night.mainEnd;
  final List<DateTimeRange> raw = <DateTimeRange>[];
  for (final SleepStageSpan span in night.spans) {
    if (!span.stage.asleepLike) continue;
    final DateTime start = span.start.isBefore(from) ? from : span.start;
    final DateTime end = span.end.isAfter(to) ? to : span.end;
    if (end.isAfter(start)) {
      raw.add(DateTimeRange(start: start, end: end));
    }
  }
  if (raw.isEmpty && to.isAfter(from)) {
    return <DateTimeRange>[DateTimeRange(start: from, end: to)];
  }
  return _merge(raw);
}

/// Every time the person woke, using the same two-minute floor as the home
/// summary and Insights: shorter gaps are stage-boundary noise, and counting
/// them would put two dozen dots on a six-hour strip.
List<DateTime> _wakeMoments(NightSummary night) {
  final List<DateTime> moments = <DateTime>[];
  for (final SleepStageSpan span in night.spans) {
    if (span.stage != SleepStage.awake && span.stage != SleepStage.awakeInBed) {
      continue;
    }
    if (span.start.isBefore(night.mainStart)) continue;
    if (!span.start.isBefore(night.mainEnd)) continue;
    if (span.duration < const Duration(minutes: 2)) continue;
    moments.add(span.start);
  }
  moments.sort();
  return moments;
}

List<DateTimeRange> _merge(List<DateTimeRange> ranges) {
  if (ranges.isEmpty) return const <DateTimeRange>[];
  final List<DateTimeRange> sorted = List<DateTimeRange>.of(ranges)
    ..sort((DateTimeRange a, DateTimeRange b) => a.start.compareTo(b.start));
  final List<DateTimeRange> merged = <DateTimeRange>[sorted.first];
  for (int i = 1; i < sorted.length; i++) {
    final DateTimeRange current = sorted[i];
    final DateTimeRange last = merged.last;
    if (!current.start.isAfter(last.end)) {
      if (current.end.isAfter(last.end)) {
        merged[merged.length - 1] = DateTimeRange(
          start: last.start,
          end: current.end,
        );
      }
    } else {
      merged.add(current);
    }
  }
  return merged;
}

List<DateTimeRange> _intersection(
  List<DateTimeRange> a,
  List<DateTimeRange> b,
) {
  final List<DateTimeRange> out = <DateTimeRange>[];
  for (final DateTimeRange left in a) {
    for (final DateTimeRange right in b) {
      final DateTime start = left.start.isAfter(right.start)
          ? left.start
          : right.start;
      final DateTime end = left.end.isBefore(right.end) ? left.end : right.end;
      if (end.isAfter(start)) {
        out.add(DateTimeRange(start: start, end: end));
      }
    }
  }
  out.sort((DateTimeRange x, DateTimeRange y) => x.start.compareTo(y.start));
  return out;
}

DateTime _floorHour(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day, moment.hour);

DateTime _ceilHour(DateTime moment) {
  final DateTime floor = _floorHour(moment);
  if (floor == moment) return floor;
  return floor.add(const Duration(hours: 1));
}

/// "3 AM" — an axis tick, never a duration.
String _hourLabel(DateTime moment) {
  final int hour = moment.hour % 12 == 0 ? 12 : moment.hour % 12;
  return '$hour ${moment.hour < 12 ? 'AM' : 'PM'}';
}

/// "8 min" under an hour, "2h 20m" above it. Whole minutes only.
String _chipDuration(Duration value) {
  final int minutes = value.inMinutes.abs();
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

NightSummary? _nightOn(List<NightSummary> nights, DateTime date) {
  for (final NightSummary night in nights) {
    if (night.date.year == date.year &&
        night.date.month == date.month &&
        night.date.day == date.day) {
      return night;
    }
  }
  return null;
}

String _firstName(String raw) {
  final String name = displayName(raw);
  if (name.isEmpty) return 'Friend';
  return name.split(' ').first;
}

/// The section's palette, with dark equivalents for the same roles.
class _CompareColors {
  const _CompareColors({
    required this.fg,
    required this.secondary,
    required this.border,
    required this.surface,
    required this.mutedSurface,
    required this.chipBlue,
    required this.chipBlueInk,
    required this.chipAmber,
    required this.chipAmberInk,
    required this.chipGreen,
    required this.chipGreenInk,
    required this.chipRed,
    required this.chipRedInk,
  });

  static const Color syncGreen = Color(0xFF1D9E75);
  static const Color userBand = Color(0xFFAFA9EC);
  static const Color friendBand = Color(0xFF9FE1CB);
  static const Color userDot = Color(0xFF534AB7);
  static const Color friendDot = Color(0xFF0F6E56);

  final Color fg;
  final Color secondary;
  final Color border;
  final Color surface;
  final Color mutedSurface;
  final Color chipBlue;
  final Color chipBlueInk;
  final Color chipAmber;
  final Color chipAmberInk;
  final Color chipGreen;
  final Color chipGreenInk;
  final Color chipRed;
  final Color chipRedInk;

  factory _CompareColors.of(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const _CompareColors(
        fg: Color(0xFFF2F2F2),
        secondary: Color(0xFFA6A6A6),
        border: Color(0xFF2E2E2E),
        surface: Color(0xFF141414),
        mutedSurface: Color(0xFF1B1B1B),
        chipBlue: Color(0xFF13263D),
        chipBlueInk: Color(0xFF9CC9F5),
        chipAmber: Color(0xFF2F2210),
        chipAmberInk: Color(0xFFF0C57A),
        chipGreen: Color(0xFF0F2E22),
        chipGreenInk: Color(0xFF86DDB6),
        chipRed: Color(0xFF341618),
        chipRedInk: Color(0xFFF3A39C),
      );
    }
    return const _CompareColors(
      fg: Color(0xFF111111),
      secondary: Color(0xFF6B6B6B),
      border: WaterTheme.hairline,
      surface: Color(0xFFFFFFFF),
      mutedSurface: Color(0xFFF7F7F7),
      chipBlue: Color(0xFFE4EEFB),
      chipBlueInk: Color(0xFF1C4F8F),
      chipAmber: Color(0xFFFBEBD2),
      chipAmberInk: Color(0xFF8A5410),
      chipGreen: Color(0xFFDFF0E7),
      chipGreenInk: Color(0xFF176B4D),
      chipRed: Color(0xFFFBE1DF),
      chipRedInk: Color(0xFF9C2E2E),
    );
  }

  (Color, Color) chip(_ChipTone tone) => switch (tone) {
    _ChipTone.blue => (chipBlue, chipBlueInk),
    _ChipTone.amber => (chipAmber, chipAmberInk),
    _ChipTone.green => (chipGreen, chipGreenInk),
    _ChipTone.red => (chipRed, chipRedInk),
  };
}
