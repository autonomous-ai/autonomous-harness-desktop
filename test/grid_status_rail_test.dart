import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/grid/grid_api_client.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/theme/app_theme.dart';
import 'package:harness/grid/grid_credentials.dart';
import 'package:harness/grid/grid_overview.dart';
import 'package:harness/grid/grid_overview_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/grid/provider_enablement_store.dart';
import 'package:harness/grid/managed_network_member.dart';
import 'package:harness/grid/member_usage.dart';
import 'package:harness/usage/usage_controller.dart';
import 'package:harness/usage/usage_source.dart';
import 'package:harness/usage/usage_window.dart';
import 'package:harness/widgets/status_rail/grid_status_rail.dart';
import 'package:harness/widgets/status_rail/pill_panel_shell.dart';
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
  _Api({this.fails = false, this.memberCount = 33});

  bool fails;
  final int? memberCount;
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
  Future<List<ManagedNetworkMember>?> members(String networkId) async =>
      memberCount == null
      ? null
      : [
          for (var i = 0; i < memberCount!; i++)
            ManagedNetworkMember.fromJson({
              'email': 'person$i@example.com',
              'roles': const ['consumer'],
            }),
        ];

  @override
  Future<({int windowSeconds, Map<String, MemberUsage> byEmail})?> memberUsage({
    required String baseUrl,
    required String apiKey,
  }) async => null;
}

/// One agent account's rate limits, fixed, so the strip's no-grid half can be
/// read without shelling out to a vendor CLI.
class _StubUsageSource implements UsageSource {
  _StubUsageSource(this.reading);

  final ProviderUsage reading;

  @override
  UsageProvider get provider => reading.provider;

  @override
  Future<ProviderUsage> read() async => reading;
}

/// A controller holding [readings], already settled.
///
/// `autoStart: false` and one explicit [UsageController.refresh]: the live one
/// starts a periodic timer, and a timer is a `pumpAndSettle` that never
/// settles.
Future<UsageController> _usageWith(List<ProviderUsage> readings) async {
  final controller = UsageController(
    sources: [for (final reading in readings) _StubUsageSource(reading)],
    autoStart: false,
  );
  await controller.refresh();
  return controller;
}

