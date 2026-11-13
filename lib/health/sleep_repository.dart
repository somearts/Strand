import 'sleep_source_service.dart';
import 'sleep_store.dart';
import 'strand_sleep.dart';

/// Why a sync ended, in terms a page can act on.
enum SleepSyncOutcome {
  /// Nights were added.
  added,

  /// Nights already stored were revised by the source.
  updated,

  /// The read worked and there was nothing new. Not a failure.
  nothingNew,

  /// The source has no sleep at all in the window asked about.
  noData,

  /// The source is not usable on this device.
  unavailable,

  /// Permission has not been granted.
  notPermitted,

  /// The read itself failed.
  failed,
}

/// What a sync did, in enough detail to say so out loud.
class SleepSyncReport {
  const SleepSyncReport({
    required this.outcome,
    required this.added,
    required this.updated,
    required this.unchanged,
    this.window,
    this.unattachedStages = 0,
    this.message,
  });

  final SleepSyncOutcome outcome;
  final int added;
  final int updated;

  /// Nights the read returned that Strand already had, unchanged. Not shown to
  /// a person — it is the proof that a second sync did not duplicate anything.
  final int unchanged;

  /// The span that was read, so a log or a test can prove an incremental sync
  /// really was incremental.
  final (DateTime from, DateTime to)? window;

  /// Stage intervals that arrived with no session to attach to.
  final int unattachedStages;

  /// Why a sync failed, when it did. Null otherwise, because "it failed" and
  /// "here is what failed" are different messages.
  final String? message;

  bool get changedAnything => added > 0 || updated > 0;
}

/// A source of sleep, normalised and stored.
///
/// One repository over any number of [SleepSourceService]s, which is what makes
/// a second integration additive rather than a second code path. The services
/// are read in sequence and their records merged by id, so a night reported by
/// two of them is one night rather than two.
class SleepRepository {
  SleepRepository({
    required List<SleepSourceService> sources,
    required this.store,
    this.lookback = const Duration(days: 400),
    this.overlap = const Duration(days: 2),
  }) : _sources = List<SleepSourceService>.unmodifiable(sources);

  final List<SleepSourceService> _sources;

  /// Where the nights are kept. Public so a caller can erase them, which is a
  /// thing a person is entitled to do and which should not require reaching
  /// into the repository.
  final SleepStore store;

  /// The configured sources, so a caller can ask one directly about itself —
  /// used to tell "no such service on this phone" from "not installed", which
  /// needs each source's own answer rather than the merged one.
  List<SleepSourceService> get sources => _sources;

  /// How far back a first sync reaches, when the source will let it.
  ///
  /// Long, because a person opening Insights for the first time wants their
  /// history rather than a fortnight of it. It is a request, not a promise:
  /// Health Connect caps how far back a newly-authorised app may read, and
  /// Strand asks for the longer window separately rather than pretending this
  /// number is what they will get.
  final Duration lookback;

  /// How far *before* the watermark a later sync re-reads.
  ///
  /// A small overlap, and not merely an optimisation. Health Connect has no
  /// query for "records changed since X", and a night can be written or
  /// revised after the fact — a wearable finishing a session it started
  /// yesterday, a source that backfills stages once the phone charges. Starting
  /// exactly at the watermark would miss those forever. Re-reading two days is
  /// cheap, and because upsert is keyed on id it cannot produce duplicates.
  final Duration overlap;

  /// Points the store at an account, so every read and write below is filed under it.
  ///
  /// **Called only from [SleepController.bindUser]**, which is the single place that
  /// knows when the account has changed. Passing it through rather than reaching for the
  /// store directly keeps the moment of rebinding in one file — and rebinding is the
  /// moment that matters, because a store pointed at the wrong account is how a deleted
  /// account's nights came back.
  void bindUser(String? uid) => store.bindUser(uid);

  Future<SleepIndex> load() => store.read();

  Future<DateTime?> lastSync() => store.readLastSync();

  /// The first source that can be used at all, or null if none can.
  Future<SleepSourceService?> usableSource() async {
    for (final SleepSourceService source in _sources) {
      if ((await source.availability()).usable) return source;
    }
    return null;
  }

