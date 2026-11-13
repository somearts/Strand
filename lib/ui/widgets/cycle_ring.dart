import 'package:flutter/material.dart';
import 'dart:math';

class CycleRing extends StatelessWidget {
  final int currentDay;
  final int cycleLength;
  final int periodDuration;
  final double size;
  final String? phaseLabel;

  const CycleRing({
    super.key,
    required this.currentDay,
    required this.cycleLength,
    required this.periodDuration,
    this.size = 260,
    this.phaseLabel,
  });

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return 'th';
    switch (n % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CycleRingPainter(
          currentDay: currentDay,
          cycleLength: cycleLength,
          periodDuration: periodDuration,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$currentDay',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 60,
                      color: Colors.black,
                      height: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 2),
                    child: Text(
                      _ordinal(currentDay),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                        fontSize: 18,
                        color: Colors.black,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'DAY OF YOUR CYCLE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 9,
                  color: Colors.black,
                  letterSpacing: 1.6,
                  height: 1,
                ),
              ),
              if (phaseLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  phaseLabel!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                    fontSize: 10,
                    color: Colors.black,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CycleRingPainter extends CustomPainter {
  final int currentDay;
  final int cycleLength;
  final int periodDuration;

  _CycleRingPainter({
    required this.currentDay,
    required this.cycleLength,
    required this.periodDuration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final stroke = 1.0;

    final basePaint = Paint()
      ..color = const Color(0xFFE6E6E6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // outer ring
    canvas.drawCircle(center, radius, basePaint);
    // inner ring
    canvas.drawCircle(center, radius - 18, basePaint);

    // period arc (menstrual days) subtle thicker
    final periodPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.butt;
    final periodSweep = (periodDuration / cycleLength) * 2 * pi;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, periodSweep, false, periodPaint);

    // progress arc to current day
    final progress = (currentDay.clamp(1, cycleLength) / cycleLength) * 2 * pi;
    final progPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - 18), -pi / 2, progress, false, progPaint);

    // current day dot
    final angle = -pi / 2 + progress;
    final dot = Offset(center.dx + (radius - 18) * cos(angle), center.dy + (radius - 18) * sin(angle));
    final dotPaint = Paint()..color = Colors.black;
    canvas.drawCircle(dot, 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _CycleRingPainter old) =>
      old.currentDay != currentDay || old.cycleLength != cycleLength || old.periodDuration != periodDuration;
}
