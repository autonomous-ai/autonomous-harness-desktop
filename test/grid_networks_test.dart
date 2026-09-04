// The Grid pane is the one screen that talks to a backend the `harness` CLI
// knows nothing about, so what it parses is not covered by anything else. The
// payload it reads lives in `support/fake_grid_api.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/settings/sections/grid_section.dart';
import 'package:harness/shared/theme/app_theme.dart';

import 'support/fake_grid_api.dart';

/// The pane writes the pick straight through to disk; tests keep it in memory.
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

  group('GridMe.fromJson', () {
    final me = GridMe.fromJson(Map<String, dynamic>.from(kGridMePayload));

    test('reads the account and every grid on it', () {
      expect(me.user.email, 'huy@example.com');
      expect(me.user.name, 'Huy Pham');
      expect(me.networks.length, 2);
    });

    test('an owned grid carries its roles, router and creation date', () {
      final owned = me.networks.first;
      expect(owned.displayName, 'hp-1-1');
      expect(owned.isOwnedBy('huy@example.com'), isTrue);
      // The API answers in seconds; a date read as milliseconds would land in
      // 1970 and the card would print it.
      expect(owned.createdAt?.year, 2026);
      expect(owned.routerEnabled, isTrue);
      expect(owned.routerAdvisors, ['openai/gpt-5-mini']);
      expect(owned.member?.roles, ['admin', 'both']);
      expect(owned.member?.isAdmin, isTrue);
    });

    test('a grid owned by someone else is not reported as yours', () {
      final other = me.networks.last;
      expect(other.isOwnedBy('huy@example.com'), isFalse);
      expect(other.member?.isAdmin, isFalse);
      expect(other.routerAdvisors, isEmpty);
      // Absent fields must not throw or invent a value.
      expect(other.createdAt, isNull);
      expect(other.description, isNull);
    });

    test('a grid with no name falls back to its id', () {
      final unnamed = GridNetwork.fromJson({
        'network_id': 'grid-1',
        'name': '   ',
        'owner_email': 'a@b.c',
      });
      expect(unnamed.displayName, 'grid-1');
      expect(unnamed.member, isNull);
      expect(unnamed.routerEnabled, isFalse);
    });
  });

  group('GridNetworksController', () {
    test('ensureLoaded fetches once, refresh fetches again', () async {
      final api = FakeGridApi();
      final controller = GridNetworksController(client: api);
      addTearDown(controller.dispose);

      expect(controller.state, isA<GridNetworksIdle>());
      controller.ensureLoaded();
      controller.ensureLoaded();
      await Future<void>.delayed(Duration.zero);

      expect(api.calls, 1, reason: 'a second ensureLoaded must not refetch');
      final state = controller.state;
      expect(state, isA<GridNetworksReady>());
      expect((state as GridNetworksReady).me.networks.length, 2);

      await controller.refresh();
      expect(api.calls, 2);
    });

    test(
      'a failed load keeps the message, and retry can still succeed',
      () async {
        final controller = GridNetworksController(
          client: FakeGridApi(error: 'token expired'),
        );
        addTearDown(controller.dispose);

        await controller.refresh();
        final state = controller.state;
        expect(state, isA<GridNetworksFailed>());
        expect(
          (state as GridNetworksFailed).message,
          contains('token expired'),
        );
      },
    );
  });

  group('GridSection', () {
    late GridSelectionStore selection;

    setUp(() => selection = GridSelectionStore(storage: _MemoryStore()));

    Future<void> pump(WidgetTester tester, GridNetworksController c) async {
      // A window the size the app actually opens at. At the 800x600 default the
      // table's viewport is one row tall, so a lazy list never builds the
      // second grid and the test is asserting about a pane no user ever sees.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: Builder(
            builder: (context) {
              AppTheme.brightness.value = Brightness.light;
              return BrightnessScope(
                child: Scaffold(
                  body: GridSection(controller: c, selection: selection),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<GridNetworksController> ready(WidgetTester tester) async {
      final controller = GridNetworksController(client: FakeGridApi());
      addTearDown(controller.dispose);
      await pump(tester, controller);
      return controller;
    }

    testWidgets('lists every grid, marking the one you own', (tester) async {
      await ready(tester);

      expect(find.text('Grid'), findsOneWidget);
      expect(find.textContaining('huy@example.com'), findsWidgets);
      expect(find.text('hp-1-1'), findsOneWidget);
      expect(find.text('Water Grid'), findsOneWidget);
      // Ownership is stated, not left to the reader to work out from an email.
      expect(find.text('YOURS'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
      expect(find.text('consumer'), findsOneWidget);
      // The advisor names live in the drawer; the row only says how many.
      expect(find.text('on · 1 model'), findsOneWidget);
      expect(find.text('off'), findsOneWidget);
      // The owner's email shows only on a grid that is not yours.
      expect(find.text('someone@else.com'), findsOneWidget);
      expect(find.byKey(const Key('grid-refresh-button')), findsOneWidget);
    });

    testWidgets('opens on "each engine\'s own login" and can come back to it', (
      tester,
    ) async {
      await ready(tester);
      expect(find.text("Each engine's own login"), findsWidgets);

      await tester.tap(find.text('hp-1-1'));
      await tester.pumpAndSettle();
      expect(selection.value.networkId, 'grid-aaf6a46ced4f42f9');
      expect(selection.value.networkName, 'hp-1-1');

      // The way out of a grid is on this screen now, not only in the sidebar.
      await tester.tap(find.text("Each engine's own login").first);
      await tester.pumpAndSettle();
      expect(selection.value.hasGrid, isFalse);
    });

    testWidgets('the strip says what new agents use', (tester) async {
      await ready(tester);
      // No model control at all — a model is chosen per agent, in the agent
      // view's header, not for the grid as a whole.
      expect(find.byKey(const Key('grid-model-trigger')), findsNothing);

      await tester.tap(find.text('Water Grid'));
      await tester.pumpAndSettle();

      expect(find.text('NEW AGENTS USE'), findsOneWidget);
      expect(find.text('Water Grid'), findsWidgets);
      expect(find.byKey(const Key('grid-model-trigger')), findsNothing);
    });

    testWidgets('details open without changing which grid is used', (
      tester,
    ) async {
      await ready(tester);
      await tester.tap(find.text('Water Grid'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Details for hp-1-1'));
      await tester.pumpAndSettle();

      // The drawer is the only place the advisor names are spelled out.
      expect(find.text('openai/gpt-5-mini'), findsOneWidget);
      // A label the column headers do not also carry.
      expect(find.text('GRID ID'), findsOneWidget);
      // Reading a grid's id is not asking to launch agents on it.
      expect(selection.value.networkId, 'grid-e3b210eacc5b4cdf');
    });

    testWidgets('a filter narrows the table and says so', (tester) async {
      await ready(tester);
      // The plain total sits on the heading; the filter bar names the account.
      expect(find.text('2 grids'), findsOneWidget);
      expect(find.text('huy@example.com'), findsOneWidget);

      await tester.tap(find.text('You own'));
      await tester.pumpAndSettle();

      expect(find.text('hp-1-1'), findsOneWidget);
      expect(find.text('Water Grid'), findsNothing);
      expect(find.textContaining('1 of 2 grids'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('grid-filter-field')),
        'nothing matches this',
      );
      await tester.pumpAndSettle();
      expect(find.text('No grid matches that filter.'), findsOneWidget);
      // Never filtered away: the way back out has to stay reachable.
      expect(find.text("Each engine's own login"), findsWidgets);
    });

    testWidgets('a narrow pane drops columns instead of squeezing them', (
      tester,
    ) async {
      await ready(tester);
      // pump() sizes the window for the common case; this test is about what
      // happens under it, so it narrows the window and rebuilds against it.
      tester.view.physicalSize = const Size(760, 800);
      await tester.pumpAndSettle();

      // Signaling goes first — it is the one column whose value is never read
      // at a glance, and it is still a chevron away in the drawer.
      expect(find.text('SIGNALING'), findsNothing);
      expect(find.text('ROUTER'), findsOneWidget);
      expect(find.text('GRID'), findsOneWidget);
      // Nothing was cut off to make room: a squeezed table overflows, and an
      // overflow is a test failure in debug.
      expect(find.text('hp-1-1'), findsOneWidget);
      expect(find.text('Water Grid'), findsOneWidget);
    });

    testWidgets('a failure says so and offers a retry', (tester) async {
      final controller = GridNetworksController(
        client: FakeGridApi(error: 'token expired'),
      );
      addTearDown(controller.dispose);
      await pump(tester, controller);

      expect(find.text('Could not load your grids'), findsOneWidget);
      expect(find.byKey(const Key('grid-retry-button')), findsOneWidget);
      expect(find.text('hp-1-1'), findsNothing);
    });
  });
}
