// Settings ▸ Keyboard shortcuts draws the deck; the ⌘/ sheet draws the column.
// What this guards is the reason the deck exists: the rows have to reflow into
// the width the pane actually has, instead of sitting in one 460px lane with
// the rest of the window empty.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/shortcuts/app_shortcuts.dart';
import 'package:harness/shortcuts/key_cap.dart';
import 'package:harness/shortcuts/shortcuts_list.dart';

void main() {
  Future<void> pumpDeck(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: const ShortcutsDeck()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a wide pane puts the groups side by side', (tester) async {
    tester.view.physicalSize = const Size(1400 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await pumpDeck(tester, 900);

    final navigate = tester.getTopLeft(find.text('NAVIGATE'));
    final panes = tester.getTopLeft(find.text('PANES'));
    expect(panes.dx, greaterThan(navigate.dx), reason: 'a second lane');
    expect(panes.dy, navigate.dy, reason: 'and level with the first');
  });

  testWidgets('a narrow pane stacks them, which is the sheet again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600 * 2, 1400 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await pumpDeck(tester, 320);

    final navigate = tester.getTopLeft(find.text('NAVIGATE'));
    final panes = tester.getTopLeft(find.text('PANES'));
    expect(panes.dx, navigate.dx);
    expect(panes.dy, greaterThan(navigate.dy));
  });

  testWidgets('every row is printed, with a cap per key', (tester) async {
    tester.view.physicalSize = const Size(1400 * 2, 1200 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await pumpDeck(tester, 900);

    for (final row in shortcutRows()) {
      expect(
        find.text(row.label),
        findsOneWidget,
        reason: '${row.label} is missing from the deck',
      );
    }

    // ⇧⌘] is three caps, not one glyph run.
    final next = find.ancestor(
      of: find.text('Next agent'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: next.first, matching: find.byType(KeyCap)),
      findsNWidgets(3),
    );

    // And the keys the app deliberately leaves alone are named too.
    expect(find.text('The terminal keeps'.toUpperCase()), findsOneWidget);
    expect(find.text(kTerminalOwnedKeys.first.label), findsOneWidget);
  });
}
