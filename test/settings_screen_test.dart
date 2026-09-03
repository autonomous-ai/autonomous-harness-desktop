// Settings is a screen now, not a dialog — so what this guards is the shape a
// dialog never had: a rail you pick a section from, a pane that follows it, a
// filter over the rail, and a way back out.
//
// Deliberately never calls a mutating method on either real global singleton
// (`terminalFontStore` or `themeModeStore`): both persist through the real
// `HarnessFileStore` (the user's actual `~/.harness/desktop-app/state.json`),
// the same reason `theme_mode_store_test.dart` never touches the real
// `themeModeStore` either. This only reads each store's untouched default.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/settings/settings_screen.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/terminal/terminal_font_store.dart';

import 'support/fake_grid_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The About section prints the running version.
  PackageInfo.setMockInitialValues(
    appName: 'Harness',
    packageName: 'ai.autonomous.harness',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  /// Opens Settings over a bare host screen and settles the push transition.
  Future<AppNotifier> openSettings(WidgetTester tester) async {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
    // Settings opens on Grid, whose pane fetches — hand it a fake so no test
    // here touches the live control plane.
    final gridNetworks = GridNetworksController(client: FakeGridApi());
    addTearDown(gridNetworks.dispose);
    // Wide enough that the rail and the pane both have room — the window's own
    // minimum is 880.
    tester.view.physicalSize = const Size(1100 * 2, 760 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            AppTheme.brightness.value = Brightness.light;
            return const BrightnessScope(child: Placeholder());
          },
        ),
      ),
    );
    unawaited(
      showSettingsScreen(
        tester.element(find.byType(Placeholder)),
        notifier,
        gridNetworks: gridNetworks,
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('opens on Grid, with every section in the rail', (tester) async {
    await openSettings(tester);

    // The rail: every group caption and every row.
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Back to app'), findsOneWidget);

    // Grid is the section it opens on, so its name is the group caption, the
    // rail row AND the pane's title.
    expect(find.text('Grid'), findsNWidgets(3));
    // And its pane really loaded, through the injected fake.
    expect(find.text('hp-1-1'), findsOneWidget);
  });

  testWidgets('picking Appearance swaps the pane for the theme control', (
    tester,
  ) async {
    await openSettings(tester);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsNWidgets(2));
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('hp-1-1'), findsNothing);
  });

  testWidgets('picking Terminal swaps the pane for the font controls', (
    tester,
  ) async {
    await openSettings(tester);

    await tester.tap(find.text('Terminal'));
    await tester.pumpAndSettle();

    expect(find.text('Terminal'), findsNWidgets(2));
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
    // The Grid pane is gone with its section.
    expect(find.text('hp-1-1'), findsNothing);
  });

  testWidgets('the rail filter narrows to matching rows, and says so when '
      'nothing matches', (tester) async {
    await openSettings(tester);

    await tester.enterText(find.byType(TextField), 'key');
    await tester.pumpAndSettle();

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    // Rail rows gone; the open pane's own title is what remains of 'Grid'.
    expect(find.text('Grid'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('Terminal'), findsNothing);
    expect(find.text('Preferences'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No settings match'), findsOneWidget);
  });

  testWidgets('Back to app leaves Settings', (tester) async {
    await openSettings(tester);

    await tester.tap(find.text('Back to app'));
    await tester.pumpAndSettle();

    expect(find.text('Back to app'), findsNothing);
    expect(find.text('Grid'), findsNothing);
    expect(find.byType(Placeholder), findsOneWidget);
  });
}
