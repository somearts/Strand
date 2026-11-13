import 'package:flutter/material.dart';

import '../health/strand_sleep.dart';

/// The restrained palette used for sleep stages across the app.
///
/// One definition so a ring, a legend dot, a breakdown card and a chart segment
/// cannot drift into four slightly different blues. Everything here is a solid
/// colour on white; no gradients, no transparency, no decorative noise.
abstract final class SleepPalette {
  /// The total figure in Insights. The home rings no longer draw a total ring:
  /// the total is the central number, not a circle.
  static const Color total = Color(0xFF111111);

  /// Soft sage. Deep sleep reads as the calmest, steadiest stage.
  static const Color deep = Color(0xFF9CC7AC);

  /// Soft butter.
  static const Color rem = Color(0xFFE3C77E);

  /// Soft sky.
  static const Color light = Color(0xFF9FC2E0);

  /// Soft apricot — the warm complement to the three cool pastels.
  static const Color awake = Color(0xFFE2B29D);

  /// Recorded sleep the source did not name a stage for.
  static const Color unspecified = Color(0xFFCFCAC0);

  /// The neutral background track behind every ring and chart bar.
  static const Color track = Color(0xFFEDEDED);

  /// A stage's colour, or a neutral for anything Strand does not draw.
  static Color forStage(SleepStage stage) => switch (stage) {
    SleepStage.deep => deep,
    SleepStage.rem => rem,
    SleepStage.light || SleepStage.asleep => light,
    SleepStage.awake ||
    SleepStage.awakeInBed ||
    SleepStage.outOfBed => awake,
    _ => unspecified,
  };
}
