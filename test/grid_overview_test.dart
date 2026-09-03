import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/grid_overview.dart';
import 'package:harness/grid/grid_power.dart';
import 'package:harness/grid/node_display.dart';
import 'package:harness/grid/node_metrics.dart';

OverviewNode _node({
  String name = 'mac',
  bool online = true,
  double? vramGb = 192,
  double? vramUsedMb = 98304,
  double? gpuUtilPct = 20,
  double? throughput = 15.7,
  int? concurrency = 1,
  String? planType,
  String platform = 'macos-arm64',
}) => OverviewNode.fromJson({
  'name': name,
  'online': online,
  'chip': 'Apple M2 Ultra',
  'device': 'Mac Studio',
  'platform': platform,
  'vram_gb': vramGb,
  'vram_total_mb': vramGb == null ? null : vramGb * 1024,
  'vram_used_mb': vramUsedMb,
  'gpu_util_pct': gpuUtilPct,
  'throughput_tok_s': throughput,
  'max_concurrency': concurrency,
  'plan_type': planType,
  'models': const ['gemma-4-31b-it'],
});

void main() {
  group('what the grid is made of', () {
    test('sums only the machines that are up', () {
      final power = gridPowerFrom([
        _node(),
        _node(name: 'off', online: false),
      ], 2);
      expect(power.onlineNodes, 1);
      expect(power.vramGb, 192);
      expect(power.vramUsedGb, 96);
    });

    test('a subscription seat brings a plan, not memory', () {
      // Its RAM never runs a model for the grid, so counting it would inflate
      // the pool with capacity nobody can use.
      final seat = _node(
        name: 'seat',
        planType: 'pro',
        vramGb: 64,
        vramUsedMb: 8192,
      );
      expect(nodeIsSubscription(seat), isTrue);
      expect(nodeVramGb(seat), isNull);
      final power = gridPowerFrom([_node(), seat], 2);
      expect(power.vramGb, 192);
      expect(power.vramUsedGb, 96);
      // It is still a machine that is online and answering.
      expect(power.onlineNodes, 2);
    });

    test('a figure nobody reported stays null, never zero', () {
      final power = gridPowerFrom([
        _node(
          vramGb: null,
          vramUsedMb: null,
          gpuUtilPct: null,
          throughput: null,
          concurrency: null,
        ),
      ], 0);
      expect(power.vramGb, isNull);
      expect(power.vramUsedGb, isNull);
      expect(power.gpuUtilPct, isNull);
      expect(power.throughputTokS, isNull);
      expect(power.parallel, isNull);
    });

    test('the relay wins on capacity, because it does the dispatching', () {
      final nodes = [_node(concurrency: 1), _node(name: 'b', concurrency: 1)];
      expect(gridPowerFrom(nodes, 2, capacity: 61).parallel, 61);
      // And the node sum is the fallback when it does not say.
      expect(gridPowerFrom(nodes, 2).parallel, 2);
    });
  });

  group('what was answered', () {
    const answered = {
      'window_seconds': 86400,
      'tokens_in': 539964042,
      'tokens_cached': 447552937,
      'tokens_out': 7574401,
      'requests': 8469,
    };

    test('the work figure is fresh input, not everything', () {
      // Total tokens is dominated by cache hits that cost almost nothing.
      final rollup = NodeAnswered.fromJson(answered);
      expect(rollup.freshInputTokens, 92411105);
      expect(formatCount(rollup.freshInputTokens), '92.4M');
    });

    test('the grid rollup wins over summing the nodes', () {
      // A machine that served all morning and then went offline takes its
      // tokens out of a summed total.
      final power = gridPowerFrom(
        [_node()],
        1,
        gridAnswered: NodeAnswered.fromJson(answered),
      );
      expect(power.answered?.tokensOut, 7574401);
    });

    test('a relay that reported none says none, rather than zero', () {
      expect(gridPowerFrom([_node()], 1).answered, isNull);
    });
  });

  group('how the figures read', () {
    test('memory switches unit at the scale it is read at', () {
      expect(formatVram(1740), '1.7 TB');
      expect(formatVram(192), '192 GB');
      // One unit for both halves, chosen from the total: a comparison written
      // in two units is a puzzle.
      expect(formatVramShare(1024.4, 1740), '1.0 / 1.7 TB');
      expect(formatVramShare(96, 192), '96 / 192 GB');
    });

    test('counts read the way people say them', () {
      expect(formatCount(92411105), '92.4M');
      expect(formatCount(8469), '8.5K');
      expect(formatCount(912), '912');
    });

    test('a day is 24h, because that is how people say it', () {
      // "1d" in "what this machine did today" reads as a unit conversion.
      expect(answeredWindowLabel(86400), '24h');
      expect(answeredWindowLabel(172800), '2d');
      expect(answeredWindowLabel(3600), '1h');
      // No span reported is no suffix — a made-up window would misrepresent a
      // real number.
      expect(answeredWindowLabel(0), '');
    });

    test('unified memory is RAM, not VRAM', () {
      // Calling an Apple Silicon machine's shared pool "VRAM" invites the
      // reader to look for a graphics card that does not exist.
      expect(memoryLabel(_node()), 'RAM');
      expect(memoryLabel(_node(platform: 'linux')), 'VRAM');
    });
  });

  group('naming the machines', () {
    test('trims a prefix only where it is actually repeated', () {
      expect(
        shortenNodeNames(['pods-alpha', 'pods-beta', 'engine-b0dc5f98']),
        ['alpha', 'beta', 'engine-b0dc5f98'],
      );
    });

    test('a machine standing alone keeps its whole name', () {
      expect(shortenNodeNames(['pods-alpha']), ['pods-alpha']);
    });
  });
}
