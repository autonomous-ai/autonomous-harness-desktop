// The two surfaces that CHANGE a provider: the create dialog, and the delete in
// the detail panel. What they guard is who may see them at all — a non-owner has
// no delete, and an account whose email provider is public is not offered the
// domain rule — so those are what these pin.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_access_type.dart';
import 'package:harness/grid/grid_models_controller.dart';
import 'package:harness/grid/grid_mutations_controller.dart';
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/grid/provider_enablement_store.dart';
import 'package:harness/settings/sections/grid_section.dart';
import 'package:harness/share/grid_cli.dart';
import 'package:harness/shared/theme/app_theme.dart';

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

class _Api extends FakeGridApi {
  _Api({this.canRestrictToDomain = false});

  /// Flipped on to check that the domain rule appears only when the control
  /// plane says this account may use it.
  final bool canRestrictToDomain;

  final List<({String name, GridAccessType type})> created = [];
  final List<String> deleted = [];
  final List<({String id, String name})> renamed = [];

  @override
  Future<GridMe> me() async {
    final payload = Map<String, dynamic>.from(kGridMePayload);
    payload['user'] = {
      ...Map<String, dynamic>.from(payload['user'] as Map),
      'can_restrict_to_domain': canRestrictToDomain,
    };
    return GridMe.fromJson(payload);
  }

  @override
  Future<GridNetwork> createNetwork({
    required String name,
    required GridAccessType type,
  }) async {
    created.add((name: name, type: type));
    return GridNetwork.fromJson({
      'network_id': 'grid-new',
      'name': name,
      'owner_email': 'huy@example.com',
      'network_type': type.wire,
      'status': 'active',
      'router_enabled': false,
      'router_advisors': const [],
    });
  }

  @override
  Future<void> deleteNetwork(String networkId) async => deleted.add(networkId);

  @override
  Future<void> renameNetwork(String networkId, {required String name}) async =>
      renamed.add((id: networkId, name: name));
}

class _Cli extends GridCli {
  _Cli() : super(environment: const {'HOME': '/tmp/fake-home'});

  @override
  Future<String?> locate() async => '/usr/local/bin/grid';

