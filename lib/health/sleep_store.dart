import 'dart:convert';

import '../settings/strand_store.dart';
import 'strand_sleep.dart';

/// Every night Strand holds, in one immutable value.
///
/// Immutable because a sync produces a new index rather than editing the one a
/// screen may be drawing. A person scrolling Insights while a sync lands should
/// see the page they were looking at, or the finished new one, never half of
/// each.
///
/// The index is also where idempotence lives. [upsert] is keyed on the record's
/// own id, so reading the same night twice replaces it instead of adding a
/// second copy — which is the whole reason syncing twice is safe.
class SleepIndex {
  SleepIndex(Map<String, StrandSleep> records)
    : _records = Map<String, StrandSleep>.unmodifiable(records);

  /// Nothing, which is a real and common state: nobody has connected anything.
  SleepIndex.empty() : _records = const <String, StrandSleep>{};

  final Map<String, StrandSleep> _records;

  /// Newest first. The order the Insights page draws.
  List<StrandSleep> get records {
    final List<StrandSleep> all = _records.values.toList()
      ..sort(StrandSleep.compareNewestFirst);
    return all;
  }

  /// The most recent night, or null.
  ///
  /// Null rather than a zero-valued record when there is nothing, because the
  /// page's empty state depends on being able to tell "no data" from "zero".
  StrandSleep? get latest {
    StrandSleep? best;
    for (final StrandSleep record in _records.values) {
      if (best == null || StrandSleep.compareNewestFirst(record, best) < 0) {
        best = record;
      }
    }
    return best;
  }

  bool get isEmpty => _records.isEmpty;
  int get length => _records.length;

  /// The newest end time across all records.
  ///
  /// This is the point a later sync starts from, so a full re-read of a long
  /// history is not repeated on every launch.
  DateTime? get watermark {
    DateTime? newest;
    for (final StrandSleep record in _records.values) {
      if (newest == null || record.end.isAfter(newest)) newest = record.end;
    }
    return newest;
  }

  /// How far back the stored history reaches.
  DateTime? get oldestStart {
    DateTime? oldest;
    for (final StrandSleep record in _records.values) {
      if (oldest == null || record.start.isBefore(oldest))
        oldest = record.start;
    }
    return oldest;
  }

  /// Adds a record, or replaces the one with the same id.
  ///
  /// The three outcomes are counted because the controller reports them, and a
  /// person watching a sync benefits from being told "nothing new" rather than
  /// being left to work out whether anything happened.
  SleepUpsert upsert(StrandSleep record) {
    final StrandSleep? existing = _records[record.id];
    if (existing == null) {
      return SleepUpsert(
        (_SleepIndexBuilder(_records).._add(record)).build(),
        SleepUpsertOutcome.added,
      );
    }
    if (existing.fingerprint == record.fingerprint) {
      // Already have exactly this. Returning the same map means a sync that
      // finds nothing new does no write at all, rather than rewriting the
      // store with identical bytes.
      return SleepUpsert(SleepIndex(_records), SleepUpsertOutcome.unchanged);
    }
    // Same night, different content: the source revised it. Replace it, and say
    // so, because a number on the page is about to change.
    return SleepUpsert(
      (_SleepIndexBuilder(_records).._add(record)).build(),
      SleepUpsertOutcome.updated,
    );
  }

  /// Removes a record by id. Returns null if it was not there.
  SleepIndex? remove(String id) {
    if (!_records.containsKey(id)) return null;
    final _SleepIndexBuilder builder = _SleepIndexBuilder(_records)
      .._remove(id);
    return builder.build();
  }

  /// Every night belonging to one calendar day, newest first.
  List<StrandSleep> onNight(DateTime night) => records
      .where(
        (StrandSleep r) =>
            r.night == DateTime(night.year, night.month, night.day),
      )
      .toList();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': 1,
    'records': _records.values.map((StrandSleep r) => r.toJson()).toList(),
  };

  static SleepIndex fromJson(Map<String, dynamic> json) {
    final Map<String, StrandSleep> out = <String, StrandSleep>{};
    final Object? raw = json['records'];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is! Map) continue;
        final StrandSleep? record = StrandSleep.fromJson(
          Map<String, dynamic>.from(item),
        );
        // A record that will not parse is dropped rather than allowed to
        // poison the index. Losing one night is visible; refusing to read the
        // other nine hundred is not acceptable.
        if (record != null) out[record.id] = record;
      }
    }
    return SleepIndex(out);
  }
}

