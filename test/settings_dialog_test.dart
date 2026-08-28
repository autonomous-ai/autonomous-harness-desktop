import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_font_store.dart';
import 'package:harness/widgets/settings_dialog.dart';

void main() {
  // Deliberately never calls a mutating method on either real global singleton
  // (`terminalFontStore` or `themeModeStore`) here — both persist through the
  // real `HarnessFileStore` (the user's actual `~/.harness/desktop-app/state.json`),
  // the same reason `theme_mode_store_test.dart` never touches the real
  // `themeModeStore` either. This only reads each store's untouched default.
  testWidgets(
    'shows the Appearance and Terminal font sections with their current values',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Placeholder()));

      unawaited(showSettingsDialog(tester.element(find.byType(Placeholder))));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);

      // Appearance section — segmented control defaults to System.
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Terminal font section — unchanged controls/keys from before the merge.
      expect(find.text('TERMINAL FONT'), findsOneWidget);
      expect(
        find.byKey(const Key('terminal-font-family-dropdown')),
        findsOneWidget,
      );
      expect(find.text(TerminalFontChoice.sfMono.label), findsOneWidget);
      expect(find.text('13pt'), findsOneWidget);
      expect(
        find.byKey(const Key('terminal-font-size-decrease')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('terminal-font-size-increase')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('terminal-settings-reset-button')),
        findsOneWidget,
      );
      expect(find.text('Reset to default'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    },
  );

  testWidgets('Close dismisses the dialog', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Placeholder()));

    final dialog = showSettingsDialog(
      tester.element(find.byType(Placeholder)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await dialog;

    expect(find.text('Settings'), findsNothing);
  });
}
