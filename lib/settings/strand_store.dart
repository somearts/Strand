
/// Somewhere small amounts of state can be kept between launches.
///
/// An interface rather than a direct use of `shared_preferences`, so settings
/// can be tested without the platform channel, and so swapping the store later
/// touches one file.
abstract interface class StrandStore {
  String? read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);

  /// Every key this store currently holds.
  ///
  /// **Added for deleting an account.** Removing one account's stored facts means
  /// naming them, and until now each of them was written under a key built by the
  /// thing that wrote it, so nothing could enumerate them and the only way to tidy up
  /// was to know the list by heart. Enumerating is what makes "delete everything that
  /// belongs to this uid" a fact about the uid rather than a list somebody has to
  /// remember to update when a new account-scoped field is added.
  Iterable<String> get keys;
}

/// A store that forgets, for tests and for a device where storage is
/// unavailable.
class MemoryStrandStore implements StrandStore {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Iterable<String> get keys => List<String>.of(_values.keys);
}

