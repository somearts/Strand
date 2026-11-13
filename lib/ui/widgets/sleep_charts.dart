import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../health/analytics/sleep_analytics.dart';
import '../../health/presentation/sleep_format.dart';
import '../sleep_colors.dart';

const TextStyle _axisStyle = TextStyle(
  fontFamily: 'Inter',
  fontSize: 9,
  fontWeight: FontWeight.w600,
  color: Colors.black,
  height: 1,
);

const TextStyle _noteStyle = TextStyle(
  fontFamily: 'Inter',
  fontSize: 10,
  fontWeight: FontWeight.w500,
  color: Colors.black,
  height: 1.4,
);

/// One date's value. Null is a gap, not a zero: the line breaks there instead
/// of falling to the baseline and inventing a night with no sleep.
class TrendPoint {
  const TrendPoint({required this.date, required this.value});

  final DateTime date;
  final double? value;
}

/// A minimal line chart for one metric over the selected nights.
///
/// Index-spaced rather than time-spaced: on a phone a three-week gap and a
/// one-night gap are equally unreadable as horizontal distance, and equal
/// spacing keeps every recorded night visible. The first and last dates anchor
/// the axis, and missing nights leave a break in the line.
class SleepLineChart extends StatelessWidget {
  const SleepLineChart({
    super.key,
    required this.points,
    required this.color,
    this.average,
    this.height = 150,
    this.formatAxis = _formatHours,
  });

  final List<TrendPoint> points;
  final Color color;

  /// Optional dashed average line, in the same unit as the values.
  final double? average;

  final double height;
  final String Function(double value) formatAxis;

  @override
  Widget build(BuildContext context) {
    final bool hasValue = points.any((TrendPoint p) => p.value != null);
    if (!hasValue) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LineChartPainter(
          points: points,
          color: color,
          average: average,
          formatAxis: formatAxis,
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.color,
    required this.average,
    required this.formatAxis,
  });

  final List<TrendPoint> points;
  final Color color;
  final double? average;
  final String Function(double) formatAxis;

  static const double _left = 34;
  static const double _right = 6;
  static const double _top = 8;
  static const double _bottom = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final List<double> values = <double>[
      for (final TrendPoint p in points)
        if (p.value != null) p.value!,
    ];
    if (values.isEmpty) return;

    double min = values.reduce(math.min);
    double max = values.reduce(math.max);
    // A flat series still needs a band to sit in.
    if ((max - min).abs() < 1) {
      min -= 30;
      max += 30;
    }
    final double rawRange = max - min;
    final double pad = rawRange * 0.14;
    min = math.max(0, min - pad);
    max = max + pad;

    final Rect plot = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );

    double xFor(int index) {
      if (points.length <= 1) return plot.center.dx;
      return plot.left + plot.width * index / (points.length - 1);
    }

    double yFor(double value) {
      final double t = (value - min) / (max - min);
      return plot.bottom - t * plot.height;
    }

    // Three quiet guides, labelled at the left edge in solid black.
    final Paint guide = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 0.8;
    final Paint guideStrong = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..strokeWidth = 0.9;
    for (int i = 0; i < 3; i++) {
      final double value = min + (max - min) * (i / 2);
      final double y = yFor(value);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        i == 0 ? guideStrong : guide,
      );
      _label(
        canvas,
        formatAxis(value),
        Offset(plot.left - 6, y),
        alignRight: true,
      );
    }

    // Optional average line.
    if (average != null && average! >= min && average! <= max) {
      final double y = yFor(average!);
      final Paint dash = Paint()
        ..color = const Color(0xFF6A6A6A)
        ..strokeWidth = 1;
      double x = plot.left;
      while (x < plot.right) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, plot.right), y), dash);
        x += 8;
      }
    }

    // The series, broken at gaps.
    final Paint line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path();
    bool drawing = false;
    final List<Offset> dots = <Offset>[];

    for (int i = 0; i < points.length; i++) {
      final double? value = points[i].value;
      if (value == null) {
        drawing = false;
        continue;
      }
      final Offset point = Offset(xFor(i), yFor(value));
      if (!drawing) {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
      dots.add(point);
    }
    canvas.drawPath(path, line);

    if (points.length <= 16) {
      final Paint dot = Paint()..color = color;
      for (final Offset point in dots) {
        canvas.drawCircle(point, 2.3, dot);
      }
    }

    // First and last date, in solid black.
    if (points.isNotEmpty) {
      _label(
        canvas,
        formatShortDate(points.first.date),
        Offset(plot.left, size.height - 12),
      );
      _label(
        canvas,
        formatShortDate(points.last.date),
        Offset(plot.right, size.height - 12),
        alignRight: true,
      );
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool alignRight = false,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: _axisStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final double dx = alignRight ? anchor.dx - painter.width : anchor.dx;
    final double dy = anchor.dy - painter.height / 2;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.points != points ||
      old.color != color ||
      old.average != average;
}

/// Stacked nightly (or bucketed) stage durations.
class StageTrendChart extends StatelessWidget {
  const StageTrendChart({
    super.key,
    required this.buckets,
    this.height = 150,
  });

  final List<StageBucket> buckets;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty || !buckets.any((StageBucket b) => b.hasAny)) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _StageChartPainter(buckets)),
    );
  }
}

