// The shape you pick is the shape you get.
//
// Every preset carries a list of unit rectangles (`PanePreset.tiles`). The
// palette PAINTS that list, so if the grid ever laid tiles out somewhere else,
// the picker would be advertising a shape the app does not build — and the only
// symptom would be a person picking the wrong one. So these tests measure the
// real laid-out tiles and hold them against the same list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pane_preset.dart';
import 'package:harness/state/pane_splits.dart';
import 'package:harness/state/terminal_pane.dart';
import 'package:harness/widgets/pane_grid.dart';

AppNotifier _withPanes(int n) {
  final notifier = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
  );
  for (var i = 0; i < n; i++) {
    notifier.panes.add(TerminalPane(id: i, machineId: 'm', agentId: 'a$i'));
  }
  return notifier;
}

/// Where each tile actually landed, as fractions of the grid.
Future<List<Rect>> _layout(WidgetTester tester, AppNotifier notifier) async {
  // Tall enough that no shape here hits the scroll fallback. Two columns of
  // nine tiles is five rows, and a window without the height for five rows at
  // the terminal floor SCROLLS rather than squeezing — correct behaviour, and
  // covered in pane_lattice_test, but it puts tiles outside the grid box and
  // there are no fractions of a visible grid left to measure.
  await tester.binding.setSurfaceSize(const Size(1600, 1500));
  await tester.pumpWidget(MaterialApp(home: PaneGrid(notifier: notifier)));
  await tester.pump();
  final grid = tester.getRect(find.byType(PaneGrid));
  return [
    for (final pane in notifier.panes)
      () {
        final r = tester.getRect(find.byKey(pane.cellKey));
        return Rect.fromLTRB(
          (r.left - grid.left) / grid.width,
          (r.top - grid.top) / grid.height,
          (r.right - grid.left) / grid.width,
          (r.bottom - grid.top) / grid.height,
        );
      }(),
  ];
}

/// Dividers eat a few pixels, so an edge lands near its fraction, not on it.
/// 0.02 of 1600px is 32px — wide enough for any divider, far too narrow to let
/// a half pass as a third.
void _expectShape(List<Rect> actual, List<Rect> want) {
  expect(actual.length, want.length);
  for (var i = 0; i < want.length; i++) {
    expect(actual[i].left, closeTo(want[i].left, 0.02), reason: 'tile $i left');
    expect(actual[i].top, closeTo(want[i].top, 0.02), reason: 'tile $i top');
    expect(
      actual[i].right,
      closeTo(want[i].right, 0.02),
      reason: 'tile $i right',
    );
    expect(
      actual[i].bottom,
      closeTo(want[i].bottom, 0.02),
      reason: 'tile $i bottom',
    );
  }
}

void main() {
  for (final count in [2, 3, 4, 5, 6, 7, 9]) {
    for (final preset in PanePreset.forCount(count)) {
      // `auto` measures the window, so its diagram is openly approximate and
      // there is nothing to hold it to — every other shape states its answer
      // and must lay out exactly that way.
      if (preset == PanePreset.auto) continue;
      testWidgets('$count tiles · ${preset.id} is laid out as it is drawn', (
        tester,
      ) async {
        final notifier = _withPanes(count);
        notifier.setPreset(count, preset);
        _expectShape(await _layout(tester, notifier), preset.tilesFor(count));
      });
    }
  }

  test('every size but one tile has something to choose', () {
    // The first cut offered nothing above four, on the theory that the window
    // decides. The window decides how many columns FIT; it does not decide how
    // many someone wants.
    expect(PanePreset.forCount(1), isEmpty);
    for (var n = 2; n <= 9; n++) {
      expect(PanePreset.forCount(n).length, greaterThan(1), reason: '$n tiles');
    }
  });

  test('a big grid offers auto first, then column counts that fit', () {
    expect(PanePreset.forCount(5).first, PanePreset.auto);
    for (var count = 5; count <= 9; count++) {
      for (final preset in PanePreset.forCount(count).skip(1)) {
        final columns = preset.statedColumns;
        expect(columns, isNotNull, reason: '${preset.id} states no columns');
        // More columns than tiles is the same grid with empty air in it.
        expect(
          columns! <= count,
          isTrue,
          reason: '$columns cols, $count tiles',
        );
      }
    }
  });

  test(
    'the lattice drawn is the lattice built, row-major with a short last row',
    () {
      // Seven tiles in three columns is three rows, the last holding one.
      final tiles = PanePreset.cols3.tilesFor(7);
      expect(tiles.length, 7);
      expect(tiles.first, const Rect.fromLTRB(0, 0, 1 / 3, 1 / 3));
      expect(tiles[3].top, closeTo(1 / 3, 1e-9), reason: 'second row starts');
      expect(tiles.last.left, closeTo(0, 1e-9), reason: 'last row starts left');
    },
  );

  test('an id written by the build that named columns by hand still opens', () {
    // Saved layouts from before the column count was general must not silently
    // fall back to the default shape.
    expect(PanePreset.byId('threeColumns'), PanePreset.cols3);
    expect(PanePreset.byId('fourColumns'), PanePreset.cols4);
  });

  test('every offered preset describes exactly that many tiles', () {
    for (var count = 2; count <= 9; count++) {
      for (final preset in PanePreset.forCount(count)) {
        expect(preset.tilesFor(count).length, count, reason: preset.id);
      }
    }
  });

  test('ids are what persist, and they are not the enum order', () {
    // Reordering the enum must not silently repoint saved layouts at a
    // different shape, so the id is the NAME. Round-trip proves it.
    for (final preset in PanePreset.values) {
      expect(PanePreset.byId(preset.id), preset);
    }
    expect(PanePreset.byId('a shape from a newer release'), isNull);
    expect(PanePreset.byId(null), isNull);
  });

  test('changing the shape drops dividers that described the old one', () {
    // A 0.7 divider under "two over one" is a boundary that does not exist
    // under "main + stack"; carrying it over lands a tile somewhere nobody
    // chose. Starting even is the only honest answer.
    final notifier = _withPanes(3);
    notifier.setSplits(3, const PaneSplits(row: 0.7, col: 0.3));
    expect(notifier.splitsFor(3).row, closeTo(0.7, 1e-9));

    notifier.setPreset(3, PanePreset.mainLeft);
    expect(notifier.splitsFor(3).row, closeTo(0.5, 1e-9));
    expect(notifier.splitsFor(3).col, closeTo(0.5, 1e-9));
  });

  test('setting the shape it already has leaves the dividers alone', () {
    // Re-picking the current shape from the palette is a no-op, not a reset —
    // it would be a nasty way to lose a tuned layout.
    final notifier = _withPanes(3);
    final preset = notifier.presetFor(3)!;
    notifier.setSplits(3, const PaneSplits(row: 0.7, col: 0.3));
    notifier.setPreset(3, preset);
    expect(notifier.splitsFor(3).row, closeTo(0.7, 1e-9));
  });
}
