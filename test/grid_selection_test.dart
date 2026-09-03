// What picking a grid is for: it has to survive a relaunch, it has to reach the
// `agent_create` frame, and — the part that is easy to get wrong — it has to
// leave that frame untouched when nobody picked anything.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/harness_file_store.dart';
import 'package:harness/grid/grid_agent_override.dart';
import 'package:harness/grid/grid_models_controller.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/widgets/grid_selector.dart';

import 'support/fake_grid_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('harness-grid-');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  GridSelectionStore storeOnDisk() =>
      GridSelectionStore(storage: HarnessFileStore(directory: dir));

  group('GridSelectionStore', () {
    test('a choice survives the next launch, model included', () async {
      final first = storeOnDisk();
      await first.selectNetwork(networkId: 'grid-1', networkName: 'Office');
      await first.selectModel('GLM-4.7-Flash');

      // A brand-new store over the same directory — this covers the on-disk
      // format, not just the logic. That `main()` actually calls `load()` is
      // startup_test's job.
      final next = storeOnDisk();
      await next.load();

      expect(next.value.networkId, 'grid-1');
      expect(next.value.label, 'Office');
      expect(next.value.model, 'GLM-4.7-Flash');
    });

    test(
      'switching grids drops the model, which belonged to the old one',
      () async {
        final store = storeOnDisk();
        await store.selectNetwork(networkId: 'grid-1', networkName: 'Office');
        await store.selectModel('GLM-4.7-Flash');

        await store.selectNetwork(networkId: 'grid-2', networkName: 'Water');

        expect(store.value.networkId, 'grid-2');
        expect(
          store.value.model,
          isNull,
          reason: 'a model id is grid-relative',
        );
      },
    );

    test(
      'clearing goes back to no grid, and that survives a relaunch',
      () async {
        final first = storeOnDisk();
        await first.selectNetwork(networkId: 'grid-1', networkName: 'Office');
        await first.clear();

        final next = storeOnDisk();
        await next.load();

        expect(next.value.hasGrid, isFalse);
        expect(next.value.model, isNull);
      },
    );

    test('a model cannot be set without a grid to be relative to', () async {
      final store = storeOnDisk();
      await store.selectModel('GLM-4.7-Flash');
      expect(store.value.model, isNull);
    });

    test(
      'a first-ever launch lands on no selection instead of throwing',
      () async {
        final store = storeOnDisk();
        await store.load();
        expect(store.value, GridSelection.none);
        expect(store.value.hasGrid, isFalse);
      },
    );
  });

  group('resolveGridAgentOverride', () {
    test('no grid picked means no override — the frame is unchanged', () async {
      final api = FakeGridApi();
      final override = await resolveGridAgentOverride(
        client: api,
        selection: GridSelection.none,
      );
      expect(override, isNull);
      expect(
        api.credentialCalls,
        0,
        reason: 'nothing should be minted for a launch that has no grid',
      );
    });

    test('a picked grid mints a fresh relay key for this launch', () async {
      final api = FakeGridApi();
      final override = await resolveGridAgentOverride(
        client: api,
        selection: const GridSelection(
          networkId: 'grid-1',
          networkName: 'Office',
          model: 'GLM-4.7-Flash',
        ),
      );

      expect(api.credentialCalls, 1);
      expect(override!.networkId, 'grid-1');
      expect(override.baseUrl, 'https://grid.example/grid-1/relay/v1');
      expect(override.apiKey, 'relay-key-for-grid-1');
      expect(override.toJson(), {
        'networkId': 'grid-1',
        'networkName': 'Office',
        'baseUrl': 'https://grid.example/grid-1/relay/v1',
        'apiKey': 'relay-key-for-grid-1',
        'model': 'GLM-4.7-Flash',
      });
    });

    test(
      'no model means the grid chooses — the key is left out entirely',
      () async {
        final override = await resolveGridAgentOverride(
          client: FakeGridApi(),
          selection: const GridSelection(
            networkId: 'grid-1',
            networkName: 'Office',
          ),
        );
        expect(override!.toJson().containsKey('model'), isFalse);
      },
    );

    test(
      'a key that cannot be minted throws rather than silently falling back',
      () async {
        await expectLater(
          resolveGridAgentOverride(
            client: FakeGridApi(credentialError: 'expired'),
            selection: const GridSelection(
              networkId: 'grid-1',
              networkName: 'Office',
            ),
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('GridSelector', () {
    Future<void> pump(
      WidgetTester tester, {
      required GridSelectionStore selection,
      required GridNetworksController networks,
      required GridModelsController models,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: Builder(
            builder: (context) {
              AppTheme.brightness.value = Brightness.light;
              return BrightnessScope(
                child: Scaffold(
                  body: SizedBox(
                    width: 280,
                    child: GridSelector(
                      selection: selection,
                      networks: networks,
                      models: models,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with no grid it names the default and offers no model row', (
      tester,
    ) async {
      final selection = storeOnDisk();
      final networks = GridNetworksController(client: FakeGridApi());
      final models = GridModelsController(client: FakeGridApi());
      addTearDown(networks.dispose);
      addTearDown(models.dispose);
      await pump(
        tester,
        selection: selection,
        networks: networks,
        models: models,
      );

      // The caption is the promise: this applies to agents made from now on.
      expect(find.text('New agents use'), findsOneWidget);
      expect(find.text("Each engine's own login"), findsOneWidget);
      expect(find.byKey(const Key('grid-model-row')), findsNothing);
    });

    testWidgets(
      'picking a grid from the menu shows it, and a model row with it',
      (tester) async {
        final selection = storeOnDisk();
        final networks = GridNetworksController(client: FakeGridApi());
        final models = GridModelsController(client: FakeGridApi());
        addTearDown(networks.dispose);
        addTearDown(models.dispose);
        await pump(
          tester,
          selection: selection,
          networks: networks,
          models: models,
        );

        await tester.tap(find.byKey(const Key('grid-picker-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Water Grid').last);
        await tester.pumpAndSettle();

        expect(selection.value.networkId, 'grid-e3b210eacc5b4cdf');
        expect(find.byKey(const Key('grid-model-row')), findsOneWidget);
        // Nothing chosen yet, so the grid decides.
        expect(find.text('Auto'), findsOneWidget);

        await tester.tap(find.byKey(const Key('grid-model-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('GLM-4.7-Flash').last);
        await tester.pumpAndSettle();

        expect(selection.value.model, 'GLM-4.7-Flash');
        // Loaded from the grid that was picked, not some other one.
        expect(
          models.networkId,
          'grid-e3b210eacc5b4cdf',
          reason: 'models must be the chosen grid\'s',
        );
      },
    );
  });
}