class _StageChartPainter extends CustomPainter {
  _StageChartPainter(this.buckets);

  final List<StageBucket> buckets;

  static const double _left = 34;
  static const double _right = 6;
  static const double _top = 8;
  static const double _bottom = 22;

  @override
  void paint(Canvas canvas, Size size) {
    double maxTotal = 0;
    for (final StageBucket bucket in buckets) {
      double total = 0;
      if (bucket.deep != null) total += bucket.deep!.inMinutes.toDouble();
      if (bucket.rem != null) total += bucket.rem!.inMinutes.toDouble();
      if (bucket.light != null) total += bucket.light!.inMinutes.toDouble();
      if (total > maxTotal) maxTotal = total;
    }
    if (maxTotal <= 0) return;

    final Rect plot = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );

    final Paint guide = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = const Color(0xFFBDBDBD)
        ..strokeWidth = 0.9,
    );
    canvas.drawLine(
      Offset(plot.left, plot.top),
      Offset(plot.right, plot.top),
      guide,
    );
    _label(canvas, _formatHours(maxTotal), Offset(plot.left - 6, plot.top), alignRight: true);
    _label(canvas, '0', Offset(plot.left - 6, plot.bottom), alignRight: true);

    final double slot = plot.width / buckets.length;
    final double barWidth = math.min(11.0, math.max(2.0, slot * 0.62));

    for (int i = 0; i < buckets.length; i++) {
      final StageBucket bucket = buckets[i];
      if (!bucket.hasAny) continue;
      final double x = plot.left + slot * (i + 0.5);
      double bottom = plot.bottom;

      void segment(Duration? duration, Color color) {
        if (duration == null || duration <= Duration.zero) return;
        final double h = plot.height * (duration.inMinutes.toDouble() / maxTotal);
        final Rect rect = Rect.fromLTRB(
          x - barWidth / 2,
          bottom - h,
          x + barWidth / 2,
          bottom,
        );
        canvas.drawRect(rect, Paint()..color = color);
        bottom -= h;
      }

      segment(bucket.deep, SleepPalette.deep);
      segment(bucket.rem, SleepPalette.rem);
      segment(bucket.light, SleepPalette.light);
    }

    _label(
      canvas,
      formatShortDate(buckets.first.start),
      Offset(plot.left, size.height - 12),
    );
    _label(
      canvas,
      formatShortDate(buckets.last.end),
      Offset(plot.right, size.height - 12),
      alignRight: true,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool alignRight = false,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: _axisStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final double dx = alignRight ? anchor.dx - painter.width : anchor.dx;
    final double dy = anchor.dy - painter.height / 2;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _StageChartPainter old) =>
      old.buckets != buckets;
}

