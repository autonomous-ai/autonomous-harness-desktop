import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/shared/theme/theme_mode_store.dart';

/// An in-memory store that can be told to fail, so the recovery paths are
/// exercised rather than assumed.
class _FakeStore implements LocalKeyValueStore {
  final Map<String, String> values = {};
  bool broken = false;

  @override
  Future<String?> read(String key) async {
    if (broken) throw StateError('unreadable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (broken) throw StateError('unwritable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('defaults to the computer, not to a guess', () async {
    final store = ThemeModeStore(storage: _FakeStore());
    await store.load();

    // The only value that can be right without asking: the person already told
    // their OS which they wanted.
    expect(store.value, ThemeMode.system);
  });

  test('remembers a choice by name, not by ordinal', () async {
    final storage = _FakeStore();
    await ThemeModeStore(storage: storage).select(ThemeMode.light);

    // An enum's index is a detail of the order its cases happen to be written
    // in, and a file on disk outlives that order. Reordering the enum must not
    // silently turn everyone's saved Light into Dark.
    expect(storage.values.values.single, 'light');

    final reopened = ThemeModeStore(storage: storage);
    await reopened.load();
    expect(reopened.value, ThemeMode.light);
  });

  test('an unreadable state file costs the preference, not the launch', () async {
    final storage = _FakeStore()..broken = true;
    final store = ThemeModeStore(storage: storage);

    await store.load();

    expect(store.value, ThemeMode.system);
  });

  test('the window moves even when the disk refuses', () async {
    // The notifier moves first and the write is awaited after: a failed write
    // costs the choice at the next launch, which is a far smaller wrong than a
    // theme that visibly lags the menu it was chosen from.
    final store = ThemeModeStore(storage: _FakeStore()..broken = true);

    await store.select(ThemeMode.dark);

    expect(store.value, ThemeMode.dark);
  });

  test('unknown text on disk falls back rather than throwing', () async {
    final storage = _FakeStore()..values['app_theme_mode'] = 'sepia';
    final store = ThemeModeStore(storage: storage);

    await store.load();

    expect(store.value, ThemeMode.system);
  });
}
