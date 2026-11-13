/// How Strand writes a duration, a time of day, and a date.
///
/// One place, so the same number cannot be written two ways on two screens — the
/// kind of inconsistency that makes a page of real data look unreliable.
///
/// Written by hand rather than with `intl`, because every format needed here is
/// a handful of lines and adding a formatter package for them would be a
/// dependency Strand does not otherwise have.
library;

import '../strand_sleep.dart';

/// "7h 32m" — the form Strand uses wherever a length is the point.
///
/// Always the same shape, so two numbers in the same column can be compared
/// without reading either. Seconds are dropped: no sleep source reports to the
/// second at a resolution worth showing, and a trailing "0s" would imply one.
String formatDuration(Duration value) {
  // A negative duration is a data fault, not a length. Clamped rather than
  // rendered as "-1m", which would look like a measurement.
  final Duration d = value.isNegative ? Duration.zero : value;
  final int hours = d.inHours;
  final int minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// "7:56 PM" — a time of day, for the ends of a night.
///
/// Upper case meridiem. "7:56 pm" set in Inter's lowercase reads as a caption
/// typed by a computer; the capitals are what a person writes on a sleep
/// summary, and they are unambiguous next to a twelve-hour figure.
String formatClock(DateTime moment) {
  final int hour = moment.hour % 12 == 0 ? 12 : moment.hour % 12;
  final String minute = moment.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${moment.hour < 12 ? 'AM' : 'PM'}';
}

/// "7:56 PM – 4:00 AM" — the span a sleep session covered.
///
/// One string rather than two loose times on opposite sides of a line. Drawn as
/// a range because that is what it is: a person reading it is answering "when
/// did I sleep", and two timestamps with nothing joining them leave them
/// guessing which end is which.
String formatSleepPeriod(DateTime start, DateTime end) =>
    '${formatClock(start)} – ${formatClock(end)}';

/// The month names, in order. Named once so a date cannot be spelled two ways.
const List<String> kMonthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The abbreviated month names, for a caption where the full one is too long.
const List<String> kMonthNamesShort = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _weekdaysShort = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// "Thursday, 30 September 2026" — the date a night is identified by.
///
/// A **calendar date, always**.
///
/// This replaced a relative label — "Tonight", "Yesterday", "3 days ago" — which
/// was wrong in a way that mattered. A relative label is only correct relative to
/// the moment it was drawn, so the same record read as "3 days ago" on one day and
/// "4 days ago" the next; two nights could carry the same label, and a night read
/// as "Tonight" was ambiguous about whether it had happened yet. A sleep record's
/// date is what identifies it. It is the morning the session ended, because a
/// night is named for the morning it finishes — an 11pm-to-7am session is the
/// 7am morning's night, and calling it the previous day puts it beside the wrong
/// neighbour in the history.
///
/// ## [shortYear], and why it is not the same as losing the year
///
/// With `shortYear: true` this writes **"Thursday, 30 September '26"** — the last
/// two digits behind an apostrophe, never a bare "26", which would read as a page
/// number or a time.
///
/// It is opt-in and off by default because this function is used where the year is
/// the whole point. [formatSleepDateShort] records a deliberate refusal to shorten
/// the year at all, and that reasoning still holds for a *history*: a list of nights
/// has to survive being scrolled past New Year, and there is nowhere else on the row
/// for the year to be recovered from. A friend's card is not a history — it shows one
/// night, and `'26` names that night exactly as `2026` does, because no two nights in
/// one person's life are a century apart.
///
/// So the caller that wants the space asks for it, and every other caller keeps the
/// full year without having to remember anything.
String formatSleepDate(DateTime night, {bool shortYear = false}) =>
    '${_weekdays[night.weekday - 1]}, ${night.day} '
    '${kMonthNames[night.month - 1]} ${_year(night, shortYear: shortYear)}';

/// "9th November, 2026" — a plain calendar date for a page header.
///
/// The ordinal is what a person writes on a letter; the comma before the year
/// is what stops "November 2026" reading as a month and a number. No weekday:
/// the header already says the time of day, and the question this date answers
/// is "which day is this", not "which weekday".
String formatLongDate(DateTime moment) {
  final String suffix = _ordinalSuffix(moment.day);
  return '${moment.day}$suffix ${kMonthNames[moment.month - 1]}, ${moment.year}';
}

String _ordinalSuffix(int day) {
  if (day % 100 >= 11 && day % 100 <= 13) return 'th';
  return switch (day % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
}

/// The year, in full or abbreviated to its last two digits.
///
/// **Only ever abbreviated, never removed.** The century is still stated — '26 is
/// 2026 the way '86 is 1986 — so the field is still there for a reader who needs it,
/// and only two characters are spent instead of four. Anything with fewer than four
/// digits is printed as it stands, so a date outside the normal range never turns
/// into a stray apostrophe with a digit hanging off it.
String _year(DateTime night, {required bool shortYear}) {
  final String year = '${night.year}';
  if (!shortYear || year.length < 4) return year;
  return "'${year.substring(year.length - 2)}";
}

/// "Thu 30 Sep 2026" — the same date, short.
///
/// Carries the year, which [formatSleepDate] makes prominent and this keeps
/// anyway: a history that can run back past New Year has to be able to tell
/// 30 December 2025 from 30 December 2026, and dropping the year to save four
/// characters makes that impossible.
String formatSleepDateShort(DateTime night) =>
    '${_weekdaysShort[night.weekday - 1]} ${night.day} '
    '${kMonthNamesShort[night.month - 1]} ${night.year}';

/// "Today", "Yesterday", "Earlier" — where a date sits relative to now.
///
/// A **secondary** aid only, never a record's identity. The date leads and this
/// sits beside or under it, because a relative word is a helpful orientation and
/// an unreliable label.
String formatRelativeToToday(DateTime night, {DateTime? now}) {
  final DateTime today = now ?? DateTime.now();
  final int daysBack = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(night.year, night.month, night.day)).inDays;
  if (daysBack == 0) return 'Today';
  if (daysBack == 1) return 'Yesterday';
  if (daysBack > 1 && daysBack < 7) return '$daysBack days ago';
  return 'Earlier';
}

/// "27 Sep" — a short date with no year, for a caption where the year is already
/// established. Not for a record's title.
String formatShortDate(DateTime moment) =>
    '${moment.day} ${kMonthNamesShort[moment.month - 1]}';

/// How much of a session the stage data described, in one honest sentence.
///
/// Null when there are no stages at all, which is a different thing from a
/// session whose stages fall short — and the caller is expected to say *that*
/// instead. A night with no stages has nothing to qualify; a night with partial
/// stages has to say so before any percentage is shown, or the percentage reads
/// as a share of the whole night when it is a share of what was measured.
String? formatStageCoverage(Duration measured, Duration window) {
  if (measured.inMinutes <= 0) return null;
  // Within two minutes either way the stages do describe the session.
  const Duration tolerance = Duration(minutes: 2);
  if (measured >= window - tolerance && measured <= window + tolerance) {
    return null;
  }
  if (measured < window) {
    return 'Stages measured ${formatDuration(measured)} of this '
        '${formatDuration(window)} session.';
  }
  // Stages longer than the session: a source reported spans past its own window.
  // Said plainly rather than hidden, because it means the two figures came from
  // different spans and a percentage built on them is approximate.
  return 'Stages extend ${formatDuration(measured - window)} beyond the '
      'recorded session.';
}

/// A share of a whole, as a percentage string.
///
/// Null when the whole is zero, rather than "0%". A share of nothing is not a
/// measurement, and printing 0% beside an empty chart would claim a stage
/// contributed nothing when the truth is that nothing was measured.
String? formatShare(Duration part, Duration whole) {
  if (whole.inMilliseconds == 0) return null;
  return '${(part.inMilliseconds / whole.inMilliseconds * 100).round()}%';
}

/// A stage's share of a sleep session, as a percentage string.
///
/// **The divisor is always the session's own duration.** One rule, everywhere —
/// the chart, the table, a history card, the headline caption — so a percentage
/// means the same thing in every place a person can read one.
///
/// This replaces a version that quietly switched divisors: it used the session
/// window when the stages covered it and the measured stage total when they did
/// not. That was defensible arithmetic and terrible product, because the same
/// 33% meant two different things depending on a fact the reader could not see,
/// and the table beside the chart could disagree with the caption above it.
///
/// So the divisor is the window, always, and [formatStageCoverage] is what tells
/// a reader when the stages do not add up to it. The percentages then sum to less
/// than 100% for a session the source only partly described, which is the truth,
/// and the note beside them says so instead of the numbers quietly inventing the
/// missing part.
///
/// Null when the source reported no stages at all. That is a different answer
/// from "0%" and worth keeping separate: a session with no breakdown has no
/// shares to give, and a table that printed one beside a stage the source never
/// mentioned would be inventing a measurement.
///
/// The divisor, when there *is* something to divide, is always the session's own
/// duration.
///
/// Gated on [StrandSleep.hasStageFigures] rather than on `hasStageData`. A night that
/// published stage totals and no intervals has a real composition, and printing "—"
/// beside a figure the source did publish would be denying a measurement Strand is
/// holding.
String? formatStageShare(Duration part, StrandSleep night) =>
    night.hasStageFigures ? formatShare(part, night.window) : null;

/// Every stage's share of a session, rounded so the table adds up.
///
/// Rounding each share on its own is arithmetic that is right and product that
/// is wrong. A session of 310 minutes split 67 deep, 58 REM, 132 light and 53
/// awake rounds to 22%, 19%, 43% and 17% — which sum to 101%. A reader who adds
/// the column sees Strand's arithmetic fail by a whole percent and has no way to
/// know whether a stage was over- or under-counted. On a page whose entire claim
/// is that these numbers came from a real measurement, that is the first thing
/// that should not happen.
///
/// So the rounding is allocated rather than independent: each stage gets its
/// nearest whole percent, and the leftover percent or two are handed to the
/// stages with the largest fractional remainders — the same method a
/// proportional-representation table uses, and the one that makes the parts sum
/// to the whole.
///
/// This only applies when the stages actually cover the session. When they do
/// not, the shares are honestly short of 100% and must stay short: the missing
/// time is real and [formatStageCoverage] is what accounts for it. Fabricating a
/// percent to make a column tidy would be inventing a measurement.
///
/// Empty when the source reported no stages, for the same reason
/// [formatStageShare] returns null: there are no shares to give.
Map<SleepStage, String> formatStageShares(StrandSleep night) {
  // `hasStageFigures`, not `hasStageData`: see [formatStageShare]. A friend's
  // published totals are stage figures even though they are not intervals, and the
  // table beside them has to list them.
  if (!night.hasStageFigures) return const <SleepStage, String>{};
  final int window = night.window.inMilliseconds;
  if (window <= 0) return const <SleepStage, String>{};

  final Map<SleepStage, int> parts = <SleepStage, int>{
    for (final SleepStage s in night.stagesPresent)
      s: (night.timeByStage[s]!.inMilliseconds * 100 / window).round(),
  };

  // Only reconcile when the shares describe the whole session. Otherwise the
  // shortfall is the point.
  if (night.stagesCoverWholeNight) {
    int total = parts.values.fold(0, (int a, int b) => a + b);
    while (total > 100) {
      // Take a percent back from whichever stage rounded up hardest.
      final Iterable<SleepStage> eligible = parts.keys.where(
        (SleepStage s) => parts[s]! > 0,
      );
      if (eligible.isEmpty) break;
      final SleepStage worst = eligible.reduce(
        (SleepStage a, SleepStage b) =>
            _remainder(night, a, window) > _remainder(night, b, window) ? a : b,
      );
      parts[worst] = parts[worst]! - 1;
      total -= 1;
    }
    while (total < 100) {
      // And hand one to whichever stage lost the most in rounding.
      final SleepStage best = parts.keys.reduce(
        (SleepStage a, SleepStage b) =>
            _remainder(night, a, window) < _remainder(night, b, window) ? a : b,
      );
      parts[best] = parts[best]! + 1;
      total += 1;
    }
  }

  return <SleepStage, String>{
    for (final MapEntry<SleepStage, int> e in parts.entries)
      e.key: '${e.value}%',
  };
}

/// How far [stage] was rounded away from its exact share, as a fraction.
///
/// The tie-breaker for [formatStageShares]: the stage whose exact percentage
/// sat nearest the top of its interval gained most from rounding up, so it is
/// the one that should lose a percent when the column has to come down.
double _remainder(StrandSleep night, SleepStage stage, int windowMs) {
  final double exact =
      night.timeByStage[stage]!.inMilliseconds * 100 / windowMs;
  return exact - exact.floorToDouble();
}