Future<GridOverviewController> _pump(
  WidgetTester tester, {
  _Api? api,
  UsageController? usage,
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
  // The rail's provider pill needs one for its settings row; nothing in these
  // tests opens Settings, so a bare notifier is enough.
  final notifier = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
  );
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            GridStatusRail(
              notifier: notifier,
              controller: controller,
              usage: usage,
              // The same store the controller reads, or the pill would name a
              // provider whose figures the rail is not showing.
              selection: selection,
              enablement: ProviderEnablementStore(
                file: File(
                  '${Directory.systemTemp.createTempSync('providers').path}'
                  '/providers_config.json',
                ),
              ),
            ),
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
    // `formatVramShare` writes the unit once, from the total, and trims a
    // trailing `.0` — 1024 GB of 1740 is "1 / 1.7 TB".
    expect(find.text('1 / 1.7 TB'), findsOneWidget);
    expect(find.text('92.4M'), findsOneWidget);
    // The figure names what it counts on screen, not only to a screen reader:
    // a bare `92.4M / 24h` is a number nobody can read without hovering it.
    expect(find.text(' tokens / 24h'), findsOneWidget);
    // What it is MADE OF, on the right.
    expect(find.text('33'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('with no grid chosen the strip reads the agent accounts', (
    tester,
  ) async {
    final api = _Api();
    final usage = await _usageWith([
      const ProviderUsage(
        provider: UsageProvider.claude,
        status: UsageStatus.ok,
        windows: [UsageWindow(label: 'Session', usedPercent: 12)],
      ),
    ]);
    addTearDown(usage.dispose);
    final controller = await _pump(
      tester,
      api: api,
      usage: usage,
      withGrid: false,
    );

    // A rate limit belongs to an account rather than to a grid, so this is a
    // substitution and not a fallback: the strip answers the question it can.
    expect(find.text('12% used'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    // And with no grid there is nothing to ask a relay about.
    expect(api.overviewCalls, 0);
    controller.dispose();
  });

  testWidgets('a nearly-spent window colours its own figure', (tester) async {
    // The whole point of looking down here unprompted. `19% used` and
    // `92% used` used to print in exactly the same ink, which made the strip
    // useless for the one question it can answer at a glance.
    final usage = await _usageWith([
      const ProviderUsage(
        provider: UsageProvider.claude,
        status: UsageStatus.ok,
        // Two, not three: at this window width a third figure overflows the
        // rail, and this test is about ink rather than layout.
        windows: [
          UsageWindow(label: 'Session', usedPercent: 12),
          UsageWindow(label: 'Fable', usedPercent: 92),
        ],
      ),
    ]);
    addTearDown(usage.dispose);
    final controller = await _pump(tester, usage: usage, withGrid: false);

    Color inkOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;
    expect(inkOf('12% used'), grid.AppPalette.textSecondary);
    expect(inkOf('92% used'), AppColors.danger);
    controller.dispose();
  });

  testWidgets('and warns in amber before it turns red', (tester) async {
    final usage = await _usageWith([
      const ProviderUsage(
        provider: UsageProvider.claude,
        status: UsageStatus.ok,
        windows: [UsageWindow(label: 'Weekly', usedPercent: 84)],
      ),
    ]);
    addTearDown(usage.dispose);
    final controller = await _pump(tester, usage: usage, withGrid: false);

    expect(
      tester.widget<Text>(find.text('84% used')).style!.color,
      grid.AppPalette.warn,
    );
    controller.dispose();
  });

  testWidgets('an account nobody signed into here leaves the strip empty', (
    tester,
  ) async {
    final api = _Api();
    final usage = await _usageWith([
      const ProviderUsage(
        provider: UsageProvider.claude,
        status: UsageStatus.signedOut,
        message: 'Sign in to Claude to see usage',
      ),
    ]);
    addTearDown(usage.dispose);
    final controller = await _pump(
      tester,
      api: api,
      usage: usage,
      withGrid: false,
    );

    // A figure-shaped blank that will never fill is worse than nothing, so an
    // account with no session contributes no figures at all — the reason there
    // are none belongs in the panel, where there is room to say it.
    expect(find.textContaining('% used'), findsNothing);
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

  // The bug this pins: the work figure is `Flexible`, and a flex child is given
  // the free space as its constraint. Without an `Align` inside it the figure
  // centres itself in that space, and `93.9M tokens / 24h` drifts out to the
  // middle of the strip with a gap on either side — worse the wider the window,
  // which is why this measures against the rail's own width rather than against
  // a pixel count that happens to hold at one size.
  testWidgets('the work figure stays left, beside the cluster it follows', (
    tester,
  ) async {
    final controller = await _pump(tester);
    // Wider than `_pump`'s default: free space is what a stretching child
    // misuses, and the real window has far more of it than 1000px.
    tester.view.physicalSize = const Size(1900, 460);
    await tester.pumpAndSettle();

    final memory = tester.getRect(find.text('1 / 1.7 TB'));
    final work = tester.getRect(find.textContaining('92.4M'));
    final counts = tester.getRect(find.text('33'));

    // It sits against the block it follows, not adrift between that block and
    // the counts at the far end. Measured as a share of the space between the
    // two, so the assertion means the same at any window width: centred in the
    // flex the figure lands near the middle of that span, and against the
    // cluster it lands at the very start of it.
    final span = counts.left - memory.right;
    // The gap to the block before it is the SAME gap the counts keep between
    // each other — `RailHoverTarget`'s own padding, twice, which is how every
    // pair on this strip is spaced. That is the real assertion: not a pixel
    // count, but that this figure is spaced like its neighbours rather than
    // pushed out into the middle by the Spacer past it.
    final nodes = tester.getRect(find.text('8'));
    final betweenCounts = nodes.left - counts.right;
    expect(
      work.left - memory.right,
      lessThan(betweenCounts * 2),
      reason: 'the figure is spaced like a figure, not adrift mid-rail',
    );
    // And it is nowhere near the middle of the run to the counts.
    expect((work.left - memory.right) / span, lessThan(0.35));
    controller.dispose();
  });

  testWidgets('a roster we may not read shows no member figure', (
    tester,
  ) async {
    // Owner-only on the server: "we may not ask" and "nobody is here" must not
    // render the same.
    final controller = await _pump(tester, api: _Api(memberCount: null));

    expect(find.text('33'), findsNothing);
    expect(find.text('8'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('the panel is a card, not the window', (tester) async {
    // The bug this pins: an OverlayEntry whose `Positioned` has no offsets is a
    // NON-positioned overlay child, and those are laid out with tight
    // constraints — the panel then covered the whole window and its own width
    // was ignored.
    tester.view.physicalSize = const Size(1000, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _pump(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('1 / 1.7 TB')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(PillPanelSurface));
    expect(panel.width, 312);
    // Its own height, not the window's — which is what the bug looked like.
    final window = tester.getRect(find.byType(MaterialApp));
    expect(panel.height, lessThan(window.height));
    // It opens UPWARD: there is nothing below a strip on the window's bottom
    // edge.
    final rail = tester.getRect(find.byType(GridStatusRail));
    expect(panel.bottom, lessThanOrEqualTo(rail.top + 1));
    controller.dispose();
  });

  testWidgets('the pointer survives the gap between figure and panel', (
    tester,
  ) async {
    // The panel hangs 8px above the rail, and a pointer reaching it crosses
    // that band — which belongs to neither. Without a beat of grace the panel
    // closed there, so nothing inside it could be clicked.
    tester.view.physicalSize = const Size(1000, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await _pump(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('1 / 1.7 TB')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(PillPanelSurface), findsOneWidget);

    // Into the dead band between the two.
    final rail = tester.getRect(find.byType(GridStatusRail));
    final panel = tester.getRect(find.byType(PillPanelSurface));
    await gesture.moveTo(
      Offset(panel.center.dx, (panel.bottom + rail.top) / 2),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(PillPanelSurface), findsOneWidget);

    // And onto the panel, which claims it before the grace runs out.
    await gesture.moveTo(panel.center);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(PillPanelSurface), findsOneWidget);
    controller.dispose();
  });

  testWidgets('a pointer that keeps going closes it', (tester) async {
    // The grace is a beat, not a latch.
    final controller = await _pump(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('1 / 1.7 TB')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(PillPanelSurface), findsOneWidget);

    await gesture.moveTo(const Offset(500, 20));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(PillPanelSurface), findsNothing);
    controller.dispose();
  });

  testWidgets('a click pins it, so its links can be reached', (tester) async {
    final controller = await _pump(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('1 / 1.7 TB')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 / 1.7 TB').first);
    await tester.pumpAndSettle();

    // Pointer well away, panel still up.
    await gesture.moveTo(const Offset(500, 20));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(PillPanelSurface), findsOneWidget);
    controller.dispose();
  });

  testWidgets('a figure opens its panel on hover', (tester) async {
    final controller = await _pump(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    // The memory reading, not the name: the name is the provider pill now, and
    // a button that opens a menu must not also open a panel on hover.
    await gesture.moveTo(tester.getCenter(find.text('1 / 1.7 TB')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // The hardware panel: the grid's name, its uptime, and the memory split.
    expect(find.text('IN USE'), findsOneWidget);
    expect(find.text('SELF-HOST'), findsOneWidget);
    controller.dispose();
  });
}
