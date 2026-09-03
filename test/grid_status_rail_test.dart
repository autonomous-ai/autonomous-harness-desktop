import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_api_client.dart';
import 'package:harness/grid/grid_credentials.dart';
import 'package:harness/grid/grid_overview.dart';
import 'package:harness/grid/grid_overview_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/widgets/status_rail/grid_status_rail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Api extends GridApiClient {
  _Api({this.fails = false, this.members = 33});

  bool fails;
  final int? members;
  int overviewCalls = 0;

  @override
  Future<GridCredentials> credentials(String networkId) async =>
      GridCredentials(
        networkId: networkId,
        baseUrl: 'https://relay.example/$networkId/relay/v1',
        apiKey: 'gridkey',
      );

  @override
  Future<GridOverview> overview({
    required String baseUrl,
    required String apiKey,
  }) async {
    overviewCalls++;
    if (fails) throw Exception('relay is away');
    return GridOverview.fromJson({
      'grid': {'state': 'running'},
      'stats': {'models': 10, 'nodes': 8, 'concurrent_capacity': 61},
      'answered': {
        'window_seconds': 86400,
        'tokens_in': 539964042,
        'tokens_cached': 447552937,
        'tokens_out': 7574401,
        'requests': 8469,
      },
      'models': [
        for (var i = 0; i < 10; i++) {'id': 'model-$i'},
      ],
      'nodes': [
        for (var i = 0; i < 8; i++)
          {
            'name': 'mac-$i',
            'online': true,
            'chip': 'Apple M2 Ultra',
            'vram_gb': 217.5,
            'vram_used_mb': 131072.0,
            'gpu_util_pct': 20.0,
            'max_concurrency': 1,
          },
      ],
    });
  }

  @override
  Future<int?> memberCount(String networkId) async => members;
}

Future<GridOverviewController> _pump(
  WidgetTester tester, {
  _Api? api,
  bool withGrid = true,
}) async {
  final selection = GridSelectionStore(storage: _MemoryStore());
  if (withGrid) {
    await selection.selectNetwork(
      networkId: 'grid-3378218621364f16',
      networkName: 'autonomous.ai',
    );
  }
  final controller = GridOverviewController(
    api: api ?? _Api(),
    selection: selection,
    // Long enough that no test ever races its own timer.
    interval: const Duration(hours: 1),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            GridStatusRail(controller: controller),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The rail's far end prints the running version. Unmocked, the plugin call
  // never answers under flutter_tester, and the version's placeholder would
  // then breathe forever — which is a `pumpAndSettle` that never settles.
  PackageInfo.setMockInitialValues(
    appName: 'Harness',
    packageName: 'ai.autonomous.harness',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  testWidgets('the rail reads the grid from both ends', (tester) async {
    final controller = await _pump(tester);

    // What this grid IS, on the left.
    expect(find.text('autonomous.ai'), findsOneWidget);
    expect(find.text('1.7 / 1.7 TB'), findsNothing);
    expect(find.text('1.0 / 1.7 TB'), findsOneWidget);
    expect(find.text('92.4M'), findsOneWidget);
    expect(find.text(' / 24h'), findsOneWidget);
    // What it is MADE OF, on the right.
    expect(find.text('33'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('with no grid chosen it says so and asks the relay nothing', (
    tester,
  ) async {
    final api = _Api();
    final controller = await _pump(tester, api: api, withGrid: false);

    expect(find.text('No grid chosen'), findsOneWidget);
    expect(api.overviewCalls, 0);
    controller.dispose();
  });

  test('a failed refresh keeps the figures and marks them stale', () async {
    final api = _Api();
    final selection = GridSelectionStore(storage: _MemoryStore());
    await selection.selectNetwork(
      networkId: 'grid-3378218621364f16',
      networkName: 'autonomous.ai',
    );
    final controller = GridOverviewController(
      api: api,
      selection: selection,
      interval: const Duration(hours: 1),
    );
    await controller.refresh();
    expect(controller.power?.onlineNodes, 8);
    expect(controller.stale, isFalse);

    api.fails = true;
    await controller.refresh();

    // A grid that answered a minute ago has not stopped existing because one
    // request timed out.
    expect(controller.power?.onlineNodes, 8);
    expect(controller.stale, isTrue);
    controller.dispose();
  });

  test('nothing loaded is not stale — there is nothing to keep', () async {
    final controller = GridOverviewController(
      api: _Api(fails: true),
      selection: GridSelectionStore(storage: _MemoryStore()),
      interval: const Duration(hours: 1),
    );
    await controller.refresh();
    expect(controller.stale, isFalse);
    expect(controller.power, isNull);
    controller.dispose();
  });

  testWidgets('a roster we may not read shows no member figure', (
    tester,
  ) async {
    // Owner-only on the server: "we may not ask" and "nobody is here" must not
    // render the same.
    final controller = await _pump(tester, api: _Api(members: null));

    expect(find.text('33'), findsNothing);
    expect(find.text('8'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('a figure opens its panel on hover', (tester) async {
    final controller = await _pump(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('autonomous.ai')));
    await tester.pumpAndSettle();

    expect(find.text('8 machines online, serving 10 models.'), findsOneWidget);
    expect(find.text('Requests at once'), findsOneWidget);
    expect(find.text('61'), findsOneWidget);
    controller.dispose();
  });
}
