import 'package:harness/core/local_key_value_store.dart';

/// A [LocalKeyValueStore] in memory — the seam that keeps `~/.harness` out of a test.
class MemoryKeyValueStore implements LocalKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
