// A note in a menu panel is a SENTENCE, and a sentence that does not fit has to
// wrap. It did not: `MenuAnchor` lays its children out inside a vertical
// `SingleChildScrollView`, which hands them unbounded width, so the row took its
// intrinsic width — one long line — and the panel's `maximumSize` clipped what
// hung off the edge. On screen that reads as a broken panel, not a narrow one:
// "Agents already running keep th" and then nothing.
//
// `maxLines` never entered into it, and neither did the `Expanded` the note used
// to wrap its text in: neither does anything without a bounded width to work
// against. Hence [AppMenuNote.panelWidth], and hence these.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/shared/widgets/app_menu.dart';

const _long =
    'New agents only. Agents already running keep the grid they started on.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpNote(
    WidgetTester tester, {
    required double panelWidth,
    double? noteWidth,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: MenuAnchor(
              style: AppMenu.style(maxWidth: panelWidth, maxHeight: 420),
              menuChildren: [
                AppMenuNote(_long, panelWidth: noteWidth),
                const AppMenuDivider(),
                AppMenuItem(label: 'autonomous.ai', onPressed: () {}),
              ],
              builder: (context, controller, _) =>
                  TextButton(onPressed: controller.open, child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a note told its panel width wraps inside the panel', (tester) async {
    await pumpNote(tester, panelWidth: 304, noteWidth: 304);

    final size = tester.getSize(find.text(_long));
    // Inside the panel, not spilling past it.
    expect(size.width, lessThanOrEqualTo(304));
    // And it grew DOWNWARD to fit — one line would be ~15px.
    expect(size.height, greaterThan(30));
    expect(
      tester.renderObject<RenderParagraph>(find.text(_long)).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('the whole note stays within the panel it is drawn in', (tester) async {
    await pumpNote(tester, panelWidth: 304, noteWidth: 304);

    final note = tester.getRect(find.text(_long));
    final panel = tester.getRect(
      find.ancestor(of: find.text(_long), matching: find.byType(Material)).last,
    );
    // The clipping bug put the note's right edge PAST the panel's. Nothing is
    // allowed to hang off either side.
    expect(note.right, lessThanOrEqualTo(panel.right + 0.5));
    expect(note.left, greaterThanOrEqualTo(panel.left - 0.5));
  });

  testWidgets('a note left unbounded still lays out on one line', (tester) async {
    // The other half of the contract: a short placeholder standing in for a
    // list ("Loading models…") passes no width and must not be forced to wrap.
    await pumpNote(tester, panelWidth: 304, noteWidth: null);

    expect(tester.getSize(find.text(_long)).height, lessThan(30));
  });
}
