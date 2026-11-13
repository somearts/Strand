import 'package:hive_flutter/hive_flutter.dart';

import '../auth/account.dart';
import 'models/profile.dart';
import 'models/cycle_record.dart';

class Storage {
  static const String profileBox = 'profile';
  static const String cyclesBox = 'cycles';
  static const String observationsBox = 'observations';
  static const String settingsBox = 'settings';
  static const String journalBox = 'journal';
  static const String accountBox = 'account';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(profileBox);
    await Hive.openBox(cyclesBox);
    await Hive.openBox(observationsBox);
    await Hive.openBox(settingsBox);
    await Hive.openBox(journalBox);
    await Hive.openBox(accountBox);
  }

  static Box get _profile => Hive.box(profileBox);
  static Box get _cycles => Hive.box(cyclesBox);
  static Box get _obs => Hive.box(observationsBox);
  static Box get _settings => Hive.box(settingsBox);
  static Box get _account => Hive.box(accountBox);

  // Account
  //
  // Kept apart from the sleep data on purpose. Signing in, signing out or
  // deleting an account never touches the nights on this device, and the
  // nights are keyed to the device rather than to a uid.
  static Account? get account {
    final dynamic raw = _account.get('data');
    if (raw is! Map) return null;
    final Account a = Account.fromMap(raw);
    return a.uid.isEmpty ? null : a;
  }

  static Future<void> saveAccount(Account a) async =>
      _account.put('data', a.toMap());

  static Future<void> clearAccount() async => _account.clear();

  // Profile
  static bool get hasProfile => _profile.get('data') != null;

  static Profile? getProfile() {
    final m = _profile.get('data');
    if (m == null) return null;
    return Profile.fromMap(Map<String, dynamic>.from(m as Map));
  }

  static Future<void> saveProfile(Profile p) async {
    await _profile.put('data', p.toMap());
  }

  // Cycles: store list under 'list'
  static List<CycleRecord> getCycles() {
    final raw = _cycles.get('list');
    if (raw == null) return [];
    final list = (raw as List).cast();
    return list
        .map((e) => CycleRecord.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> saveCycles(List<CycleRecord> records) async {
    await _cycles.put('list', records.map((r) => r.toMap()).toList());
  }

  static Future<void> addCycle(CycleRecord r) async {
    final list = getCycles();
    // avoid duplicate start date
    list.removeWhere((c) => _sameDay(c.startDate, r.startDate));
    list.add(r);
    list.sort((a, b) => a.startDate.compareTo(b.startDate));
    await saveCycles(list);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Observations
  static List<Observation> getObservations() {
    final raw = _obs.get('list');
    if (raw == null) return [];
    return (raw as List)
        .map((e) => Observation.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> saveObservation(Observation o) async {
    final list = getObservations();
    list.removeWhere((x) => _sameDay(x.date, o.date));
    list.add(o);
    list.sort((a, b) => a.date.compareTo(b.date));
    await _obs.put('list', list.map((x) => x.toMap()).toList());
  }

  static Observation? getObservation(DateTime date) {
    for (final o in getObservations()) {
      if (_sameDay(o.date, date)) return o;
    }
    return null;
  }

  // Settings: onboarding complete flag etc
  static bool get onboarded => _settings.get('onboarded') == true;
  static Future<void> setOnboarded(bool v) async =>
      _settings.put('onboarded', v);

  static bool get seenIntro => _settings.get('seenIntro') == true;
  static Future<void> setSeenIntro(bool v) async =>
      _settings.put('seenIntro', v);

  /// Whether the account step has been shown since this release introduced it.
  /// Existing installs are past the original onboarding but have never seen the
  /// sign-in screen, so they are shown it exactly once.
  static bool get authIntroSeen => _settings.get('authIntroSeen') == true;
  static Future<void> setAuthIntroSeen(bool v) async =>
      _settings.put('authIntroSeen', v);

  // Cycle preferences
  static int? get prefCycleLength => _settings.get('prefCycleLength') as int?;
  static Future<void> setPrefCycleLength(int? v) async {
    if (v == null) {
      await _settings.delete('prefCycleLength');
    } else {
      await _settings.put('prefCycleLength', v);
    }
  }

  static int? get prefPeriodDuration =>
      _settings.get('prefPeriodDuration') as int?;
  static Future<void> setPrefPeriodDuration(int? v) async {
    if (v == null) {
      await _settings.delete('prefPeriodDuration');
    } else {
      await _settings.put('prefPeriodDuration', v);
    }
  }

  static bool get usePrefPrediction =>
      _settings.get('usePrefPrediction') == true;
  static Future<void> setUsePrefPrediction(bool v) async =>
      _settings.put('usePrefPrediction', v);

  // Notifications
  static bool get notificationsEnabled =>
      _settings.get('notificationsEnabled') == true;
  static Future<void> setNotificationsEnabled(bool v) async =>
      _settings.put('notificationsEnabled', v);

  static bool get periodApproachingReminder =>
      _settings.get('periodApproachingReminder') != false;
  static Future<void> setPeriodApproachingReminder(bool v) async =>
      _settings.put('periodApproachingReminder', v);

  static bool get periodStartReminder =>
      _settings.get('periodStartReminder') != false;
  static Future<void> setPeriodStartReminder(bool v) async =>
      _settings.put('periodStartReminder', v);

  static bool get ovulationReminder =>
      _settings.get('ovulationReminder') == true;
  static Future<void> setOvulationReminder(bool v) async =>
      _settings.put('ovulationReminder', v);

  static bool get fertileReminder => _settings.get('fertileReminder') == true;
  static Future<void> setFertileReminder(bool v) async =>
      _settings.put('fertileReminder', v);

  static int get reminderDaysBefore =>
      (_settings.get('reminderDaysBefore') as int?) ?? 2;
  static Future<void> setReminderDaysBefore(int v) async =>
      _settings.put('reminderDaysBefore', v);

  // Journal
  static List<Map<String, dynamic>> getJournalEntries() {
    final raw = Hive.box(journalBox).get('list');
    if (raw == null) return [];
    return (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> saveJournalEntry(String text) async {
    final list = getJournalEntries();
    list.insert(0, {
      'date': DateTime.now().millisecondsSinceEpoch,
      'text': text,
    });
    await Hive.box(journalBox).put('list', list);
  }

  /// Saves a dream and returns the millisecond key it was filed under.
  ///
  /// The interpretation is written in the same record as the dream, and the
  /// return value is what lets the screen attach the worker's reading to the
  /// exact entry the person just wrote. Nothing is guessed from the text.
  static Future<int> saveDreamEntry({
    required String text,
    String interpretation = '',
  }) async {
    final int key = DateTime.now().millisecondsSinceEpoch;
    final list = getJournalEntries();
    list.insert(0, <String, dynamic>{
      'date': key,
      'text': text,
      'interpretation': interpretation,
    });
    await Hive.box(journalBox).put('list', list);
    return key;
  }

  /// Stores a reading that arrived after the dream was already saved.
  static Future<void> setDreamInterpretation(
    int key,
    String interpretation,
  ) async {
    final list = getJournalEntries();
    for (final entry in list) {
      if ((entry['date'] as num?)?.toInt() == key) {
        entry['interpretation'] = interpretation;
        break;
      }
    }
    await Hive.box(journalBox).put('list', list);
  }

  // Generic string storage for StrandStore adapter.
  static String? readString(String key) => _settings.get(key) as String?;
  static Iterable<String> get settingsKeys => _settings.keys.cast<String>();
  static Future<void> writeString(String key, String value) async =>
      _settings.put(key, value);
  static Future<void> removeString(String key) async => _settings.delete(key);

  static Future<void> clearAllData() async {
    await Hive.box(profileBox).clear();
    await Hive.box(cyclesBox).clear();
    await Hive.box(observationsBox).clear();
    await Hive.box(settingsBox).clear();
    await Hive.box(journalBox).clear();
    await Hive.box(accountBox).clear();
  }
}