/// A horizontal range showing how much two clock times moved.
///
/// Bedtime and wake-up are times of day, not magnitudes, so a line chart is the
/// wrong shape: it would draw a jump from 11:50 PM to 12:10 AM as a 23-hour
/// collapse. A range with an average tick says "these nights sat between here
/// and here, centred here", which is what consistency means.
class ConsistencyBar extends StatelessWidget {
  const ConsistencyBar({
    super.key,
    required this.label,
    required this.minimum,
    required this.average,
    required this.maximum,
    required this.spreadMinutes,
    required this.domainStart,
    required this.domainEnd,
    this.height = 68,
  });

  final String label;

  /// Coordinates in minutes, already placed on the domain's clock.
  final double? minimum;
  final double? average;
  final double? maximum;

  /// Circular standard deviation in minutes, or null when unknown.
  final double? spreadMinutes;

  final double domainStart;
  final double domainEnd;
  final double height;

  String get _summary {
    if (average == null) return 'No data';
    final String mean = formatClock(_clock(average!));
    final String spread = spreadMinutes == null
        ? ''
        : '  ·  ±${spreadMinutes!.round()}m';
    return '$mean$spread';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasRange = minimum != null && maximum != null && average != null;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: Colors.black,
                  ),
                ),
              ),
              Text(
                _summary,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasRange)
            const Text(
              'Not enough nights to show a range.',
              style: _noteStyle,
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double width = constraints.maxWidth;
                double fraction(double value) => ((value - domainStart) /
                        (domainEnd - domainStart))
                    .clamp(0.0, 1.0);
                final double left = fraction(minimum!);
                final double right = fraction(maximum!);
                final double mean = fraction(average!);

                return SizedBox(
                  height: 22,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        height: 2,
                        width: width,
                        color: SleepPalette.track,
                      ),
                      Positioned(
                        left: left * width,
                        width: math.max(2, (right - left) * width),
                        child: Container(height: 2, color: Colors.black),
                      ),
                      Positioned(
                        left: (mean * width).clamp(0, width - 2),
                        child: Container(width: 2, height: 12, color: Colors.black),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (hasRange)
            Row(
              children: <Widget>[
                Text(
                  formatClock(_clock(minimum!)),
                  style: _noteStyle,
                ),
                const Spacer(),
                Text(
                  formatClock(_clock(maximum!)),
                  style: _noteStyle,
                ),
              ],
            ),
        ],
      ),
    );
  }

  DateTime _clock(double minutes) {
    final int normalized = minutes.round() % 1440;
    return DateTime(2000, 1, 1, normalized ~/ 60, normalized % 60);
  }
}

/// A labelled share bar for one stage's average percentage.
class StageShareBar extends StatelessWidget {
  const StageShareBar({
    super.key,
    required this.label,
    required this.color,
    required this.share,
    this.percent,
    required this.detail,
  });

  final String label;
  final Color color;

  /// 0..1, or null when the source did not report this stage.
  final double? share;

  /// Whole percentage to display instead of rounding [share] alone.
  ///
  /// The three named stages are rounded together by the analytics layer so
  /// their labels total 100%; this is that figure, and the bar uses it too so
  /// the label and the fill cannot disagree.
  final int? percent;

  /// e.g. "1h 52m average" or "Unavailable".
  final String detail;

  @override
  Widget build(BuildContext context) {
    final int? shown = percent ??
        (share == null ? null : (share! * 100).round());
    final double? fill = shown == null ? null : shown / 100; 
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              Text(
                shown == null ? '—' : '$shown%',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              final double filled = fill == null
                  ? 0
                  : (fill.clamp(0.0, 1.0)) * width;
              return SizedBox(
                height: 3,
                width: width,
                child: Stack(
                  children: <Widget>[
                    Container(color: SleepPalette.track),
                    if (filled > 0)
                      Container(width: filled, color: color),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: _noteStyle,
          ),
        ],
      ),
    );
  }
}

/// Small coloured dot used in chart legends.
class StageLegendDot extends StatelessWidget {
  const StageLegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}

String _formatHours(double minutes) {
  if (minutes <= 0) return '0h';
  final int hours = minutes ~/ 60;
  return '${hours}h';
}