  @override
  Future<GridCliResult> run(List<String> arguments) async =>
      const GridCliResult(exitCode: 0, stdout: '', stderr: '');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<GridMutationsController> pump(
    WidgetTester tester,
    _Api api, {
    GridSelectionStore? selection,
  }) async {
    // The window the app actually opens at — at 800x600 the table's viewport is
    // one row tall and the second grid is never built.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final networks = GridNetworksController(client: api);
    final mutations = GridMutationsController(
      client: api,
      cli: _Cli(),
      networks: networks,
      selection: selection ?? GridSelectionStore(storage: _MemoryStore()),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            AppTheme.brightness.value = Brightness.light;
            return BrightnessScope(
              child: Scaffold(
                body: GridSection(
                  controller: networks,
                  selection: selection ?? GridSelectionStore(
                    storage: _MemoryStore(),
                  ),
                  mutations: mutations,
                  // Its own, never the singleton: that one holds a real client
                  // and would reach for the developer's own Grid session.
                  models: GridModelsController(client: api),
                  // Its own, pointed at a temp file: the singleton writes the
                  // developer's real ~/.harness, and a test run must not.
                  enablement: ProviderEnablementStore(
                    file: File(
                      '${Directory.systemTemp.createTempSync('providers').path}'
                      '/providers_config.json',
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return mutations;
  }

  group('create', () {
    testWidgets('the button opens the form and a name makes a grid', (
      tester,
    ) async {
      final api = _Api();
      await pump(tester, api);

      await tester.tap(find.byKey(const Key('grid-create-button')));
      await tester.pumpAndSettle();
      expect(find.text('Create provider'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('create-grid-name-field')),
        'new grid',
      );
      await tester.tap(find.byKey(const Key('create-grid-submit')));
      await tester.pumpAndSettle();

      expect(api.created.single.name, 'new grid');
      // The dialog closes itself and the pane says what happened.
      expect(find.text('Create provider'), findsNothing);
      expect(find.text('Provider “new grid” created.'), findsOneWidget);
    });

    testWidgets('reopening after a success shows a usable form', (
      tester,
    ) async {
      final api = _Api();
      await pump(tester, api);

      // One successful create leaves the controller in CreateGridDone.
      await tester.tap(find.byKey(const Key('grid-create-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create-grid-name-field')),
        'first grid',
      );
      await tester.tap(find.byKey(const Key('create-grid-submit')));
      await tester.pumpAndSettle();
      expect(api.created.length, 1);

      // Reopening must not slam shut on the state left from last time.
      await tester.tap(find.byKey(const Key('grid-create-button')));
      await tester.pumpAndSettle();
      expect(find.text('Create provider'), findsOneWidget,
          reason: 'the form stays open on a stale Done state');

      await tester.enterText(
        find.byKey(const Key('create-grid-name-field')),
        'second grid',
      );
      await tester.tap(find.byKey(const Key('create-grid-submit')));
      await tester.pumpAndSettle();
      expect(api.created.length, 2);
      expect(api.created.last.name, 'second grid');
    });

    testWidgets('an invalid name is refused without a round-trip', (
      tester,
    ) async {
      final api = _Api();
      await pump(tester, api);

      await tester.tap(find.byKey(const Key('grid-create-button')));
      await tester.pumpAndSettle();
      // Already taken — the fixture's second grid.
      await tester.enterText(
        find.byKey(const Key('create-grid-name-field')),
        'Water Grid',
      );
      await tester.tap(find.byKey(const Key('create-grid-submit')));
      await tester.pumpAndSettle();

      expect(api.created, isEmpty);
      expect(find.textContaining('already have a provider'), findsOneWidget);
      // The form stays open, with the name still in it to correct.
      expect(find.text('Create provider'), findsOneWidget);
    });

    testWidgets('the domain rule is offered only when the account may use it', (
      tester,
    ) async {
      await pump(tester, _Api());
      await tester.tap(find.byKey(const Key('grid-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-grid-access-field')));
      await tester.pumpAndSettle();
      expect(find.text('Invite only'), findsWidgets);
      // The rule's own label, not the account email the pane prints behind the
      // dialog — that one also contains the domain.
      expect(find.textContaining('@example.com emails'), findsNothing);
      expect(find.text('My domain'), findsNothing);
      await tester.tap(find.text('Public').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await pump(tester, _Api(canRestrictToDomain: true));
      await tester.tap(find.byKey(const Key('grid-create-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-grid-access-field')));
      await tester.pumpAndSettle();
      // Named by the domain it admits, not "My domain".
      expect(find.textContaining('@example.com emails'), findsWidgets);
    });
  });

  group('delete', () {
    testWidgets('a grid you own offers it, behind a confirm', (tester) async {
      final api = _Api();
      await pump(tester, api);

      // The owned provider is the first row; selecting it puts its actions in
      // the detail panel beside the rail. Keyed rather than found by text:
      // the panel prints the same name, so the text is not unique.
      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      // The confirm names what is lost rather than asking "are you sure?".
      expect(find.textContaining('removes everyone on it'), findsOneWidget);

      await tester.tap(find.byKey(const Key('provider-delete-confirm')));
      await tester.pumpAndSettle();
      expect(api.deleted, ['grid-aaf6a46ced4f42f9']);
      expect(find.text('Deleted "hp-1-1".'), findsOneWidget);
    });

    testWidgets('cancelling the confirm deletes nothing', (tester) async {
      final api = _Api();
      await pump(tester, api);

      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(api.deleted, isEmpty);
    });

    // The server refuses a non-owner anyway; an action that can only fail is
    // worse than one that was never offered.
    testWidgets('a grid somebody else owns offers no delete', (tester) async {
      await pump(tester, _Api());

      await tester.tap(
        find.byKey(const Key('provider-row-grid-e3b210eacc5b4cdf')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
    });
  });


  /// Renaming is a double-click on the provider's name — there is no button.
  ///
  /// ⚠️ `pump`, never `pumpAndSettle`, between the two taps: settling stops as
  /// soon as no frame is scheduled, which is a few milliseconds, so a settle
  /// here would still be inside kDoubleTapTimeout and the NEXT tap in a test
  /// would pair with this one instead.
  Future<void> doubleClickName(WidgetTester tester, String networkId) async {
    final name = find.byKey(Key('provider-name-$networkId'));
    await tester.tap(name);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(name);
    await tester.pumpAndSettle();
  }

  group('rename', () {
    testWidgets('opens on the current name and saves a new one', (
      tester,
    ) async {
      final api = _Api();
      await pump(tester, api);

      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      await doubleClickName(tester, 'grid-aaf6a46ced4f42f9');

      // The field arrives holding the name it is about to replace.
      final field = tester.widget<TextField>(
        find.byKey(const Key('rename-grid-name-field')),
      );
      expect(field.controller?.text, 'hp-1-1');

      await tester.enterText(
        find.byKey(const Key('rename-grid-name-field')),
        'hp-2',
      );
      await tester.tap(find.byKey(const Key('rename-grid-submit')));
      await tester.pumpAndSettle();

      expect(api.renamed.single.name, 'hp-2');
      expect(find.text('Rename provider'), findsNothing);
      expect(find.text('Renamed to "hp-2".'), findsOneWidget);
    });

    // Saving the name it already has is a no-op, not a round-trip.
    testWidgets('an unchanged name just closes', (tester) async {
      final api = _Api();
      await pump(tester, api);

      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      await doubleClickName(tester, 'grid-aaf6a46ced4f42f9');
      await tester.tap(find.byKey(const Key('rename-grid-submit')));
      await tester.pumpAndSettle();

      expect(api.renamed, isEmpty);
      expect(find.text('Rename provider'), findsNothing);
      // Nothing happened, so nothing is announced.
      expect(find.textContaining('Renamed to'), findsNothing);
    });

    testWidgets('a duplicate name is refused, and the form stays', (
      tester,
    ) async {
      final api = _Api();
      await pump(tester, api);

      await tester.tap(
        find.byKey(const Key('provider-row-grid-aaf6a46ced4f42f9')),
      );
      await tester.pumpAndSettle();
      await doubleClickName(tester, 'grid-aaf6a46ced4f42f9');
      await tester.enterText(
        find.byKey(const Key('rename-grid-name-field')),
        'Water Grid',
      );
      await tester.tap(find.byKey(const Key('rename-grid-submit')));
      await tester.pumpAndSettle();

      expect(api.renamed, isEmpty);
      expect(find.textContaining('already have a provider'), findsOneWidget);
      expect(find.text('Rename provider'), findsOneWidget);
    });

    testWidgets('a grid somebody else owns offers no rename', (tester) async {
      await pump(tester, _Api());

      await tester.tap(
        find.byKey(const Key('provider-row-grid-e3b210eacc5b4cdf')),
      );
      await tester.pumpAndSettle();
      // No name to double-click, and no button either: a provider somebody
      // else owns answers 403 to a rename.
      expect(
        find.byKey(const Key('provider-name-grid-e3b210eacc5b4cdf')),
        findsNothing,
      );
      expect(find.text('Rename'), findsNothing);
    });
  });
}