/// A tiny helper so [SleepIndex] can stay immutable while still being built by
/// a loop that upserts hundreds of records.
class _SleepIndexBuilder {
  _SleepIndexBuilder(Map<String, StrandSleep> seed)
    : _records = Map<String, StrandSleep>.of(seed);

  final Map<String, StrandSleep> _records;

  void _add(StrandSleep record) => _records[record.id] = record;

  void _remove(String id) => _records.remove(id);

  SleepIndex build() => SleepIndex(_records);
}

/// What one [SleepIndex.upsert] did.
enum SleepUpsertOutcome {
  added,
  updated,

  /// Already stored, byte for byte.
  unchanged;

  bool get changed => this != SleepUpsertOutcome.unchanged;
}

/// One upsert's result: the new index, and what happened.
class SleepUpsert {
  const SleepUpsert(this.index, this.outcome);
  final SleepIndex index;
  final SleepUpsertOutcome outcome;
}

/// Somewhere the nights Strand has imported are kept between launches.
///
/// An interface, like [StrandStore], so the health layer can be exercised
/// without a platform channel and so a store that cannot hold a long history
/// can be swapped in without touching the repository.
abstract interface class SleepStore {
  /// Points the store at an account, or at nobody.
  ///
  /// Null — signed out — reads as empty and refuses to write. See
  /// [KeyValueSleepStore.bindUser] for why the account has to be named here rather than
  /// assumed.
  void bindUser(String? uid);

  Future<SleepIndex> read();

  /// Persists [index], and remembers [lastSync].
  Future<void> write(SleepIndex index, {DateTime? lastSync});

  /// When a sync last completed, whether or not it found anything.
  Future<DateTime?> readLastSync();

  /// Forgets everything. Used by "erase your data on this device", which has to
  /// reach imported nights as well as the profile.
  Future<void> clear();
}

/// The real store, on device.
///
/// The whole history is one JSON string in [StrandStore]. That is a deliberate
/// trade rather than an oversight: a few years of nights is on the order of a
/// megabyte, it is read on the way to the page in a single call, and it keeps
/// the store from becoming a second database with its own failure modes. A
/// person with decades of history would want this sharded by month, and the
/// [SleepStore] interface is where that change would be made — nothing above it
/// knows how the records are filed.
///
/// ## Why the keys carry an account
///
/// These were **one device-wide key each**, with no account named, and that is the
/// reason a deleted account's sleep history came back. Deleting a Strand account
/// deletes the auth record, so re-registering with the same address produces a **new
/// uid** — and the old nights were sitting in a key the new account had every right to
/// read, because nothing in the key said they belonged to somebody else.
///
/// The symptom was: delete the account, register again, and the previous account's
/// sleep history was already there and appeared to have synced. It was not a sync.
/// Nothing had been read from Health Connect. `SleepRepository.load` is
/// `store.read()`, and the store had simply never been emptied.
class KeyValueSleepStore implements SleepStore {
  KeyValueSleepStore(this._store);

  final StrandStore _store;

  /// The device-wide keys these used to be written under.
  ///
  /// **Named so the deletion sweep can remove them**, and so nothing that migrates
  /// strand-by-strand ever tries to read one and find it still populated.
  static const String legacyRecordsKey = 'strand.sleep.records';
  static const String legacyLastSyncKey = 'strand.sleep.lastSync';

  /// The account these nights belong to, or null when nobody is bound.
  String? _uid;

  @override
  void bindUser(String? uid) {
    _uid = uid;
  }

