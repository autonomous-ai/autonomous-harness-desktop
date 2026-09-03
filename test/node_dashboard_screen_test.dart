import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_api_client.dart';
import 'package:harness/grid/grid_credentials.dart';
import 'package:harness/grid/grid_overview.dart';
import 'package:harness/grid/grid_overview_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/grid/managed_network_member.dart';
import 'package:harness/grid/node_dashboard_view.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/widgets/node_dashboard/node_dashboard_card.dart';
import 'package:harness/widgets/node_dashboard/node_dashboard_dialog.dart';

import 'support/real_fonts.dart';

class _Store implements LocalKeyValueStore {
  final Map<String, String> v = {};
  @override
  Future<String?> read(String k) async => v[k];
  @override
  Future<void> write(String k, String value) async => v[k] = value;
  @override
  Future<void> delete(String k) async => v.remove(k);
}

/// Answers with the captured relay overview and nothing else — the dashboard
/// reads no roster and no usage.
class _Api extends GridApiClient {
  _Api({this.nodes});

  /// Replaces the fixture's machines. Null serves the real eight.
  final List<Map<String, dynamic>>? nodes;

  @override
  Future<GridCredentials> credentials(String networkId) async =>
      GridCredentials(networkId: networkId, baseUrl: 'x', apiKey: 'y');

  @override
  Future<GridOverview> overview({
    required String baseUrl,
    required String apiKey,
  }) async {
    final body =
        jsonDecode(File('test/fixtures/grid_overview.json').readAsStringSync())
            as Map<String, dynamic>;
    if (nodes != null) body['nodes'] = nodes;
    return GridOverview.fromJson(body);
  }

  /// The dashboard reads no roster; answering null keeps the controller from
  /// reaching for one.
  @override
  Future<List<ManagedNetworkMember>?> members(String networkId) async => null;
}

/// The dashboard, its controller and the store behind its toolbar.
typedef _Dash = ({GridOverviewController controller, NodeDashboardViewStore store});

