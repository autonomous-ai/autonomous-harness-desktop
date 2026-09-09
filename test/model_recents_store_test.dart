// The picker's top section. Small, but it is the only thing in this feature
// that persists, and the two rules that matter — a re-pick MOVES a row rather
// than repeating it, and "no provider" is never one — are invisible until the
// list is wrong.
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/model_picker_options.dart';
import 'package:harness/grid/model_recents_store.dart';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

ModelChoice _choice(String model) =>
    ModelChoice(networkId: 'grid-office', networkName: 'Office', model: model);

void main() {
  test(
    'the newest pick is first, and a re-pick moves it rather than doubling it',
    () async {
      final store = ModelRecentsStore(storage: _MemoryStore());

      await store.remember(_choice('a'));
      await store.remember(_choice('b'));
      await store.remember(_choice('a'));

      expect(store.value.map((choice) => choice.model), ['a', 'b']);
    },
  );

  test('the list is a shortcut, not a history', () async {
    final store = ModelRecentsStore(storage: _MemoryStore());

    for (var i = 0; i < ModelRecentsStore.max + 3; i++) {
      await store.remember(_choice('model-$i'));
    }

    expect(store.value, hasLength(ModelRecentsStore.max));
    expect(store.value.first.model, 'model-${ModelRecentsStore.max + 2}');
  });

  test('"no provider" is never remembered', () async {
    // It is already a permanent row at the top of the picker, so a recent copy
    // of it would be the same row twice.
    final store = ModelRecentsStore(storage: _MemoryStore());

    await store.remember(ModelChoice.none);

    expect(store.value, isEmpty);
  });

  test('a relaunch reads back the picks, and not the names they were made under', () async {
    // The provider's name is rebuilt from the live list at draw time, so a grid
    // renamed since the pick reads under the name it has now.
    final disk = _MemoryStore();
    await ModelRecentsStore(storage: disk).remember(_choice('GLM-4.7-Flash'));

    final next = ModelRecentsStore(storage: disk);
    await next.load();

    expect(next.value, [_choice('GLM-4.7-Flash')]);
    expect(next.value.single.networkName, isEmpty);
  });

  test('an unreadable list costs the shortcut, not the picker', () async {
    final disk = _MemoryStore()..values['grid_recent_models'] = 'not json';
    final store = ModelRecentsStore(storage: disk);

    await store.load();

    expect(store.value, isEmpty);
  });

  test('Auto is a pick worth remembering', () async {
    // A model of null is "let the provider route", which is a real choice —
    // distinct from having picked no provider at all.
    final store = ModelRecentsStore(storage: _MemoryStore());

    await store.remember(
      const ModelChoice(networkId: 'grid-office', networkName: 'Office'),
    );

    expect(store.value.single.model, isNull);
    expect(store.value.single.hasProvider, isTrue);
  });
}
