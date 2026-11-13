import 'strand_sleep.dart';

/// Whether a sleep source can be used on this device at all.
///
/// Four states rather than a boolean, because "not installed" and "this phone
/// has no such service" call for different sentences on a page, and a person who
/// is told the wrong one cannot act on it.
enum SleepSourceAvailability {
  /// The source exists and Strand can talk to it.
  ready,

  /// The source is a separate app on this device and is not installed. There is
  /// something the person can do about it.
  notInstalled,

  /// The device has no such service at all, so installing anything will not
  /// help. Nothing to offer and nothing to ask for.
  unsupported,

  /// The check itself failed. Not the same as unsupported: the honest thing is
  /// to say the answer is unknown rather than to guess either way.
  unknown;

  bool get usable => this == SleepSourceAvailability.ready;
}

/// One night as the source describes it, before Strand has decided anything.
///
/// A session and its stages arrive as two separate reads, so they are two
/// separate shapes. [sessionId] is what joins them: the source uses the same id
/// on the session and on every stage inside it, and that is the only link
/// between them. Holding the two apart is what stops the stages from being
/// guessed at a session rather than read from it.
class RawSleepSession {
  const RawSleepSession({
    required this.sessionId,
    required this.start,
    required this.end,
    required this.sourcePackage,
    this.sourceName = '',
    this.deviceId,
    this.metrics,
  });

  final String sessionId;
  final DateTime start;
  final DateTime end;
  final String sourcePackage;
  final String sourceName;
  final String? deviceId;
  final NightMetrics? metrics;
}

/// One stage interval as the source reports it.
class RawSleepStage {
  const RawSleepStage({
    required this.sessionId,
    required this.stage,
    required this.start,
    required this.end,
  });

  /// The parent session's id, as supplied by the source.
  final String sessionId;
  final SleepStage stage;
  final DateTime start;
  final DateTime end;
}

/// Everything Strand needs from a sleep source, and nothing about how it works.
///
/// This is the seam that makes a second integration possible. Everything above
/// it — the repository, the store, the controller, every screen — is written
/// against this interface, so adding a source means writing one class and
/// registering it. It also means none of that code can name a Health Connect
/// type, which is what keeps a platform API from spreading.
///
/// Implementations are expected to be safe to call before permission has been
/// granted, and to fail loudly rather than return an empty list when something
/// is actually wrong: an empty list and a failed read mean different things to
/// the person looking at the page.
abstract interface class SleepSourceService {
  /// The name of the source, for a person to read.
  String get displayName;

  /// Whether the source can be used on this device right now.
  Future<SleepSourceAvailability> availability();

  /// Whether Strand already has permission to read sleep.
  Future<bool> hasPermission();

  /// Asks the person for permission, and reports whether it was granted.
  ///
  /// Returning false covers both a refusal and a dismissal. The two are the
  /// same to the page — permission was not given — and only the system's own
  /// permission screen distinguishes them.
  Future<bool> requestPermission();

  /// Whether the source will serve history beyond its default window.
  ///
  /// Sources cap how far back a newly-authorised app can read, which is a
  /// deliberate privacy choice on their part. Strand asks about it rather than
  /// assuming, because the answer changes what a person's history can contain.
  Future<bool> historyAuthorized();

  /// Asks for the longer history window, and reports whether it was granted.
  Future<bool> requestHistoryAuthorization();

  /// Reads every sleep session the source holds between two moments.
  Future<List<RawSleepSession>> readSessions(DateTime from, DateTime to);

  /// Reads every sleep stage the source holds between two moments.
  ///
  /// Returned flat and tagged with [RawSleepStage.sessionId] rather than nested,
  /// because that is how the source itself reports them.
  Future<List<RawSleepStage>> readStages(DateTime from, DateTime to);

  /// Opens the platform's own screen for this source's permissions, for when the
  /// in-app request has been permanently refused and the person has to go and
  /// change it in system settings.
  Future<void> openSystemPermissions();

  /// Sends the person to the store page for the source's own app, when the
  /// source is a separate install (Health Connect is, on older Androids).
  Future<void> installSource();

  /// Opens the source's own app, where a permission can be inspected or
  /// changed when Android will not show the in-app sheet again.
  Future<void> openSourceApp();
}