  /// This account's key, or null when nobody is bound.
  ///
  /// **Null rather than a bare key**, for the same reason the profile's and the strands'
  /// are. A key that cannot say whose it is belongs to whoever reads it next.
  String? get _recordsKey => _uid == null ? null : '$legacyRecordsKey.$_uid';
  String? get _lastSyncKey => _uid == null ? null : '$legacyLastSyncKey.$_uid';

  @override
  Future<SleepIndex> read() async {
    final String? key = _recordsKey;
    if (key == null) return SleepIndex.empty();
    final String? raw = _store.read(key);
    if (raw == null || raw.isEmpty) return SleepIndex.empty();
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return SleepIndex.empty();
      return SleepIndex.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Corrupt or half-written. An empty history is wrong but survivable;
      // refusing to open the app is not. A later sync refills it.
      return SleepIndex.empty();
    }
  }

  @override
  Future<void> write(SleepIndex index, {DateTime? lastSync}) async {
    final String? recordsKey = _recordsKey;
    final String? lastSyncKey = _lastSyncKey;
    // **Refuses rather than writing to a shared key.** A night saved with nobody signed
    // in has no account to belong to, and a key that accepts it is a key the next
    // account will read.
    if (recordsKey == null || lastSyncKey == null) return;
    await _store.write(recordsKey, jsonEncode(index.toJson()));
    if (lastSync != null) {
      await _store.write(lastSyncKey, lastSync.toUtc().toIso8601String());
    }
  }

  @override
  Future<DateTime?> readLastSync() async {
    final String? key = _lastSyncKey;
    if (key == null) return null;
    return DateTime.tryParse(_store.read(key) ?? '');
  }

  @override
  Future<void> clear() async {
    // Clears the bound account's keys **and the legacy device-wide ones**.
    //
    // The legacy pair is removed even when an account is bound, because that pair is
    // what an account deleted before this change left behind — and the whole point is
    // that a re-registered account must not find it. Leaving it would mean the exact
    // reported bug survives for every person who deleted an account on an older build.
    final String? recordsKey = _recordsKey;
    final String? lastSyncKey = _lastSyncKey;
    if (recordsKey != null) await _store.remove(recordsKey);
    if (lastSyncKey != null) await _store.remove(lastSyncKey);
    await _store.remove(legacyRecordsKey);
    await _store.remove(legacyLastSyncKey);
  }
}

/// A store that forgets, for tests and for a device where storage is
/// unavailable.
class MemorySleepStore implements SleepStore {
  SleepIndex _index = SleepIndex.empty();
  DateTime? _lastSync;

  /// Whether a write is accepted, which is only false while nobody is bound.
  ///
  /// **Kept honest rather than always true**, so a test exercising the signed-out guard
  /// is testing the guard and not a store that happens to accept everything.
  bool _bound = false;

  /// The account the single slot currently holds, so a switch can be detected.
  String? _uid;

  /// **Cleared on every rebind, not only on sign-out.**
  ///
  /// The real store keeps one key per account, so switching accounts switches to a
  /// different key and the previous one's records are simply not there any more. This
  /// store holds a *single* slot, so it has to model that by emptying itself whenever the
  /// account changes — which is the same observable behaviour.
  ///
  /// An earlier version cleared only on sign-out, and a test that switched from one
  /// account to another found the first account's nights still held: which is exactly
  /// the leak this whole change exists to close, reproduced in the double rather than in
  /// production. A fake that is laxer than the thing it stands in for is worse than no
  /// fake at all.
  @override
  void bindUser(String? uid) {
    if (_uid == uid) return;
    _uid = uid;
    _bound = uid != null;
    _index = SleepIndex.empty();
    _lastSync = null;
  }

  @override
  Future<SleepIndex> read() async => _index;

  @override
  Future<void> write(SleepIndex index, {DateTime? lastSync}) async {
    if (!_bound) return;
    _index = index;
    if (lastSync != null) _lastSync = lastSync;
  }

  @override
  Future<DateTime?> readLastSync() async => _lastSync;

  @override
  Future<void> clear() async {
    _index = SleepIndex.empty();
    _lastSync = null;
  }
}
