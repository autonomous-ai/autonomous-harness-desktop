/// What a grid is made of, as its relay reports it.
///
/// `GET {relay}/grid/overview` — the same host that serves the models list, on
/// the same short-lived key. Everything the status rail prints comes from here,
/// so every field is parsed leniently and nothing is invented: a figure the
/// relay did not send is **null**, never zero. The difference matters on this
/// screen more than anywhere else in the app, because a zero is a measurement
/// and a blank is an admission.
library;

/// The grid's own counters.
class GridStats {
  const GridStats({
    required this.models,
    required this.nodes,
    this.concurrentCapacity,
    this.uptimePct,
  });

  final int models;
  final int nodes;

  /// How many requests the relay will dispatch at once.
  final int? concurrentCapacity;
  final double? uptimePct;

  factory GridStats.fromJson(Map<String, dynamic> json) => GridStats(
    models: (json['models'] as num?)?.toInt() ?? 0,
    nodes: (json['nodes'] as num?)?.toInt() ?? 0,
    concurrentCapacity: (json['concurrent_capacity'] as num?)?.toInt(),
    uptimePct: (json['uptime_pct'] as num?)?.toDouble(),
  );
}

/// What was answered inside the relay's rollup window.
class Answered {
  const Answered({
    required this.windowSeconds,
    required this.tokensIn,
    required this.tokensCached,
    required this.tokensOut,
    required this.requests,
  });

  final int windowSeconds;

  /// Tokens read, cached ones included.
  final int tokensIn;

  /// The share of [tokensIn] served from a prompt cache — nearly free, and the
  /// reason input cannot be printed as one number.
  final int tokensCached;
  final int tokensOut;
  final int requests;

  /// Input that was NOT served from cache.
  ///
  /// This is the figure the rail prints, and the choice is deliberate: total
  /// tokens is dominated by cache hits that cost almost nothing, so a grid
  /// re-reading the same prompt all day would show a huge number for very
  /// little work. This is the work.
  int get freshInput => tokensIn - tokensCached;

  factory Answered.fromJson(Map<String, dynamic> json) => Answered(
    windowSeconds: (json['window_seconds'] as num?)?.toInt() ?? 0,
    tokensIn: (json['tokens_in'] as num?)?.toInt() ?? 0,
    tokensCached: (json['tokens_cached'] as num?)?.toInt() ?? 0,
    tokensOut: (json['tokens_out'] as num?)?.toInt() ?? 0,
    requests: (json['requests'] as num?)?.toInt() ?? 0,
  );
}

/// One machine on the grid.
class OverviewNode {
  const OverviewNode({
    required this.name,
    required this.online,
    this.device,
    this.chip,
    this.engine,
    this.planType,
    this.memoryGb,
    this.vramGb,
    this.vramTotalMb,
    this.vramUsedMb,
    this.gpuUtilPct,
    this.throughputTokS,
    this.maxConcurrency,
    this.models = const [],
    this.answered,
  });

  final String name;
  final bool online;
  final String? device;
  final String? chip;
  final String? engine;

  /// A subscription seat names its plan here instead of bringing hardware.
  final String? planType;

  final double? memoryGb;
  final double? vramGb;
  final double? vramTotalMb;
  final double? vramUsedMb;
  final double? gpuUtilPct;
  final double? throughputTokS;
  final int? maxConcurrency;
  final List<String> models;
  final Answered? answered;

  /// A seat relays to a hosted model, so whatever memory its machine reports
  /// never runs anything for the grid. Counting it would inflate the pool with
  /// capacity nobody can use.
  bool get isSubscription => planType != null && planType!.isNotEmpty;

  /// What this machine contributes to the memory pool, in GB, or null when it
  /// contributes none.
  double? get poolVramGb {
    if (isSubscription) return null;
    final gb = vramGb ?? (vramTotalMb == null ? null : vramTotalMb! / 1024);
    return gb == null || gb <= 0 ? null : gb;
  }

  /// What to call this machine's hardware in one line.
  String get hardware => [
    if (chip != null && chip!.isNotEmpty) chip!,
    if (device != null && device!.isNotEmpty && device != chip) device!,
  ].join(' · ');

  factory OverviewNode.fromJson(Map<String, dynamic> json) => OverviewNode(
    name: json['name'] as String? ?? '',
    online: json['online'] == true,
    device: json['device'] as String?,
    chip: json['chip'] as String?,
    engine: json['engine'] as String?,
    planType: json['plan_type'] as String?,
    memoryGb: (json['memory_gb'] as num?)?.toDouble(),
    vramGb: (json['vram_gb'] as num?)?.toDouble(),
    vramTotalMb: (json['vram_total_mb'] as num?)?.toDouble(),
    vramUsedMb: (json['vram_used_mb'] as num?)?.toDouble(),
    gpuUtilPct: (json['gpu_util_pct'] as num?)?.toDouble(),
    throughputTokS: (json['throughput_tok_s'] as num?)?.toDouble(),
    maxConcurrency: (json['max_concurrency'] as num?)?.toInt(),
    models: [
      for (final model in (json['models'] as List?) ?? const [])
        if (model is String) model,
    ],
    answered: json['answered'] is Map
        ? Answered.fromJson(Map<String, dynamic>.from(json['answered'] as Map))
        : null,
  );
}

/// One model the grid advertises.
class OverviewModel {
  const OverviewModel({
    required this.id,
    this.name,
    this.maker,
    this.modality,
    this.contextLength,
    this.status,
  });

