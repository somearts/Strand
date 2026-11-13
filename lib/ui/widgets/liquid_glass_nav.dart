import 'dart:ui';

import 'package:flutter/material.dart';

/// A floating, translucent "liquid glass" navigation capsule.
///
/// The widget must be placed in a [Stack] *above* the scrolling content so the
/// clipped [BackdropFilter] can sample and blur whatever is painted behind it.
///
/// The surface is deliberately not opaque. The blur does the work of softening
/// the page underneath; the white tint is only strong enough to keep the black
/// labels legible over whatever happens to be scrolling past.
class LiquidGlassNav extends StatelessWidget {
  const LiquidGlassNav({
    super.key,
    required this.index,
    required this.labels,
    required this.pastels,
    required this.onSelected,
    this.radius = 38,
  });

  final int index;
  final List<String> labels;
  final List<Color> pastels;
  final ValueChanged<int> onSelected;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);

    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        // A wide, faint shadow under the capsule. Not a drop shadow on a card:
        // only enough to separate glass from page, so the bar reads as lifted
        // rather than pasted on.
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.09),
            blurRadius: 26,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          // Real backdrop blur, not a simulated one. 20 is heavy enough that
          // long paragraphs passing underneath turn into soft colour rather
          // than legible, distracting shapes.
          filter: ImageFilter.blur(
            sigmaX: 20,
            sigmaY: 20,
            tileMode: TileMode.clamp,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: r,
              // Translucent frosted white. Kept neutral so the blurred colours
              // behind it stay vivid; Flutter's ImageFilter exposes blur but no
              // colour matrix, so tinting is the only lever over the backdrop.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Colors.white.withValues(alpha: 0.62),
                  Colors.white.withValues(alpha: 0.46),
                ],
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(labels.length, (i) {
                      final selected = i == index;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Semantics(
                          button: true,
                          selected: selected,
                          label: labels[i],
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelected(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                // The active pill is glass too: the same pastel,
                                // now translucent, with a top-lit sheen instead
                                // of a flat fill.
                                gradient: selected
                                    ? LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: <Color>[
                                          pastels[i].withValues(alpha: 0.62),
                                          pastels[i].withValues(alpha: 0.38),
                                        ],
                                      )
                                    : null,
                                color: selected ? null : Colors.transparent,
                                border: selected
                                    ? Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.65,
                                        ),
                                        width: 0.8,
                                      )
                                    : null,
                              ),
                              child: Text(
                                labels[i],
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 9,
                                  letterSpacing: 1.2,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // The rim lives above the labels as paint only, never as a hit
                // target.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GlassRimPainter(radius: radius),
                    ),
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

/// The lit edge of the glass.
///
/// A single stroke cannot be bright at the top and dim at the bottom, so the
/// border is painted with a vertical gradient shader: almost white along the
/// top rim, fading to nearly nothing underneath, the way light catches a real
/// glass droplet. A second, inset stroke supplies the faint inner highlight.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;

    final RRect outer = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius - 0.5),
    );
    final Paint rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.white.withValues(alpha: 0.95),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.14),
        ],
        stops: const <double>[0.0, 0.35, 1.0],
      ).createShader(rect);
    canvas.drawRRect(outer, rim);

    final RRect inner = RRect.fromRectAndRadius(
      rect.deflate(2.0),
      Radius.circular(radius - 2.0),
    );
    final Paint highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const <double>[0.0, 0.22, 0.55],
      ).createShader(rect);
    canvas.drawRRect(inner, highlight);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
