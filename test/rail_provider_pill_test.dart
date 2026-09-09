// The status rail's left end: what new agents run on.
//
// The rule this file holds: the rail names the CAUSE, not just its consequence.
// Every other figure on the strip is a measurement — how much of a rate limit
// is spent, how many machines are up — and before this pill a person reading
// `2% used` had no way to know whose 2% it was.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/grid/provider_enablement_store.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/status_rail/rail_provider_pill.dart';

import 'support/fake_grid_api.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late GridSelectionStore selection;
  late ProviderEnablementStore enablement;

  setUp(() {
    selection = GridSelectionStore(storage: _MemoryStore());
    // Its own file: the singleton writes the developer's real ~/.harness.
    enablement = ProviderEnablementStore(
      file: File(
        '${Directory.systemTemp.createTempSync('providers').path}'
        '/providers_config.json',
      ),
      gridSurface: true,
    );
  });

  Future<GridNetworksController> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final networks = GridNetworksController(client: FakeGridApi());
    addTearDown(networks.dispose);
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            AppTheme.brightness.value = Brightness.light;
            return BrightnessScope(
              child: Scaffold(
                // Bottom-left, the way the rail sits, so the menu opens upward
                // into real room rather than off the top of the window.
                body: Align(
                  alignment: Alignment.bottomLeft,
                  child: RailProviderPill(
                    notifier: notifier,
                    networks: networks,
                    selection: selection,
                    enablement: enablement,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return networks;
  }

  // The word is not "No provider", which is what the picker inside the menu
  // calls the same state. A menu row is a choice and may be named for what it
  // is not; a readout is a statement and has to say what is true — and what is
  // true is that the agents are billing the accounts this machine signed into.
  testWidgets('with no provider chosen it names the subscription', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text(kRailSubscriptionLabel), findsOneWidget);
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('No provider'), findsNothing);
  });

  testWidgets('with a provider chosen it names the provider', (tester) async {
    await selection.selectNetwork(
      networkId: 'grid-aaf6a46ced4f42f9',
      networkName: 'hp-1-1',
    );
    await pump(tester);

    expect(find.text('hp-1-1'), findsOneWidget);
    expect(find.text(kRailSubscriptionLabel), findsNothing);
  });

  // The pill is the one thing at this end of the rail a person can act on, and
  // the name was already here before it — as ink, unclickable.
  testWidgets('it opens the picker, and picking retargets new agents', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text(kRailSubscriptionLabel));
    await tester.pumpAndSettle();

    // The menu says what a pick does and does not do.
    expect(find.textContaining('New agents only'), findsOneWidget);
    expect(find.text('hp-1-1'), findsOneWidget);

    await tester.tap(find.text('hp-1-1'));
    await tester.pumpAndSettle();

    expect(selection.value.networkId, 'grid-aaf6a46ced4f42f9');
    expect(selection.value.networkName, 'hp-1-1');
    // And the pill now reads the choice back.
    expect(find.text('hp-1-1'), findsOneWidget);
  });

  testWidgets('the way back to no provider is in the same menu', (
    tester,
  ) async {
    await selection.selectNetwork(
      networkId: 'grid-aaf6a46ced4f42f9',
      networkName: 'hp-1-1',
    );
    await pump(tester);

    await tester.tap(find.text('hp-1-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kNoGridTargetLabel).first);
    await tester.pumpAndSettle();

    expect(selection.value.hasGrid, isFalse);
    expect(find.text(kRailSubscriptionLabel), findsOneWidget);
  });

  // The switch in Settings ▸ Providers means "do not offer me this one", and
  // this menu is one of the two places it acts on.
  //
  // ⚠️ The switch is thrown BEFORE the pump, not after. `setEnabled` writes its
  // file, and a real `File.writeAsString` never completes inside `testWidgets`'
  // fake-async zone — awaiting one mid-test hangs the whole run rather than
  // failing it. Same trap `SnapshotStore` documents; the state this test is
  // about is the state the menu is built from, so setting it up front is both
  // safe and what it actually means to assert.
  testWidgets('a provider switched off is not offered here', (tester) async {
    unawaited(enablement.setEnabled('grid-aaf6a46ced4f42f9', false));
    expect(enablement.isEnabled('grid-aaf6a46ced4f42f9'), isFalse);
    await pump(tester);

    await tester.tap(find.text(kRailSubscriptionLabel));
    await tester.pumpAndSettle();

    expect(find.text('hp-1-1'), findsNothing);
    expect(find.text('Water Grid'), findsOneWidget);
  });

  testWidgets('the menu carries a way into the provider pane', (tester) async {
    await pump(tester);

    await tester.tap(find.text(kRailSubscriptionLabel));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('rail-provider-settings-item')),
      findsOneWidget,
    );
    expect(find.text('Provider settings…'), findsOneWidget);
  });
}
