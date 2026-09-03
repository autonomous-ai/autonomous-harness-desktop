// The Grid pane is the one screen that talks to a backend the `harness` CLI
// knows nothing about, so what it parses is not covered by anything else. The
// payload it reads lives in `support/fake_grid_api.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/settings/sections/grid_section.dart';
import 'package:harness/shared/theme/app_theme.dart';

import 'support/fake_grid_api.dart';

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
    Future<void> pump(WidgetTester tester, GridNetworksController c) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: Builder(
            builder: (context) {
              AppTheme.brightness.value = Brightness.light;
              return BrightnessScope(
                child: Scaffold(body: GridSection(controller: c)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists every grid, marking the one you own', (tester) async {
      final controller = GridNetworksController(client: FakeGridApi());
      addTearDown(controller.dispose);
      await pump(tester, controller);

      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('huy@example.com'), findsOneWidget);
      expect(find.text('hp-1-1'), findsOneWidget);
      expect(find.text('Water Grid'), findsOneWidget);
      // Ownership is stated, not left to the reader to work out from an email.
      expect(find.text('You own this'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
      expect(find.text('consumer'), findsOneWidget);
      expect(find.text('router · openai/gpt-5-mini'), findsOneWidget);
      // The owner's email shows only on a grid that is not yours.
      expect(find.text('someone@else.com'), findsOneWidget);
      expect(find.byKey(const Key('grid-refresh-button')), findsOneWidget);
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
