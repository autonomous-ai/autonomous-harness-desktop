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
import 'package:harness/widgets/node_dashboard/node_dashboard_screen.dart';

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

  @override
  Future<List<ManagedNetworkMember>?> members(String networkId) async => null;
}

/// The app the rail lives in, reduced to the one thing this file is about: a
/// screen with the link that opens the dashboard.
///
/// Pumped as a real route stack rather than the screen alone, because what is
/// under test *is* the navigation — that the dashboard arrives as a route over
/// the shell and that leaving it puts the shell back.
class _Shell extends StatelessWidget {
  const _Shell({required this.controller, required this.store, this.onInvite});

  final GridOverviewController controller;
  final NodeDashboardViewStore store;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showNodeDashboardScreen(
          context,
          controller: controller,
          store: store,
          onInvite: onInvite,
        ),
        child: const Text('View dashboard'),
      ),
    ),
  );
}

typedef _Dash = ({GridOverviewController controller, NodeDashboardViewStore store});

/// Pumps the shell, opens the dashboard through the link, runs [body], then
/// disposes the controller.
///
/// The dispose has to happen inside the test body: [GridOverviewController]
/// holds a periodic timer, and the framework checks for pending timers before
/// it runs any `addTearDown`, so registering it there fails every test with
/// "A Timer is still pending".
Future<void> _withScreen(
  WidgetTester tester, {
  List<Map<String, dynamic>>? nodes,
  VoidCallback? onInvite,
  Size size = const Size(1280, 900),
  bool open = true,
  required Future<void> Function(_Dash dash) body,
}) async {
  grid.AppTheme.brightness.value = Brightness.light;
  tester.view.physicalSize = size;
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
      home: _Shell(controller: controller, store: store, onInvite: onInvite),
    ),
  );
  await tester.pumpAndSettle();
  if (open) {
    await tester.tap(find.text('View dashboard'));
    await tester.pumpAndSettle();
  }
  await body((controller: controller, store: store));
  // Tear the route stack down before disposing: the screen listens to the
  // controller, and disposing one still mounted makes the next frame throw
  // "used after being disposed" — a fact about this harness, not the screen.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  controller.dispose();
}

/// Every machine name the dashboard will show, scrolling to reach the rows the
/// lazy list has not built yet.
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

  testWidgets('the link opens a screen, not a dialog', (tester) async {
    await _withScreen(tester, body: (dash) async {
      // The whole point of the change: no `Dialog` anywhere, and the shell that
      // launched it is gone from the tree rather than greyed out behind a scrim.
      expect(find.byType(NodeDashboardScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
      expect(find.text('Nodes'), findsOneWidget);
    });
  });

  testWidgets('the screen fills the window it was opened over', (tester) async {
    await _withScreen(tester, body: (dash) async {
      // A dialog inset itself by 40×32 and capped at 1180×860; a screen takes
      // the window. Measured against the view, so this fails the moment the
      // screen grows an inset or a max width of its own.
      final size = tester.getSize(find.byType(NodeDashboardScreen));
      expect(size.width, 1280);
      expect(size.height, 900);
    });
  });

  testWidgets('the header names the grid these machines serve', (tester) async {
    await _withScreen(tester, body: (dash) async {
      // The screen has room the dialog did not, and the name is what the person
      // clicked through from — the rail's panel is titled with it.
      expect(
        find.text(
          'autonomous.ai · 8 machines serving · readings refresh with the '
          'grid overview',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('every machine is still drawn, one card each', (tester) async {
    await _withScreen(tester, body: (dash) async {
      expect(await _allMachines(tester), hasLength(8));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a wider window lays the same cards out in more columns', (
    tester,
  ) async {
    // What the screen was for. The dialog stopped widening at 1180, so past
    // that point a wider display bought no extra column; the screen keeps
    // reflowing until its own ceiling.
    late int narrow;
    await _withScreen(tester, size: const Size(900, 900), body: (dash) async {
      narrow = tester.widgetList<NodeDashboardCard>(
        find.byType(NodeDashboardCard),
      ).length;
    });
    await _withScreen(tester, size: const Size(1900, 900), body: (dash) async {
      final wide = tester.widgetList<NodeDashboardCard>(
        find.byType(NodeDashboardCard),
      ).length;
      expect(wide, greaterThan(narrow));
    });
  });

  testWidgets('back to app leaves the screen and restores the shell', (
    tester,
  ) async {
    await _withScreen(tester, body: (dash) async {
      expect(find.byType(NodeDashboardScreen), findsOneWidget);
      await tester.tap(find.text('Back to app'));
      await tester.pumpAndSettle();
      expect(find.byType(NodeDashboardScreen), findsNothing);
      // The way back landed on the shell, not on a blank route.
      expect(find.text('View dashboard'), findsOneWidget);
    });
  });

  testWidgets('the filters survive leaving and coming back', (tester) async {
    // The store outlives the screen, which is why it is handed in rather than
    // made here — a filter set, a glance at a terminal, and back should not
    // silently reset to all machines.
    await _withScreen(tester, body: (dash) async {
      dash.store.showModel('qwen3.6-35b-a3b');
      await tester.pumpAndSettle();
      expect(find.byType(NodeDashboardCard), findsOneWidget);

      await tester.tap(find.text('Back to app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View dashboard'));
      await tester.pumpAndSettle();

      expect(find.byType(NodeDashboardCard), findsOneWidget);
      expect(find.text('gamma-machine-02'), findsOneWidget);
    });
  });

  testWidgets("an empty grid's offer leaves this screen before it pushes", (
    tester,
  ) async {
    // Pushing first and popping after would pop the thing just pushed. The
    // offer has to fire with the dashboard already gone.
    var invited = 0;
    await _withScreen(
      tester,
      nodes: const [],
      onInvite: () => invited++,
      body: (dash) async {
        expect(find.text('Add the first machine'), findsOneWidget);
        await tester.tap(find.text('Invite people'));
        await tester.pumpAndSettle();

        expect(invited, 1);
        expect(find.byType(NodeDashboardScreen), findsNothing);
        expect(find.text('View dashboard'), findsOneWidget);
      },
    );
  });
}
