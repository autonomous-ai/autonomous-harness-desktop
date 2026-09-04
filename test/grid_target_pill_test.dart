// The sidebar's grid picker. The choice used to live in Settings ▸ Grid alone, so what is asserted
// here is the part that is new: the rail says which grid new agents use without being asked, and
// changing it is one menu rather than a screen.
//
// The rows are built by a pure function so the three states a menu is awkward to open in — mid-load,
// after a failure, on an account with no grids — are covered without a widget at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/grid_target_pill.dart';

import 'support/fake_grid_api.dart';

/// The pill writes the pick straight through to disk; tests keep it in memory.
class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

GridNetworksState _ready() => GridNetworksReady(
  GridMe.fromJson(Map<String, dynamic>.from(kGridMePayload)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gridTargetMenuOptions', () {
    test('own login is always first, and needs no fetch to be offered', () {
      for (final state in [
        const GridNetworksIdle(),
        const GridNetworksLoading(),
        const GridNetworksFailed('token expired'),
        _ready(),
      ]) {
        final first = gridTargetMenuOptions(state).first;
        expect(first.label, kOwnLoginTargetLabel);
        expect(first.networkId, isNull);
        expect(first.enabled, isTrue);
      }
    });

    test('every grid on the account is a pick', () {
      final options = gridTargetMenuOptions(_ready());
      expect(options.map((o) => o.label), [
        kOwnLoginTargetLabel,
        'hp-1-1',
        'Water Grid',
      ]);
      expect(options.last.networkId, 'grid-e3b210eacc5b4cdf');
    });

    // Loading, failed and empty must not render as the same row — a menu that says nothing while it
    // waits is indistinguishable from one that has answered with nothing.
    test('waiting, failing and having none each say so, and none is a pick', () {
      for (final (state, text) in [
        (const GridNetworksLoading(), 'Loading grids…'),
        (const GridNetworksFailed('token expired'), 'token expired'),
        (
          GridNetworksReady(GridMe.fromJson(const {'user': {}, 'networks': []})),
          'This account is on no grids',
        ),
      ]) {
        final rest = gridTargetMenuOptions(state).skip(1).toList();
        expect(rest.single.label, text);
        expect(rest.single.enabled, isFalse);
      }
    });
  });

  group('GridTargetPill', () {
    late GridSelectionStore selection;
    late GridNetworksController networks;

    setUp(() {
      selection = GridSelectionStore(storage: _MemoryStore());
      networks = GridNetworksController(client: FakeGridApi());
      addTearDown(networks.dispose);
    });

    Future<void> pump(WidgetTester tester) async {
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      tester.view.physicalSize = const Size(900 * 2, 700 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.dark),
          home: Scaffold(
            // The pill sits at the foot of the rail and its menu opens upward, so the test gives it
            // the same shape: a narrow column with room above it to land in.
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: 240,
                child: GridTargetPill(
                  notifier: notifier,
                  networks: networks,
                  selection: selection,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the rail states the target without being asked', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('NEW AGENTS USE'), findsOneWidget);
      expect(find.text(kOwnLoginTargetLabel), findsOneWidget);

      await selection.selectNetwork(
        networkId: 'grid-aaf6a46ced4f42f9',
        networkName: 'hp-1-1',
      );
      await tester.pump();
      expect(find.text('hp-1-1'), findsOneWidget);
      expect(find.text(kOwnLoginTargetLabel), findsNothing);
    });

    testWidgets('picking a grid in the menu is the whole trip', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('rail-grid-target-button')));
      await tester.pumpAndSettle();

      // Opening the menu is what fetches; nothing loads for a rail nobody opened.
      expect(find.text('Water Grid'), findsOneWidget);
      await tester.tap(find.text('Water Grid'));
      await tester.pumpAndSettle();

      expect(selection.value.networkId, 'grid-e3b210eacc5b4cdf');
      expect(selection.value.networkName, 'Water Grid');
      // And the pill it was opened from now reads back the choice.
      expect(find.text('Water Grid'), findsOneWidget);
    });

    testWidgets('own login is reachable again once a grid is picked', (
      tester,
    ) async {
      await selection.selectNetwork(
        networkId: 'grid-aaf6a46ced4f42f9',
        networkName: 'hp-1-1',
      );
      await pump(tester);
      await tester.tap(find.byKey(const Key('rail-grid-target-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(kOwnLoginTargetLabel).last);
      await tester.pumpAndSettle();
      expect(selection.value.hasGrid, isFalse);
    });
  });
}