  final String id;
  final String? name;
  final String? maker;
  final String? modality;
  final int? contextLength;
  final String? status;

  String get label => name?.isNotEmpty == true ? name! : id;

  factory OverviewModel.fromJson(Map<String, dynamic> json) => OverviewModel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String?,
    maker: json['maker'] as String?,
    modality: json['modality'] as String?,
    contextLength: (json['context_length'] as num?)?.toInt(),
    status: json['status'] as String?,
  );
}

/// The whole answer.
class GridOverview {
  const GridOverview({
    required this.stats,
    required this.models,
    required this.nodes,
    this.state,
    this.answered,
  });

  final GridStats stats;
  final List<OverviewModel> models;
  final List<OverviewNode> nodes;
  final String? state;

  /// What the WHOLE grid answered — read this rather than summing [nodes].
  ///
  /// A node is listed only while its heartbeat is live, so a machine that
  /// served all morning and then went offline takes its tokens out of a summed
  /// total, and the relay's per-node rollup separately drops rows it cannot
  /// attribute. Summing is quietly low, by an amount that moves as machines
  /// come and go.
  final Answered? answered;

  bool get running => state == null || state == 'running';

  factory GridOverview.fromJson(Map<String, dynamic> json) {
    final grid = json['grid'];
    return GridOverview(
      state: grid is Map ? grid['state'] as String? : null,
      stats: GridStats.fromJson(
        json['stats'] is Map
            ? Map<String, dynamic>.from(json['stats'] as Map)
            : const {},
      ),
      models: [
        for (final model in (json['models'] as List?) ?? const [])
          if (model is Map)
            OverviewModel.fromJson(Map<String, dynamic>.from(model)),
      ],
      nodes: [
        for (final node in (json['nodes'] as List?) ?? const [])
          if (node is Map)
            OverviewNode.fromJson(Map<String, dynamic>.from(node)),
      ],
      answered: json['answered'] is Map
          ? Answered.fromJson(
              Map<String, dynamic>.from(json['answered'] as Map),
            )
          : null,
    );
  }
}

/// The grid's hardware, summed over the machines that are actually up.
///
/// Every total stays null unless at least one online node reported that field:
/// a grid where nobody advertises throughput shows no throughput, rather than
/// claiming "0 tok/s".
class GridPower {
  const GridPower({
    required this.onlineNodes,
    required this.models,
    this.vramGb,
    this.vramUsedGb,
    this.gpuUtilPct,
    this.parallel,
    this.throughputTokS,
    this.answered,
  });

  final int onlineNodes;
  final int models;

  /// Total graphics memory across online nodes. Never 0 — absent and "zero GB"
  /// are different claims and only one of them is honest.
  final double? vramGb;

  /// How much of [vramGb] is already spoken for. Summed over the same set of
  /// machines, so the ratio is over one consistent pool.
  final double? vramUsedGb;

  final double? gpuUtilPct;
  final int? parallel;
  final double? throughputTokS;
  final Answered? answered;

  bool get isEmpty => onlineNodes == 0 && models == 0;

  /// What the ring draws, 0–1, or null when there is nothing honest to draw.
  ///
  /// Memory in use first, because it is the figure printed right beside it —
  /// the ring and the text are then the same claim. Failing that, mean GPU
  /// load. Failing both, no ring: an empty circle beside a total would imply a
  /// measurement of zero.
  double? get share {
    final total = vramGb;
    final used = vramUsedGb;
    if (total != null && used != null && total > 0) return used / total;
    final util = gpuUtilPct;
    return util == null ? null : util / 100;
  }

  bool get ringIsMemory => vramGb != null && vramUsedGb != null;
}

/// Derive [GridPower] from an overview. Pure, so the summing rules are testable
/// without a relay.
GridPower gridPowerFrom(GridOverview overview) {
  final online = [
    for (final node in overview.nodes)
      if (node.online) node,
  ];

  double? vram;
  double? vramUsed;
  var utilSum = 0.0;
  var utilNodes = 0;
  int? concurrency;
  double? throughput;

  for (final node in online) {
    final gb = node.poolVramGb;
    if (gb == null) continue;
    vram = (vram ?? 0) + gb;
    // Both live figures follow the pool's own membership rule: whatever
    // `poolVramGb` refused contributes neither a used share nor a utilisation
    // reading, so the ratio is over one consistent set of machines.
    final usedMb = node.vramUsedMb;
    if (usedMb != null && usedMb > 0) vramUsed = (vramUsed ?? 0) + usedMb / 1024;
    final util = node.gpuUtilPct;
    if (util != null && util >= 0) {
      utilSum += util;
      utilNodes++;
    }
  }
  for (final node in online) {
    final max = node.maxConcurrency;
    if (max != null && max > 0) concurrency = (concurrency ?? 0) + max;
    final tokS = node.throughputTokS;
    if (tokS != null && tokS > 0) throughput = (throughput ?? 0) + tokS;
  }

  return GridPower(
    onlineNodes: online.length,
    // The relay sometimes reports `stats.models` as 0 with a populated list,
    // so the list wins when there is one.
    models: overview.models.isNotEmpty
        ? overview.models.length
        : overview.stats.models,
    vramGb: vram,
    vramUsedGb: vramUsed,
    gpuUtilPct: utilNodes == 0 ? null : utilSum / utilNodes,
    // The relay is the authority on how much work it will dispatch: it may cap
    // or oversubscribe what the nodes individually advertise.
    parallel: overview.stats.concurrentCapacity ?? concurrency,
    throughputTokS: throughput,
    answered: overview.answered,
  );
}
