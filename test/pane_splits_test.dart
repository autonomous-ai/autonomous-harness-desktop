// Where the dividers sit, and what is allowed to move them.
//
// The clamps are the point. A fraction is the one form of "size" that survives
// being reopened on another display, but it still has to be stopped before it
// produces a tile the terminal underneath cannot use.
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pane_layout_store.dart';
import 'package:harness/state/pane_splits.dart';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  group('the model', () {
    test('a fresh grid is centred everywhere', () {
      const splits = PaneSplits();
      expect(splits.row, 0.5);
      expect(splits.colTop, 0.5);
      expect(splits.colBottom, 0.5);
      expect(splits.isDefault, isTrue);
    });

    test('a divider cannot be pushed onto the edge', () {
      // The pixel floor (40 columns) is applied where the width is known; this
      // is the backstop that keeps a stored file from asking for a zero-width
      // tile before anything has been measured.
      expect(const PaneSplits().copyWith(colTop: 0.99).colTop, 0.85);
      expect(const PaneSplits().copyWith(colTop: 0.001).colTop, 0.15);
      expect(const PaneSplits().copyWith(row: -5).row, 0.15);
    });

    test('nonsense reads as centred rather than throwing', () {
      expect(PaneSplits.fromJson(null), const PaneSplits());
      expect(PaneSplits.fromJson('nope'), const PaneSplits());
      expect(PaneSplits.fromJson({'row': 'x'}), const PaneSplits());
      expect(PaneSplits.fromJson({'row': double.nan}).row, 0.5);
    });

    test('round trips through json', () {
      const splits = PaneSplits(row: 0.7, colTop: 0.3, colBottom: 0.62);
      expect(PaneSplits.fromJson(splits.toJson()), splits);
    });
  });

  group('what is written to disk', () {
    test('a centred grid writes nothing to read back wrong later', () async {
      final storage = _MemoryStore();
      final store = PaneLayoutStore(storage: storage);
      await store.saveSplits({2: const PaneSplits(), 3: const PaneSplits()});
      expect(storage.values['terminal_pane_splits'], '{}');
      expect(await store.loadSplits(), isEmpty);
    });

    test('moved dividers survive the round trip, per pane count', () async {
      final store = PaneLayoutStore(storage: _MemoryStore());
      await store.saveSplits({
        2: const PaneSplits(colTop: 0.7),
        4: const PaneSplits(row: 0.3, colTop: 0.4, colBottom: 0.8),
      });
      final back = await store.loadSplits();
      expect(back[2]!.colTop, 0.7);
      expect(back[4]!.colBottom, 0.8);
      expect(back.containsKey(3), isFalse);
    });

    test('a count this build cannot lay out is dropped', () async {
      // Written by a future build with a bigger grid, or by hand.
      final storage = _MemoryStore();
      storage.values['terminal_pane_splits'] =
          '{"4":{"row":0.3},"9":{"row":0.3},"1":{"row":0.3}}';
      final back = await PaneLayoutStore(storage: storage).loadSplits();
      expect(back.keys, [4]);
    });

    test('an unreadable file lands on centred, not on a crash', () async {
      final storage = _MemoryStore();
      storage.values['terminal_pane_splits'] = 'not json at all';
      expect(await PaneLayoutStore(storage: storage).loadSplits(), isEmpty);
    });
  });

  group('the grid state', () {
    AppNotifier notifier(PaneLayoutStore store) => AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      paneLayoutStore: store,
    );

    test('each pane count keeps its own dividers', () async {
      // Three tiles and four tiles are different SHAPES. Carrying a fraction
      // between them moves a boundary the user never dragged.
      final n = notifier(PaneLayoutStore(storage: _MemoryStore()));
      n.setSplits(3, const PaneSplits(row: 0.7));
      expect(n.splitsFor(3).row, 0.7);
      expect(n.splitsFor(4).row, 0.5);
      expect(n.splitsFor(2), const PaneSplits());
    });

    test('a count off the grid is refused', () async {
      final n = notifier(PaneLayoutStore(storage: _MemoryStore()));
      n.setSplits(1, const PaneSplits(row: 0.7));
      n.setSplits(9, const PaneSplits(row: 0.7));
      expect(n.paneSplits, isEmpty);
    });

    test('moving a divider is written straight through', () async {
      final storage = _MemoryStore();
      final n = notifier(PaneLayoutStore(storage: storage));
      n.setSplits(2, const PaneSplits(colTop: 0.62));
      await Future<void>.delayed(Duration.zero);
      expect(storage.values['terminal_pane_splits'], contains('0.62'));
    });

    test('setting the same position again does not notify', () async {
      final n = notifier(PaneLayoutStore(storage: _MemoryStore()));
      n.setSplits(2, const PaneSplits(colTop: 0.62));
      var notified = 0;
      n.addListener(() => notified++);
      n.setSplits(2, const PaneSplits(colTop: 0.62));
      expect(notified, 0);
    });
  });
}
