import 'package:flutter/material.dart';

/// The Strand wordmark, exactly as it is set on the opening screen.
///
/// The splash screen is the source of truth: Inter, weight 600, letter spacing
/// -2, lowercase, tight line height. Every other place the brand name appears
/// uses this widget so the wordmark cannot drift into a second interpretation.
/// [size] is the one thing a layout may change — the spacing is expressed in
/// logical pixels and is scaled with it so the mark keeps its proportions.
class StrandWordmark extends StatelessWidget {
  const StrandWordmark({
    super.key,
    this.size = 56,
    this.color = Colors.black,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'strand',
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: size,
        letterSpacing: -2 * (size / 56),
        color: color,
      ),
    );
  }
}
