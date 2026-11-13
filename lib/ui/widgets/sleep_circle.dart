import 'package:flutter/material.dart';
import 'dart:math';

class SleepCircleSegment {
  const SleepCircleSegment({required this.color, required this.fraction});
  final Color color;
  final double fraction; // 0..1 of full circle
}

class SleepCircle extends StatelessWidget {
  const SleepCircle({
    super.key,
    this.segments = const [],
    this.centerLabel = '—',
    this.centerCaption = 'NO SLEEP RECORDED',
    this.size = 280,
  });

  final List<SleepCircleSegment> segments;
  final String centerLabel;
  final String centerCaption;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SleepCirclePainter(segments: segments),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 40,
                  color: Colors.black,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                centerCaption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: Colors.black,
                  letterSpacing: 1.4,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleepCirclePainter extends CustomPainter {
  _SleepCirclePainter({required this.segments});
  final List<SleepCircleSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final stroke = 3.0;

    final basePaint = Paint()
      ..color = const Color(0xFFE6E6E6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, basePaint);

    double start = -pi / 2;
    for (final seg in segments) {
      if (seg.fraction <= 0) continue;
      final sweep = seg.fraction * 2 * pi;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SleepCirclePainter old) => old.segments != segments;
}
