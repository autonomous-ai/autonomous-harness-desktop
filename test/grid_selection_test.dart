// What picking a grid is for: it has to survive a relaunch, it has to reach the
// `agent_create` frame, and — the part that is easy to get wrong — it has to
// leave that frame untouched when nobody picked anything.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/harness_file_store.dart';
import 'package:harness/grid/grid_agent_override.dart';
import 'package:harness/grid/grid_selection_store.dart';

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
    test('a selection is a grid and nothing else', () async {
      final store = storeOnDisk();
      await store.selectNetwork(networkId: 'grid-1', networkName: 'Office');
      expect(store.value.networkId, 'grid-1');
      expect(store.value.label, 'Office');
    });

    // A model left by an older build named no particular agent, so there is nothing to carry
    // forward and reading it back would resurrect the global choice this change removes.
    test('ignores a model persisted by an older build', () async {
      final first = storeOnDisk();
      await first.selectNetwork(networkId: 'grid-1', networkName: 'Office');
      await HarnessFileStore(directory: dir).write('grid_selected_model', 'GLM-4.7-Flash');

      final next = storeOnDisk();
      await next.load();
      expect(next.value.networkId, 'grid-1');
    });

    test(
      'clearing goes back to no grid, and that survives a relaunch',
      () async {
        final first = storeOnDisk();
        await first.selectNetwork(networkId: 'grid-1', networkName: 'Office');
        await first.clear();

        final next = storeOnDisk();
        await next.load();

        expect(next.value.hasGrid, isFalse);
      },
    );

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
        ),
        model: 'GLM-4.7-Flash',
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

    test('the model comes from the caller, not the store', () async {
      final override = await resolveGridAgentOverride(
        client: FakeGridApi(),
        selection: const GridSelection(
          networkId: 'grid-abc',
          networkName: 'autonomous.ai',
        ),
        model: 'GLM-4.7-Flash',
      );
      expect(override!.model, 'GLM-4.7-Flash');
    });

    test('no model means the grid chooses', () async {
      final override = await resolveGridAgentOverride(
        client: FakeGridApi(),
        selection: const GridSelection(
          networkId: 'grid-abc',
          networkName: 'autonomous.ai',
        ),
      );
      expect(override!.model, isNull);
      expect(override.toJson().containsKey('model'), isFalse);
    });
  });
}