  /// Reads from every usable source and merges the result into the store.
  ///
  /// Safe to run as often as one likes: records are keyed by id, so a second run
  /// over the same nights reports them as unchanged and writes nothing.
  ///
  /// A source that is unusable or unpermitted is skipped and does not stop the
  /// others, so one missing integration cannot hide the data another has.
  ///
  /// [forceFull] re-reads the whole [lookback] instead of starting from the
  /// watermark. It exists for one moment: just after a person grants Health
  /// Connect's longer history window, the nights that window makes newly
  /// reachable are all *behind* the watermark, so an incremental read would
  /// never find them.
  Future<SleepSyncReport> sync({DateTime? now, bool forceFull = false}) async {
    final DateTime at = now ?? DateTime.now();
    SleepIndex index = await store.read();
    final DateTime? mark = index.watermark;

    // An incremental sync when there is something to be incremental about, and
    // the full lookback otherwise. The window always ends "now" rather than at
    // the watermark, so a night in progress — or one written since last time —
    // is picked up.
    final DateTime wanted;
    if (forceFull || mark == null) {
      wanted = at.subtract(lookback);
    } else {
      wanted = mark.subtract(overlap);
    }
    // A watermark at or past "now" would produce an empty window, which some
    // backends treat as no range at all and return nothing for. Widening it
    // keeps the read well-formed rather than silently empty.
    final DateTime from = wanted.isBefore(at) ? wanted : at.subtract(overlap);

    int added = 0;
    int updated = 0;
    int unchanged = 0;
    int orphanStages = 0;
    bool readAnything = false;
    bool anyUsable = false;
    bool allUnpermitted = true;
    String? failure;

    for (final SleepSourceService source in _sources) {
      if (!(await source.availability()).usable) continue;
      anyUsable = true;

      if (!await source.hasPermission()) continue;
      allUnpermitted = false;

      try {
        // Empty rather than skipped, so the rest of this loop does not have to
        // know whether sessions were asked for. An empty list and a
        // declined request reach the same place, which is the point.
        final List<RawSleepSession> sessions = readSessions
            ? await source.readSessions(from, at)
            : const <RawSleepSession>[];
        final List<RawSleepStage> stages = readStageDetail
            ? await source.readStages(from, at)
            : const <RawSleepStage>[];
        if (sessions.isNotEmpty || stages.isNotEmpty) readAnything = true;

        // Stages first, grouped by the session id they were reported under.
        // This is the rejoin described in HealthConnectSleepSource: the source
        // splits one night across two reads and the id is the only thing that
        // connects them.
        final Map<String, List<SleepStageSpan>> bySession =
            <String, List<SleepStageSpan>>{};
        for (final RawSleepStage stage in stages) {
          bySession
              .putIfAbsent(stage.sessionId, () => <SleepStageSpan>[])
              .add(
                SleepStageSpan(
                  stage: stage.stage,
                  start: stage.start,
                  end: stage.end,
                ),
              );
        }

        // Which of those ids a session in *this* window actually claimed.
        // Anything else is a stage Strand cannot place, and it is counted
        // rather than attached: a stage belongs to one specific night, and
        // guessing which would silently corrupt that night's stage figures.
        final Set<String> claimed = sessions
            .map((RawSleepSession s) => s.sessionId)
            .toSet();
        orphanStages += bySession.keys
            .where((String id) => !claimed.contains(id))
            .length;

        for (final RawSleepSession session in sessions) {
          final String id = _idFor(source, session.sessionId);
          final StrandSleep record = StrandSleep(
            id: id,
            start: session.start,
            end: session.end,
            sourcePackage: session.sourcePackage,
            sourceName: session.sourceName,
            deviceId: session.deviceId,
            stages: bySession[session.sessionId] ?? const <SleepStageSpan>[],
            metrics: session.metrics,
            importedAt: at,
          );

          final SleepUpsert result = index.upsert(record);
          index = result.index;
          switch (result.outcome) {
            case SleepUpsertOutcome.added:
              added++;
            case SleepUpsertOutcome.updated:
              updated++;
            case SleepUpsertOutcome.unchanged:
              unchanged++;
          }
        }

        // Stages whose session was not in this window are counted above, before
        // the session loop, so nothing is attached on a guess.
      } catch (error) {
        // One source failing must not discard what another gave, so this is
        // remembered and the loop continues.
        failure ??= '$error';
      }
    }

    final SleepSyncOutcome outcome;
    if (!anyUsable) {
      outcome = SleepSyncOutcome.unavailable;
    } else if (allUnpermitted) {
      outcome = SleepSyncOutcome.notPermitted;
    } else if (failure != null && !readAnything) {
      outcome = SleepSyncOutcome.failed;
    } else if (added > 0) {
      outcome = SleepSyncOutcome.added;
    } else if (updated > 0) {
      outcome = SleepSyncOutcome.updated;
    } else if (readAnything) {
      outcome = SleepSyncOutcome.nothingNew;
    } else {
      outcome = SleepSyncOutcome.noData;
    }

    // Written whenever the read succeeded, even with nothing new: a sync that
    // worked and found nothing is still the moment the person last checked, and
    // the Health Data page should say so.
    if (outcome != SleepSyncOutcome.failed &&
        outcome != SleepSyncOutcome.unavailable) {
      await store.write(index, lastSync: at);
    }

    return SleepSyncReport(
      outcome: outcome,
      added: added,
      updated: updated,
      unchanged: unchanged,
      window: (from, at),
      unattachedStages: orphanStages,
      message: failure,
    );
  }

  /// A record's identity: the source, then the source's own id for it.
  ///
  /// Namespaced by source so two integrations that happen to hand out the same
  /// id for different nights cannot collide into one record. The id is stable,
  /// which is what makes [SleepIndex.upsert] idempotent.
  static String _idFor(SleepSourceService source, String sessionId) =>
      '${source.displayName}:$sessionId';

  /// Empties the store. The repository's own forget, so "erase your data" does
  /// not have to know which store it is.
  Future<void> clear() => store.clear();

  /// Whether to ask the source for the per-stage records as well as the session.
  ///
  /// A real switch on the Health Data page, and this is where it takes effect.
  /// The stage read is a second, much larger query — one record per REM span,
  /// per deep span, per stretch of light sleep — and somebody who only wants
  /// their nights does not need it. Off means the breakdown is never requested
  /// and never stored, so Insights has no stages to draw for nights read after
  /// that.
  ///
  /// True by default, so nothing changes for a person who has never touched the
  /// switch.
  bool readStageDetail = true;

  /// Whether the night records themselves are read at all.
  ///
  /// The bluntest of the three sleep permissions, and a real one: Health Connect
  /// hands over the session and the stage records separately, so somebody may
  /// want the stages without the night, or — more to the point — may want Strand
  /// to hold nothing at all.
  ///
  /// Off means no session is read, so nothing is stored, because a stage with no
  /// night to belong to is not something Strand can show. Empty rather than
  /// skipped, matching [readStageDetail], so the rest of the read does not have to
  /// know which of the three were switched on.
  ///
  /// True by default, so a person who has never touched the switch is unaffected.
  bool readSessions = true;
}
