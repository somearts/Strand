import 'package:flutter/material.dart';

import '../../health/analytics/sleep_analytics.dart';

/// The four tones used by the Home rings and the breakdown beneath them.
///
/// Monochrome by design: the rings are an identity, not a chart. They always
/// draw as complete circles, so no stage can look "unfinished" just because it
/// is shorter than another.
abstract final class RingTones {
  /// Total sleep, the outermost and darkest circle.
  static const Color total = Color(0xFF161616);
  static const Color deep = Color(0xFF4C4C4C);
  static const Color rem = Color(0xFF868686);
  static const Color light = Color(0xFFBFBFBF);

  /// Used only when the night has no figures at all.
  static const Color empty = Color(0xFFE4E4E4);
}

/// The sleep figures the rings and the breakdown need, in one place.
class SleepRingData {
  const SleepRingData({
    required this.totalSleep,
    required this.timeInBed,
    this.deep,
    this.rem,
    this.light,
    this.awake,
  });

  const SleepRingData.unavailable()
    : totalSleep = null,
      timeInBed = null,
      deep = null,
      rem = null,
      light = null,
      awake = null;

  final Duration? totalSleep;
  final Duration? timeInBed;
  final Duration? deep;
  final Duration? rem;
  final Duration? light;
  final Duration? awake;

  factory SleepRingData.fromNight(NightSummary? night) {
    if (night == null) return const SleepRingData.unavailable();
    return SleepRingData(
      totalSleep: night.asleep,
      timeInBed: night.timeInBed,
      deep: night.deep,
      rem: night.rem,
      light: night.light,
      awake: night.awake,
    );
  }

  bool get hasTotal => totalSleep != null && totalSleep! > Duration.zero;

  /// A stage's share of total sleep, for the quiet percentage beside it.
  double? shareOf(Duration? part) {
    final Duration? total = totalSleep;
    if (total == null || part == null || total <= Duration.zero) return null;
    return (part.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Four complete, thin concentric outlines with the night's total sleep at the
/// centre.
///
/// Deliberately inert: nothing here responds to a tap, because tapping a ring
/// was only ever a way to make a healthy night look like a failed target.
class ConcentricSleepRings extends StatelessWidget {
  const ConcentricSleepRings({
    super.key,
    required this.data,
    this.size = 320,
    this.centerLabel = '—',
    this.centerCaption = 'TOTAL SLEEP',
  });

  final SleepRingData data;
  final double size;
  final String centerLabel;
  final String centerCaption;

  static const double _stroke = 1.6;
  static const double _gap = 10.0;

  static const List<Color> _colors = <Color>[
    RingTones.total,
    RingTones.deep,
    RingTones.rem,
    RingTones.light,
  ];

  List<double> get _radii {
    final List<double> radii = <double>[];
    double radius = size / 2 - _stroke / 2;
    radii.add(radius);
    for (int i = 1; i < _colors.length; i++) {
      radius -= _stroke + _gap;
      radii.add(radius);
    }
    return radii;
  }

  @override
  Widget build(BuildContext context) {
    final List<double> radii = _radii;
    final double innerEdge = radii.last - _stroke / 2;
    final List<Color> colors = data.hasTotal
        ? _colors
        : _colors.map((Color _) => RingTones.empty).toList(growable: false);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: _ConcentricRingsPainter(
              radii: radii,
              stroke: _stroke,
              colors: colors,
            ),
          ),
          SizedBox(
            width: (innerEdge * 2) - 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    centerLabel,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: (size * 0.21).clamp(30.0, 46.0),
                      color: Colors.black,
                      height: 1,
                      letterSpacing: -1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  centerCaption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: (size * 0.032).clamp(8.0, 10.0),
                    color: Colors.black,
                    letterSpacing: 1.8,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcentricRingsPainter extends CustomPainter {
  _ConcentricRingsPainter({
    required this.radii,
    required this.stroke,
    required this.colors,
  });

  final List<double> radii;
  final double stroke;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < radii.length; i++) {
      final Paint paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..isAntiAlias = true;
      canvas.drawCircle(center, radii[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConcentricRingsPainter old) {
    if (old.stroke != stroke || old.colors.length != colors.length) {
      return true;
    }
    for (int i = 0; i < colors.length; i++) {
      if (old.colors[i] != colors[i] || old.radii[i] != radii[i]) return true;
    }
    return false;
  }
}
