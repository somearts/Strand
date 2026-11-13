import '../data/storage.dart';
import '../settings/strand_store.dart';

class HiveStrandStore implements StrandStore {
  @override
  Iterable<String> get keys => Storage.settingsKeys;

  @override
  String? read(String key) => Storage.readString(key);

  @override
  Future<void> write(String key, String value) => Storage.writeString(key, value);

  @override
  Future<void> remove(String key) => Storage.removeString(key);
}
