import 'dart:async';

import 'package:flutter/widgets.dart';

import 'sleep_repository.dart';
import 'sleep_source_service.dart';
import 'sleep_store.dart';
import 'strand_sleep.dart';

/// Where Strand is with its sleep source, in the terms a page needs.
///
/// The order matters: [checking] comes first because it is what a person sees
/// while the device is still answering, and a page that renders "not connected"
/// during that moment would be briefly wrong about something it cannot know
/// yet.
enum SleepStatus {
  /// Still asking the device what is available.
  checking,

  /// The service is not on this phone, and cannot be.
  unsupported,

  /// The service exists on this phone but is not installed.
  notInstalled,

  /// Permission has not been granted yet.
  needsPermission,

  /// Permission was asked for and refused.
  refused,

  /// The last read failed. [SleepController.message] says why.
  failed,

  /// Connected, read successfully, and there is nothing in the window.
  readyNoData,

  /// Connected, and there are nights.
  readyWithData,

  /// A read is running right now.
  syncing,
}

/// The one place the app knows what sleep Strand has.
///
/// Home's glance card, the Health Data page and Insights all read from this,
/// which is what stops them disagreeing about whether anything is connected —
/// the same rule the profile already follows. None of them talk to
/// Health Connect, and none of them hold a night of their own.
///
/// Loaded from the store before any read, so the history is on screen
/// immediately and a sync only ever *adds* to what the person is looking at.
class SleepController extends ChangeNotifier {
  SleepController(this._repository, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now,
      _status = SleepStatus.checking;

  final SleepRepository _repository;

  /// "Now", as the controller sees it.
  ///
  /// Injected rather than read from the clock directly, so a test can hold time
  /// still. A sync window is defined in relation to the present moment, and a
  /// test that cannot control it is a test whose read window moves every day it
  /// is run.
  final DateTime Function() _now;

  /// "Now", as the rest of the app should see it.
  ///
  /// A page that read the wall clock itself would label a night "yesterday"
  /// using a different moment from the one the sync window was built around,
  /// and the two would disagree across a midnight or a timezone. One clock,
  /// shared.
  DateTime get now => _now();

  /// The account these imported nights belong to, or null when nobody is bound.
  String? _uid;

  /// Bumped whenever the account changes.
  ///
  /// **This is what makes a late sync harmless.** A sync reads from Health Connect over
  /// the network and then writes the result. If the account is deleted, or another one
  /// signs in, while that read is in flight, the write that lands afterwards belongs to
  /// the wrong account — and because the store is keyed by uid, it would land in the
  /// *new* account's nights, which is worse than losing it.
  ///
  /// A sync captures the epoch it started in and compares before it writes. The
  /// comparison happens at the last possible moment, immediately before the write, so
  /// an account change at any earlier point still discards the result.
  int _epoch = 0;

  /// Points the controller at an account, and drops whatever the last one held.
  ///
  /// ## Why a rebind is not merely a reload
  ///
  /// Two things happen here, and both are load-bearing.
  ///
  /// **The held nights are dropped immediately**, before any read — for the same reason
  /// the strands are: the moment the session changes, whatever is held belonged to
  /// somebody else, and it must not be on screen under a new account's name even for a
  /// frame.
  ///
  /// **The epoch is bumped**, which is what stops an in-flight sync from writing into
  /// whichever account is bound by the time it finishes.
  ///
  /// ## What deliberately is *not* cleared
  ///
  /// **The permission state, and the Health Connect records themselves.** Strand cannot
  /// revoke a permission Android granted it — there is no API for an app to withdraw its
  /// own runtime grants — and the records are the person's, held by the platform. So a
  /// new account starts with the permission still granted, and a sync will read the same
  /// nights again. **That is a fresh import, not a restoration**, and the difference is
  /// exactly the empty local index this method leaves behind: there is no stale history
  /// to mistake for one.
  ///
  /// Nothing here claims the permission was revoked, because it was not.
  Future<void> bindUser(String? uid, {bool checkHealth = true}) async {
    if (_uid == uid) return;
    _uid = uid;
    _epoch++;

    _repository.bindUser(uid);

    // The status is reset as well, because it was a statement about the *last*
    // account's ability to read. Left alone it would claim "connected, with data" over
    // an empty index, which is the one combination that lies.
    _index = SleepIndex.empty();
    _lastSync = null;
    _status = SleepStatus.checking;
    notifyListeners();

    // **Re-read, because clearing is not the same as being ready.**
    //
    // This method empties the controller, so something has to fill it again for the
    // account that just signed in — and the store now points at that account's key, so
    // the read gets *their* history rather than nobody's. Without these two lines the
    // app sits on [SleepStatus.checking] for ever after sign-in, which is a spinner
    // that never resolves; the header golden caught exactly that.
    //
    // **Nothing is read while signed out.** A null uid means the store answers empty by
    // construction, and calling into the platform channel for an account that is not
    // there would be asking a question whose answer is already known.
    if (uid == null) return;
    await load();
    if (checkHealth) {
      await checkAvailability();
    } else {
      // Nothing has been asked of the platform yet. Existing local nights are
      // still shown; an empty local index means the connection flow is the next
      // thing the person needs, not that there is no sleep.
      _status = _index.isEmpty ? SleepStatus.needsPermission : _ready;
      notifyListeners();
    }
  }

  /// The account currently bound, for callers that need to key their own storage by it.
  String? get uid => _uid;

  /// Whether Strand may read from the source at all.
  ///
  /// Set from the settings page, and consulted by [sync] itself rather than by
  /// each caller — so a switch that is off cannot be worked around by a screen
  /// that forgot to check, which is the only way a privacy control is ever
  /// actually trustworthy.
  bool readingAllowed = true;

  /// Whether to request the per-stage breakdown on the next read.
  ///
  /// Pushed down to the repository, which is the only place that knows what a
  /// stage read costs.
  set readStageDetail(bool value) => _repository.readStageDetail = value;
  bool get readStageDetail => _repository.readStageDetail;

  /// Pushed down for the same reason: whether Strand asks Health Connect for the
  /// night records at all.
  set readSessions(bool value) => _repository.readSessions = value;
  bool get readSessions => _repository.readSessions;

  SleepStatus _status;
  SleepIndex _index = SleepIndex.empty();
  DateTime? _lastSync;
  String? _message;

  /// Held so two taps on Sync do not start two reads of the same history.
  Future<SleepSyncReport>? _inFlight;

  SleepStatus get status => _status;

  /// Every night, newest first. Empty until a load or a sync has happened.
  List<StrandSleep> get records => _index.records;

  /// The most recent night, or null.
  StrandSleep? get latest => _index.latest;

  int get count => _index.length;
  bool get hasData => _index.isEmpty == false;

  /// When the last successful read finished, whether or not it found anything.
  DateTime? get lastSync => _lastSync;

  /// Why a read failed, when one did.
  String? get message => _message;

  bool get busy => _inFlight != null;

  /// The source, as a person reads it, or null when none is usable.
  String? sourceName;

  /// Whether the source can go back further than its default window.
  ///
  /// Null until it has been asked, so a page can say "unknown" rather than
  /// guessing. Kept because it changes what a person's history can contain,
  /// and a person deserves to know that before assuming Strand has missed
  /// anything.
  bool? historyAuthorized;

  /// Reads the stored history, without touching the source.
  ///
  /// Cheap, and safe to call repeatedly. This is what makes the Insights page
  /// open instantly and show a real history before any network-free read has
  /// happened.
  Future<void> load() async {
    _index = await _repository.load();
    _lastSync = await _repository.lastSync();
    // Deliberately leaves [_status] alone.
    //
    // Reading the store says nothing about the source: an empty store is just
    // as true before a permission is granted as after. Folding the two together
    // here is what would let "not connected yet" turn into "connected, nothing
    // found" on a cold start, and the page would then promise a sync that was
    // never possible.
    notifyListeners();
  }

  SleepStatus get _ready =>
      _index.isEmpty ? SleepStatus.readyNoData : SleepStatus.readyWithData;

  /// Asks the device what is available, and records it.
  ///
  /// Safe on a device with no health service at all; the answer is
  /// [SleepStatus.unsupported] and the page explains it.
  Future<void> checkAvailability() async {
    _status = SleepStatus.checking;
    notifyListeners();

    debugPrint('StrandSleep: checkAvailability start');
    final SleepSourceService? source = await _repository.usableSource();
    if (source == null) {
      debugPrint('StrandSleep: no usable source');
      _status = await _noSourceIsUnsupported()
          ? SleepStatus.unsupported
          : SleepStatus.notInstalled;
      sourceName = null;
      notifyListeners();
      return;
    }

    debugPrint('StrandSleep: source=${source.displayName}');
    sourceName = source.displayName;
    final bool hasPerm = await source.hasPermission();
    debugPrint('StrandSleep: hasPermission=$hasPerm');
    if (hasPerm) {
      historyAuthorized = await source.historyAuthorized();
      // The store is read for whatever history is already held, and only then is
      // the status settled. The order matters: the count has to be in hand
      // before "connected with data" or "connected with nothing" can be chosen.
      await load();
      _status = _ready;
    } else {
      historyAuthorized = null;
      _status = SleepStatus.needsPermission;
    }
    notifyListeners();
  }

  /// True when no configured source reports itself usable.
  ///
  /// The repository does not expose the individual answers, so this asks
  /// directly and caches nothing: it runs only on the path where there is no
  /// source at all, which is rare and not hot.
  Future<bool> _noSourceIsUnsupported() async {
    final List<SleepSourceService> sources = _repository.sources;
    for (final SleepSourceService source in sources) {
      if ((await source.availability()) ==
          SleepSourceAvailability.unsupported) {
        return true;
      }
    }
    return false;
  }

  /// Asks the person for permission, then reads if they gave it.
  Future<SleepSyncReport?> requestAccess() async {
    debugPrint('StrandSleep: requestAccess');
    final SleepSourceService? source = await _repository.usableSource();
    if (source == null) {
      await checkAvailability();
      return null;
    }

    _status = SleepStatus.checking;
    notifyListeners();

    final bool granted = await source.requestPermission();
    if (!granted) {
      // Refused. Not an error, and not the same as never having asked: the
      // page offers a way to change it in system settings.
      _status = SleepStatus.refused;
      notifyListeners();
      return null;
    }

    historyAuthorized = await source.historyAuthorized();
    return sync();
  }

  /// Asks for the longer history window, and reads again if it is granted.
  Future<SleepSyncReport?> requestFullHistory() async {
    final SleepSourceService? source = await _repository.usableSource();
    if (source == null) return null;
    final bool granted = await source.requestHistoryAuthorization();
    historyAuthorized = granted;
    if (!granted) {
      notifyListeners();
      return null;
    }
    return sync(forceFull: true);
  }

  /// Sends the person to the store page for Health Connect itself, for a phone
  /// that does not ship it in the system image.
  Future<void> installSource() async {
    for (final SleepSourceService source in _repository.sources) {
      await source.installSource();
    }
  }

  /// Opens the platform's own permission screen for the attached source.
  Future<void> openSystemPermissions() async {
    final SleepSourceService? source = await _repository.usableSource();
    await source?.openSystemPermissions();
  }

  /// Opens Health Connect itself, where access can be reviewed or revoked.
  Future<void> openSourceApp() async {
    for (final SleepSourceService source in _repository.sources) {
      await source.openSourceApp();
    }
  }

  /// Retries the connection, from the No Data state.
  ///
  /// "No sleep found yet" and "Strand is not allowed to read" are different problems that
  /// produce the same empty screen, and a retry that only re-reads data cannot tell them
  /// apart — it would re-query a source Strand has no permission for and report the same
  /// nothing, which is indistinguishable from the permission having been revoked on purpose.
  ///
  /// So the permission is **re-read from the device first**, every time. It is the only
  /// thing that can have changed underneath: the person may have granted it since, or
  /// revoked it since, and only the device can say which. Then the answer decides:
  ///
  ///  * permission is now held, or was never the problem — [sync] re-queries the nights
  ///  * permission is not held — [requestAccess] reopens the Health Connect flow, because a
  ///    retry that silently did nothing is a button that looks broken
  ///  * there is no source here — nothing to retry, and the status says why
  ///
  /// ## Why the permission is asked rather than cached
  ///
  /// A stored flag would be wrong in both directions and wrong silently: it cannot know
  /// that access was granted from Health Connect's own settings, and it cannot know it was
  /// revoked from there either. Health Connect holds the answer; this asks it every time.
  Future<SleepSyncReport?> retry() async {
    // Strand's own switch comes first, and it is not a cache of Health Connect's permission
    // — it is a separate decision this person made. When it is off a retry must say so
    // rather than appear to do nothing, so the status is set to explain the refusal instead
    // of the read quietly returning.
    if (!readingAllowed) {
      _status = SleepStatus.refused;
      _message = null;
      notifyListeners();
      return null;
    }

    await checkAvailability();

    switch (_status) {
      // Not permitted (or permitted but the ask was declined): reopen the flow rather than
      // re-reading a source Strand cannot read.
      case SleepStatus.needsPermission:
      case SleepStatus.refused:
        return requestAccess();
      // Nothing here to connect to. The status already says which of the two it is.
      case SleepStatus.unsupported:
      case SleepStatus.notInstalled:
        return null;
      // Permitted — re-query the nights. This also covers a permission that was granted
      // since the last read but was not known at the time, which is the case a person
      // pressing Retry is most likely to be in.
      case SleepStatus.readyNoData:
      case SleepStatus.readyWithData:
      case SleepStatus.checking:
      case SleepStatus.failed:
      case SleepStatus.syncing:
        return sync();
    }
  }

  /// Reads from the source and merges the result into what is held.
  ///
  /// Running it twice over the same nights is safe and is expected to find
  /// nothing new; that is the property [SleepIndex.upsert] exists to provide,
  /// and it is what lets a page offer a Sync button without a guard.
  Future<SleepSyncReport?> sync({bool forceFull = false}) async {
    debugPrint('StrandSleep: sync forceFull=$forceFull readingAllowed=$readingAllowed');
    // The gate, in one place. A read that is not allowed does not quietly
    // become a no-op deeper down where nobody would notice; it stops here, and
    // nothing on the page or in the store changes.
    if (!readingAllowed) return null;
    if (_inFlight != null) return _inFlight;

    _status = SleepStatus.syncing;
    _message = null;
    notifyListeners();

    final Future<SleepSyncReport> run = _run(forceFull: forceFull);
    _inFlight = run;
    try {
      return await run;
    } finally {
      _inFlight = null;
    }
  }

  Future<SleepSyncReport> _run({required bool forceFull}) async {
    // **The epoch this read belongs to**, captured before the network is touched.
    //
    // Everything below is a comparison against it. The read itself cannot be cancelled —
    // the platform call is already in progress and there is no handle to abandon it with
    // — so what is made safe is its *result*.
    final int startedAt = _epoch;

    SleepSyncReport report;
    try {
      // `forceFull` re-reads the whole lookback rather than from the watermark,
      // for a person who has just granted a longer history window and wants the
      // nights that window makes newly reachable.
      report = await _repository.sync(now: _now(), forceFull: forceFull);
    } catch (error) {
      // **A failure after the account changed is not this account's failure to report.**
      // Surfacing it would put a stale error on the page of whichever account is now
      // signed in, which is both untrue and confusing.
      if (startedAt != _epoch) return _discardedReport();
      _status = SleepStatus.failed;
      _message = '$error';
      notifyListeners();
      return SleepSyncReport(
        outcome: SleepSyncOutcome.failed,
        added: 0,
        updated: 0,
        unchanged: 0,
        message: _message,
      );
    }

    // **The check that matters.** The account changed while the read was in flight, so
    // what came back describes nights that were imported for somebody else — and the
    // repository has already written them under whichever account is bound now, which is
    // the new one. So the write is undone and the report discarded.
    //
    // Undoing rather than merely ignoring is deliberate: the repository writes on the way
    // out of `sync`, before this code regains control, so by this point the new account's
    // store may genuinely hold the old account's nights. `clear()` takes them back out,
    // and because the store is keyed by uid that touches the *new* account's key — which
    // is the one that was just polluted.
    if (startedAt != _epoch) {
      await _repository.clear();
      _index = SleepIndex.empty();
      _lastSync = null;
      return _discardedReport();
    }

    await load();

    debugPrint('StrandSleep: sync outcome=${report.outcome} added=${report.added} updated=${report.updated} unchanged=${report.unchanged} message=${report.message}');
    switch (report.outcome) {
      case SleepSyncOutcome.unavailable:
        await checkAvailability();
      case SleepSyncOutcome.notPermitted:
        _status = SleepStatus.needsPermission;
      case SleepSyncOutcome.failed:
        _status = SleepStatus.failed;
        _message = report.message;
      default:
        _status = _ready;
        _message = null;
    }
    notifyListeners();
    return report;
  }

  /// What a sync reports when its result was thrown away because the account changed.
  ///
  /// **`unchanged` with zero of everything, and no message.** It is not a failure — the
  /// read may well have succeeded — but it is not a success either, because nothing was
  /// kept. A message is deliberately absent: there is nothing for the person to do about
  /// an account that has already been replaced, and a snackbar about it would be noise
  /// about a state they are no longer in.
  SleepSyncReport _discardedReport() => SleepSyncReport(
    outcome: SleepSyncOutcome.nothingNew,
    added: 0,
    updated: 0,
    unchanged: 0,
  );

  /// Whether a sleep source is attached, for the settings controller to read.
  ///
  /// A read-only view of the same state, so the glance card on Home and this
  /// controller can never tell two different stories.
  bool get connected => switch (_status) {
    SleepStatus.readyNoData ||
    SleepStatus.readyWithData ||
    SleepStatus.syncing => true,
    _ => false,
  };

  /// Whether the source is attached and has actually produced nights.
  bool get connectedWithSleep =>
      _status == SleepStatus.readyWithData && hasData;

  /// Forgets [uid]'s imported nights, on this device and in memory.
  ///
  /// ## Why deletion calls this directly rather than waiting for the sign-out
  ///
  /// Signing out does bind to null and does empty everything, so this is belt and
  /// braces — and belt and braces is exactly the wrong reason to add a method. The real
  /// reason is **ordering**: deletion has to be able to say it cleaned up, and it cannot
  /// say that about something another callback might do later. A delete that clears
  /// state *because* a sign-out happens to follow is a delete whose correctness depends
  /// on the auth listener, and the one time that matters is when something has already
  /// gone wrong.
  ///
  /// ## What it does not touch
  ///
  /// The Health Connect permission, and the records Health Connect holds. Strand cannot
  /// revoke a permission Android granted it, and the records are the person's. **Neither
  /// is claimed to be revoked here** — the permission stays granted, and the next
  /// account reads from the platform afresh, which is an import rather than a recovery
  /// because there is nothing left in Strand's own storage to recover.
  ///
  /// The in-flight guard is bumped, so a read already under way for this account cannot
  /// write its result back afterwards. That is the same epoch mechanism [bindUser] uses,
  /// reached from deletion rather than from a session change.
  Future<void> forgetAccount(String uid) async {
    // A read under way for this account is now answering for nobody. Discard it.
    _epoch++;

    _repository.bindUser(uid);
    await _repository.clear();

    // Only if this is still the bound account. Somebody else may already have signed in
    // — deleting and registering quickly is exactly the sequence this exists for — and
    // clearing then would wipe the *new* account's state on the way past.
    if (_uid != uid) {
      _repository.bindUser(_uid);
      return;
    }

    _index = SleepIndex.empty();
    _lastSync = null;
    _message = null;
    _status = SleepStatus.checking;
    notifyListeners();
  }

  /// Forgets every imported night. Used by "erase your data on this device".
  Future<void> clear() async {
    await _repository.clear();
    _index = SleepIndex.empty();
    _lastSync = null;
    notifyListeners();
  }
}

/// Makes the sleep state reachable without threading it through every screen.
class SleepScope extends InheritedNotifier<SleepController> {
  const SleepScope({
    required SleepController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static SleepController of(BuildContext context) {
    final SleepScope? scope = context
        .dependOnInheritedWidgetOfExactType<SleepScope>();
    assert(scope?.notifier != null, 'No SleepScope above this widget.');
    return scope!.notifier!;
  }

  /// The controller, or null when there is no scope above this widget.
  ///
  /// **For callers that can do the right thing without it** — Settings, which sits
  /// inside the app shell on one route and outside it on another. `of` would assert
  /// there, which for a cleanup step is the wrong trade: failing to find the sleep
  /// controller is not a reason to fail a deletion that has already succeeded.
  static SleepController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SleepScope>()?.notifier;
}