/// Pumps the dashboard, runs [body] against it, then disposes the controller.
///
/// The dispose has to happen inside the test body: [GridOverviewController]
/// holds a periodic timer, and the framework checks for pending timers before
/// it runs any `addTearDown`, so registering it there fails every test with
/// "A Timer is still pending".
Future<void> _withDashboard(
  WidgetTester tester, {
  List<Map<String, dynamic>>? nodes,
  VoidCallback? onShareIntelligence,
  VoidCallback? onInvite,
  required Future<void> Function(_Dash dash) body,
}) async {
  grid.AppTheme.brightness.value = Brightness.light;
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final selection = GridSelectionStore(storage: _Store());
  await selection.selectNetwork(
    networkId: 'grid-3378218621364f16',
    networkName: 'autonomous.ai',
  );
  final controller = GridOverviewController(
    api: _Api(nodes: nodes),
    selection: selection,
    interval: const Duration(hours: 1),
  );
  final store = NodeDashboardViewStore();
  addTearDown(store.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.light),
      home: NodeDashboardDialog(
        controller: controller,
        store: store,
        onShareIntelligence: onShareIntelligence,
        onInvite: onInvite,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await body((controller: controller, store: store));
  controller.dispose();
}

/// Every machine name the dashboard will show, scrolling to reach the rows the
/// lazy list has not built yet.
///
/// Rows ARE lazy, deliberately — a dashboard of many machines builds only what
/// is on screen — so "one card per machine" cannot be counted in one frame.
Future<List<String>> _allMachines(WidgetTester tester) async {
  final seen = <String>{};
  void collect() {
    for (final card in tester.widgetList<NodeDashboardCard>(
      find.byType(NodeDashboardCard),
    )) {
      seen.add(card.node.name);
    }
  }

  collect();
  final list = find.byType(Scrollable).last;
  for (var i = 0; i < 8; i++) {
    await tester.drag(list, const Offset(0, -320));
    await tester.pumpAndSettle();
    final before = seen.length;
    collect();
    if (seen.length == before) break;
  }
  return seen.toList();
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('draws a card per machine, with what the relay actually said', (
    tester,
  ) async {
    await _withDashboard(tester, body: (dash) async {
      expect(find.text('Nodes'), findsOneWidget);
      expect(
        find.text(
          '8 machines serving · readings refresh with the grid overview',
        ),
        findsOneWidget,
      );
      // Figures that could only come from the captured answer having been
      // parsed: the busiest machine leads the default order, under the model
      // it serves and the decode rate the relay timed (43.7, rounded the way
      // `throughputLabel` rounds).
      expect(find.text('beta-machine-07'), findsOneWidget);
      expect(find.text('deepseek-v4-flash-0731'), findsOneWidget);
      expect(find.text('44'), findsOneWidget);

      expect(await _allMachines(tester), hasLength(8));
    });
  });

  testWidgets('a measured zero and an unmeasured reading look different', (
    tester,
  ) async {
    // The one confusion `node_metrics.dart` exists to prevent, on one card:
    // gamma-machine-02 answered a real, measured 0 requests, and the relay
    // never managed to time it. The first is a number; the second is a dash.
    await _withDashboard(tester, body: (dash) async {
      dash.store.showModel('qwen3.6-35b-a3b');
      await tester.pumpAndSettle();

      expect(find.byType(NodeDashboardCard), findsOneWidget);
      expect(find.text('gamma-machine-02'), findsOneWidget);
      // Measured zeros: input, cached, output and requests all read 0.
      expect(find.text('0'), findsWidgets);
      // Unmeasured: the throughput footer, with the reason on hover.
      expect(
        find.byTooltip('This machine has not served a request yet.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NodeDashboardCard),
          matching: find.text('—'),
        ),
        findsWidgets,
      );
    });
  });

  testWidgets('nothing overflows, in the fonts the app actually draws in', (
    tester,
  ) async {
    // The fixed-extent grid this replaced clipped the tok/s figure off the
    // fullest cards by 22px. Rows sized by their tallest member must not.
    await _withDashboard(tester, body: (dash) async {
      await _allMachines(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the sort menu reorders the cards it is read above', (
    tester,
  ) async {
    await _withDashboard(tester, body: (dash) async {
      expect(dash.store.value.sort, NodeSortKey.inputTokens);

      await tester.tap(find.text('Input tokens'));
      await tester.pumpAndSettle();
      // Every order says what it actually ranks by — the window included,
      // because "Output tokens" without it reads as all-time.
      expect(find.text('Most tokens read in the last 24h'), findsOneWidget);
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();

      expect(dash.store.value.sort, NodeSortKey.name);
      final first = tester
          .widgetList<NodeDashboardCard>(find.byType(NodeDashboardCard))
          .first;
      expect(first.node.name, 'alpha-machine-00');
    });
  });

  testWidgets('a filter narrows the cards but never its own menu', (
    tester,
  ) async {
    await _withDashboard(tester, body: (dash) async {
      await tester.tap(find.text('All platforms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Linux').last);
      await tester.pumpAndSettle();

      expect(dash.store.value.platform, 'Linux');
      expect(find.byType(NodeDashboardCard), findsNWidgets(3));
      expect(
        find.text(
          '3 of 8 machines serving · readings refresh with the grid overview',
        ),
        findsOneWidget,
      );

      // The menu still offers what the GRID has, not what is left after the
      // filter — otherwise this is a filter you can enter and never leave.
      await tester.tap(find.text('Linux').first);
      await tester.pumpAndSettle();
      expect(find.text('macOS'), findsOneWidget);
      await tester.tap(find.text('macOS'));
      await tester.pumpAndSettle();
      expect(dash.store.value.platform, 'macOS');
    });
  });

  testWidgets('filters that match nothing offer the way back', (tester) async {
    await _withDashboard(tester, body: (dash) async {
      dash.store
        ..showPlatform('Linux')
        ..showModel('gemma-4-31b-it');
      await tester.pumpAndSettle();

      // Both gemma machines are Macs, so this pair matches nobody. That is a
      // different fact from an empty grid, and the only one with a button.
      expect(find.byType(NodeDashboardCard), findsNothing);
      expect(find.text('No machine matches'), findsOneWidget);
      await tester.tap(find.text('Show all machines'));
      await tester.pumpAndSettle();
      expect(find.byType(NodeDashboardCard), findsWidgets);
      expect(dash.store.value.isFiltered, isFalse);
    });
  });

  testWidgets('a grid with nothing serving it offers both ways to fill it', (
    tester,
  ) async {
    var shared = 0;
    await _withDashboard(
      tester,
      nodes: const [],
      onShareIntelligence: () => shared++,
      onInvite: () {},
      body: (dash) async {
        expect(find.byType(NodeDashboardCard), findsNothing);
        expect(
          find.text('No machines are serving this grid right now.'),
          findsOneWidget,
        );
        // A filter strip over a grid with nothing to filter is a control that
        // could only ever empty an already-empty pane.
        expect(find.text('Input tokens'), findsNothing);

        await tester.tap(find.text('Share Intelligence'));
        await tester.pumpAndSettle();
        expect(shared, 1);
      },
    );
  });

  testWidgets('an empty grid with nowhere to send anyone draws no buttons', (
    tester,
  ) async {
    await _withDashboard(
      tester,
      nodes: const [],
      body: (dash) async {
        expect(find.text('Add the first machine'), findsOneWidget);
        expect(find.text('Share Intelligence'), findsNothing);
        expect(find.text('Invite people'), findsNothing);
      },
    );
  });
}
