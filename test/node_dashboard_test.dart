import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/grid_overview.dart';
import 'package:harness/grid/node_dashboard_layout.dart';
import 'package:harness/grid/node_dashboard_view.dart';

/// The captured relay answer — one real grid, anonymised. A hand-written list
/// would have none of the shapes these rules exist for: a node that has served
/// nothing, one the relay never timed, one advertising three models, and two
/// platforms in the same fleet.
List<OverviewNode> _onlineNodes() {
  final overview = GridOverview.fromJson(
    jsonDecode(File('test/fixtures/grid_overview.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  return [
    for (final node in overview.nodes)
      if (node.online) node,
  ];
}

List<String> _names(List<OverviewNode> nodes) => [
  for (final node in nodes) node.name,
];

void main() {
  final nodes = _onlineNodes();

  group('sorting', () {
    test('input tokens ranks by FRESH input, not by the raw total', () {
      // beta-machine-01 reads the most of anything (368M in), but 337M of it
      // was cache — 31M fresh. beta-machine-07 reads less in total (185M) and
      // more that was actually new (59M), so it leads. Ranking on `tokensIn`
      // would put a machine re-reading one cached prompt all day at the top.
      final sorted = sortNodes(nodes, NodeSortKey.inputTokens);
      expect(sorted.first.name, 'beta-machine-07');
      expect(sorted[1].name, 'beta-machine-01');
      expect(
        sorted.first.answered!.tokensIn,
        lessThan(sorted[1].answered!.tokensIn),
      );
    });

    test('a machine nobody has timed sinks below every measured one', () {
      // The whole point: "never measured" must not sort like "measured zero".
      // Two nodes report no decode rate at all; both land at the bottom, in
      // name order, under the machine measured at 10 tok/s.
      final sorted = sortNodes(nodes, NodeSortKey.throughput);
      expect(_names(sorted).sublist(sorted.length - 2), [
        'gamma-machine-02',
        'gamma-machine-05',
      ]);
      expect(sorted[sorted.length - 3].name, 'alpha-machine-03');
      expect(sorted[sorted.length - 3].throughputTokS, 10.0);
    });

    test('a measured zero still outranks an unmeasured reading', () {
      // gamma-machine-02 answered a real, measured 0 requests; the relay sent
      // no rollup at all for a node without one. The measured zero goes first.
      final withoutRollup = OverviewNode.fromJson(const {
        'name': 'never-asked',
        'online': true,
      });
      final sorted = sortNodes([withoutRollup, ...nodes], NodeSortKey.requests);
      expect(sorted.last.name, 'never-asked');
      expect(sorted[sorted.length - 2].answered!.requests, 0);
    });

    test('every order is total and stable, so a poll never reshuffles', () {
      for (final key in NodeSortKey.values) {
        final once = _names(sortNodes(nodes, key));
        final twice = _names(sortNodes(sortNodes(nodes, key), key));
        expect(twice, once, reason: '$key');
        expect(once.length, nodes.length, reason: '$key');
      }
    });

    test('name order is the one that does not move under you', () {
      expect(_names(sortNodes(nodes, NodeSortKey.name)), [
        'alpha-machine-00',
        'alpha-machine-03',
        'alpha-machine-06',
        'beta-machine-01',
        'beta-machine-04',
        'beta-machine-07',
        'gamma-machine-02',
        'gamma-machine-05',
      ]);
    });

    test('sorting leaves the caller its own list', () {
      final before = _names(nodes);
      sortNodes(nodes, NodeSortKey.outputTokens);
      expect(_names(nodes), before);
    });
  });

  group('the menus', () {
    test("lists the models the grid's machines advertise, `auto` dropped", () {
      final models = nodeDashboardModels(nodes);
      expect(models, isNot(contains('auto')));
      // The three-model node contributes all three; a media capability is
      // listed under its human name.
      expect(models.map(modelLabel), contains('Image generation'));
      expect(models, contains('qwen/qwen3.8-27b'));
      // The id keeps the spelling its node advertises, not a lower-cased one.
      expect(models, isNot(contains('qwen/qwen3.8-27b'.toUpperCase())));
    });

    test('offers only the platforms actually here', () {
      expect(nodeDashboardPlatforms(nodes), ['Linux', 'macOS']);
    });

    test('keeps naming a model whose last machine went offline', () {
      // Dropping back to "All models" would say the dashboard is showing
      // everything at the moment it is showing nothing.
      expect(modelLabelForKey(const [], 'glm-4.7-flash'), 'glm-4.7-flash');
    });
  });

  group('filtering', () {
    test('a model filter keeps only the machines serving it', () {
      final view = const NodeDashboardView().showingModel('gemma-4-31b-it');
      expect(_names(applyNodeDashboardView(nodes, view)), [
        'alpha-machine-00',
        'alpha-machine-03',
      ]);
      expect(view.isFiltered, isTrue);
    });

    test('a platform filter reads the label, not the wire value', () {
      final view = const NodeDashboardView().showingPlatform('Linux');
      expect(applyNodeDashboardView(nodes, view), hasLength(3));
    });

    test('a node that named no platform is excluded by any platform filter', () {
      // Treating "didn't say" as a match puts a machine under a heading it may
      // not belong to, with no way for the reader to tell which rows were
      // guesses.
      final silent = OverviewNode.fromJson(const {
        'name': 'no-platform',
        'online': true,
      });
      final view = const NodeDashboardView().showingPlatform('macOS');
      expect(applyNodeDashboardView([silent], view), isEmpty);
    });

    test('reordering hides nothing, so a sort is not a filter', () {
      expect(
        const NodeDashboardView().sortedBy(NodeSortKey.name).isFiltered,
        isFalse,
      );
    });

    test('clearing keeps the order and drops both filters', () {
      final view = const NodeDashboardView()
          .sortedBy(NodeSortKey.memory)
          .showingModel('gemma-4-31b-it')
          .showingPlatform('macOS');
      expect(view.unfiltered, const NodeDashboardView(sort: NodeSortKey.memory));
    });
  });

  group('the subtitle', () {
    test('prints the ratio only while a filter is hiding something', () {
      // Unfiltered it would read "8 of 8" on every grid, which trains the eye
      // to skip the one line that warns it cards are missing.
      expect(nodeDashboardSubtitle(8, 8), startsWith('8 machines serving'));
      expect(nodeDashboardSubtitle(8, 2), startsWith('2 of 8 machines'));
    });

    test('the noun agrees with the total, not with what is shown', () {
      expect(nodeDashboardSubtitle(9, 1), contains('1 of 9 machines'));
      expect(nodeDashboardSubtitle(1, 1), contains('1 machine serving'));
    });

    test('an empty grid says so instead of counting to zero', () {
      expect(nodeDashboardSubtitle(0, 0), isNot(contains('0 machines serving')));
    });
  });

  group('the layout', () {
    test('never divides by zero, whatever the first layout pass reports', () {
      expect(dashboardColumns(0), 1);
      expect(dashboardColumns(-40), 1);
      expect(dashboardColumns(200), 1);
    });

    test('adds a column only once a whole card fits beside the last', () {
      const gap = kNodeCardGap;
      const target = kNodeCardTargetWidth;
      expect(dashboardColumns(target * 2 + gap), 2);
      expect(dashboardColumns(target * 2 + gap - 1), 1);
      expect(dashboardColumns(target * 3 + gap * 2), 3);
    });
  });

  group('the store', () {
    test('remembers the choice, and hands back a new value each time', () {
      final store = NodeDashboardViewStore();
      addTearDown(store.dispose);
      var notified = 0;
      store.addListener(() => notified++);

      store.sortBy(NodeSortKey.requests);
      store.showModel('GLM-4.7-Flash');
      expect(store.value.sort, NodeSortKey.requests);
      // Keyed, so a filter set from one spelling matches a node advertising
      // another.
      expect(store.value.model, 'glm-4.7-flash');

      store.clearFilters();
      expect(store.value.model, isNull);
      // The order survives a clear — it was never what was hiding anything.
      expect(store.value.sort, NodeSortKey.requests);
      expect(notified, 3);
    });
  });
}
