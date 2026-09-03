import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/grid_overview.dart';
import 'package:harness/grid/grid_overview_controller.dart';

Map<String, dynamic> _node({
  String name = 'mac',
  bool online = true,
  double? vramGb = 192,
  double? vramUsedMb = 98304,
  double? gpuUtilPct = 20,
  double? throughput = 15.7,
  int? concurrency = 1,
  String? planType,
  Map<String, dynamic>? answered,
}) => {
  'name': name,
  'online': online,
  'chip': 'Apple M2 Ultra',
  'device': 'Mac Studio',
  'vram_gb': vramGb,
  'vram_total_mb': vramGb == null ? null : vramGb * 1024,
  'vram_used_mb': vramUsedMb,
  'gpu_util_pct': gpuUtilPct,
  'throughput_tok_s': throughput,
  'max_concurrency': concurrency,
  'plan_type': planType,
  'models': ['gemma-4-31b-it'],
  if (answered != null) 'answered': answered,
};

GridOverview _overview({
  List<Map<String, dynamic>>? nodes,
  Map<String, dynamic>? stats,
  Map<String, dynamic>? answered,
  int modelCount = 2,
}) => GridOverview.fromJson({
  'grid': {'state': 'running'},
  'stats': stats ?? {'models': modelCount, 'nodes': 1},
  'answered': answered,
  'models': [
    for (var i = 0; i < modelCount; i++) {'id': 'model-$i'},
  ],
  'nodes': nodes ?? [_node()],
});

void main() {
  group('what the grid is made of', () {
    test('sums only the machines that are up', () {
      final power = gridPowerFrom(
        _overview(
          nodes: [
            _node(vramGb: 192, vramUsedMb: 98304),
            _node(name: 'off', online: false, vramGb: 192),
          ],
        ),
      );
      expect(power.onlineNodes, 1);
      expect(power.vramGb, 192);
      expect(power.vramUsedGb, 96);
    });

    test('a subscription seat brings a plan, not memory', () {
      // Its RAM never runs a model for the grid, so counting it would inflate
      // the pool with capacity nobody can use.
      final power = gridPowerFrom(
        _overview(
          nodes: [
            _node(vramGb: 192, vramUsedMb: 98304),
            _node(name: 'seat', planType: 'pro', vramGb: 64, vramUsedMb: 8192),
          ],
        ),
      );
      expect(power.vramGb, 192);
      expect(power.vramUsedGb, 96);
      // It is still a machine that is online and answering.
      expect(power.onlineNodes, 2);
    });

    test('a figure nobody reported stays null, never zero', () {
      final power = gridPowerFrom(
        _overview(
          nodes: [
            _node(vramGb: null, vramUsedMb: null, gpuUtilPct: null, throughput: null),
          ],
          stats: {'models': 0, 'nodes': 1},
          modelCount: 0,
        ),
      );
      expect(power.vramGb, isNull);
      expect(power.vramUsedGb, isNull);
      expect(power.gpuUtilPct, isNull);
      expect(power.throughputTokS, isNull);
      // Nothing honest to draw beats an empty circle beside a total.
      expect(power.share, isNull);
    });

    test('the ring falls back to GPU load, and says which it is', () {
      final power = gridPowerFrom(
        _overview(nodes: [_node(vramUsedMb: null, gpuUtilPct: 40)]),
      );
      expect(power.ringIsMemory, isFalse);
      expect(power.share, closeTo(0.4, 0.001));
    });

    test('the relay wins on capacity, because it does the dispatching', () {
      final power = gridPowerFrom(
        _overview(
          nodes: [_node(concurrency: 1), _node(name: 'b', concurrency: 1)],
          stats: {'models': 2, 'nodes': 2, 'concurrent_capacity': 61},
        ),
      );
      expect(power.parallel, 61);
    });

    test('and the node sum is the fallback when it does not say', () {
      final power = gridPowerFrom(
        _overview(
          nodes: [_node(concurrency: 4), _node(name: 'b', concurrency: 3)],
        ),
      );
      expect(power.parallel, 7);
    });

    test('the model list wins over a stats count the relay under-reports', () {
      final power = gridPowerFrom(
        _overview(stats: {'models': 0, 'nodes': 1}, modelCount: 10),
      );
      expect(power.models, 10);
    });
  });

  group('what was answered', () {
    test('the work figure is fresh input, not everything', () {
      // Total tokens is dominated by cache hits that cost almost nothing.
      final overview = _overview(
        answered: const {
          'window_seconds': 86400,
          'tokens_in': 539964042,
          'tokens_cached': 447552937,
          'tokens_out': 7574401,
          'requests': 8469,
        },
      );
      expect(overview.answered!.freshInput, 92411105);
      expect(formatTokens(overview.answered!.freshInput), '92.4M');
    });

    test('a relay that reported none says none, rather than zero', () {
      expect(_overview().answered, isNull);
      expect(gridPowerFrom(_overview()).answered, isNull);
    });
  });

  group('how the figures read', () {
    test('memory switches unit at the scale it is read at', () {
      expect(formatMemoryGb(1740), '1.7 TB');
      expect(formatMemoryGb(192), '192 GB');
      expect(formatMemoryGb(4.5), '4.5 GB');
      expect(formatMemoryPair(1024, 1740), '1.0 / 1.7 TB');
      expect(formatMemoryPair(96, 192), '96 / 192 GB');
    });

    test('tokens read the way people say them', () {
      expect(formatTokens(92411105), '92.4M');
      expect(formatTokens(8469), '8.5k');
      expect(formatTokens(912), '912');
      expect(formatTokens(2400000000), '2.4B');
    });

    test('a day is 24h, because that is how people say it', () {
      // "1d" in "what this machine did today" reads as a unit conversion.
      expect(formatWindow(86400), '24h');
      expect(formatWindow(172800), '2d');
      expect(formatWindow(3600), '1h');
      expect(formatWindow(900), '15m');
      // No span reported is no suffix — a made-up window would misrepresent a
      // real number.
      expect(formatWindow(0), '');
    });
  });

  group('a machine on the grid', () {
    test('names its hardware without saying the same thing twice', () {
      final node = OverviewNode.fromJson(_node());
      expect(node.hardware, 'Apple M2 Ultra · Mac Studio');
      final same = OverviewNode.fromJson({
        ..._node(),
        'device': 'Apple M2 Ultra',
      });
      expect(same.hardware, 'Apple M2 Ultra');
    });

    test('falls back to the total when no vram_gb was sent', () {
      final node = OverviewNode.fromJson({
        ..._node(vramGb: null),
        'vram_total_mb': 196608.0,
      });
      expect(node.poolVramGb, 192);
    });
  });
}
