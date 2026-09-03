/// What `grid catalog` says this exact machine should run, ready to download.
///
/// The local route's empty state used to be a picker with nothing in it and a
/// link. The link went to the right place — but a screen whose only content is
/// "there is nothing here" leaves the reader to work out what to want, and the
/// CLI already knows: it ranks a couple of models against this Mac's memory,
/// chip and backend, and that answer costs one spawn.
///
/// Deliberately a *short* list. The shelf — every GGUF the catalogue carries —
/// is the model manager's job and stays one press away; this is the two or
/// three picks that make the first download a decision rather than research.
library;

import 'package:flutter/foundation.dart';

import '../grid/grid_api_client.dart';
import 'catalog_models.dart';
import 'grid_cli.dart';
import 'pull_spec.dart';

/// One recommendation, as the empty state draws it.
class RecommendedPick {
  const RecommendedPick({
    required this.repoId,
    required this.file,
    this.minVramGb,
    this.sizeBytes,
    this.specs = const [],
  });

  /// `unsloth/Qwen3.6-35B-A3B-MTP-GGUF`.
  final String repoId;

  /// The exact GGUF the CLI would land on disk. `grid catalog` names it, which
  /// is what makes "is this one already here?" answerable without a download.
  final String file;

  /// The memory the CLI says this needs. Its own figure, not ours — omitted
  /// rather than guessed when the row does not carry one.
  final int? minVramGb;

  /// What the download weighs. Only the shelf knows it, so it is null until
  /// [RecommendedModelsController] has asked, and stays null if the ask failed.
  final int? sizeBytes;

  /// What `grid pull` is given, one entry per file — every shard of a split
  /// set, so a model never lands with a hole in it. Falls back to the CLI's own
  /// `<repo>:<file>` when the shelf could not be reached.
  final List<String> specs;

  /// The name a person would use: the repo's tail, without the GGUF marker.
  String get name {
    final tail = repoId.contains('/') ? repoId.split('/').last : repoId;
    return tail.replaceFirst(RegExp(r'[-_]?GGUF$', caseSensitive: false), '');
  }

  /// The quantisation, read off the filename — `UD-IQ3_S` in
  /// `Qwen3.6-35B-A3B-UD-IQ3_S.gguf`. Null when the name carries no tag.
  String? get quant {
    final match = RegExp(
      r'[._-]((?:UD-|i1-|imat-)?I?Q\d+(?:_\w+)*|F16|F32|BF16)\.gguf$',
      caseSensitive: false,
    ).firstMatch(file);
    return match?.group(1);
  }

  RecommendedPick withVersion(ModelVersion version) => RecommendedPick(
    repoId: repoId,
    file: file,
    minVramGb: minVramGb,
    sizeBytes: version.sizeBytes > 0 ? version.sizeBytes : null,
    specs: versionPullSpecs(urls: version.urls, pullSpec: version.pullSpec),
  );

  static RecommendedPick? fromCatalogRow(Object? row) {
    if (row is! Map) return null;
    final repoId = row['hf_repo'];
    final file = row['file'];
    if (repoId is! String || repoId.isEmpty) return null;
    if (file is! String || file.isEmpty) return null;
    return RecommendedPick(
      repoId: repoId,
      file: file,
      minVramGb: (row['min_vram_gb'] as num?)?.toInt(),
      specs: ['$repoId:$file'],
    );
  }
}

/// This computer, in the one line the empty state prints above the picks.
///
/// Every part is a figure the CLI sent. A machine that answers with less prints
/// less, and one that answers with nothing prints nothing — the line is there
/// to say the picks were ranked against *this* Mac, and a made-up spec would
/// undo exactly that.
String? machineSummary(Map<String, dynamic>? deviceInfo) {
  if (deviceInfo == null) return null;
  final parts = <String>[];
  final cpu = deviceInfo['cpu'];
  if (cpu is Map && cpu['brand'] is String) {
    parts.add(cpu['brand'] as String);
  }
  final memory = deviceInfo['memory'];
  if (memory is Map && memory['total_gb'] is num) {
    parts.add('${(memory['total_gb'] as num).round()} GB memory');
  }
  final disk = deviceInfo['disk'];
  if (disk is Map && disk['free_gb'] is num) {
    parts.add('${(disk['free_gb'] as num).round()} GB free');
  }
  if (parts.isNotEmpty) return parts.join(' · ');
  // The CLI's own sentence, when the structured fields are not the shape this
  // build expects. Still its measurement, not ours.
  final detected = deviceInfo['detected'];
  return detected is String && detected.isNotEmpty ? detected : null;
}

/// Loads the picks, and the machine they were picked for.
class RecommendedModelsController extends ChangeNotifier {
  RecommendedModelsController({GridCli? cli, GridApiClient? api})
    : _cli = cli ?? GridCli(),
      _api = api ?? GridApiClient();

  final GridCli _cli;
  final GridApiClient _api;

  /// More than three is a shelf, and the shelf has its own screen.
  static const int maxPicks = 3;

  List<RecommendedPick> picks = const [];
  String? machine;
  bool loading = false;

  bool _loaded = false;
  bool _disposed = false;

  /// Ask once. The recommendation is a fact about this machine, and this
  /// machine does not change while the window is open.
  Future<void> load() async {
    if (_loaded || loading) return;
    loading = true;
    _notify();

    final rows = await _cli.runJson<List<dynamic>>(['catalog']);
    final device = await _cli.runJson<Map<String, dynamic>>(['device-info']);
    machine = machineSummary(device);
    final found = [
      for (final row in rows ?? const []) ?RecommendedPick.fromCatalogRow(row),
    ].take(maxPicks).toList();

    // Sizes come from the shelf, one call per pick. A pick whose detail fails
    // keeps its name, its memory figure and a working Download — losing the
    // whole row because the weight is unknown would be the wrong trade.
    picks = await Future.wait([for (final pick in found) _withSize(pick)]);
    loading = false;
    _loaded = true;
    _notify();
  }

  Future<RecommendedPick> _withSize(RecommendedPick pick) async {
    try {
      final detail = await _api.catalogDetail(pick.repoId);
      final version = _versionFor(pick, detail);
      return version == null ? pick : pick.withVersion(version);
    } on Object {
      return pick;
    }
  }

  /// The version that lands as the file the CLI named, else nothing.
  ///
  /// Matched on the filename rather than the quant label, because the two are
  /// written differently — `UD-IQ3_S` in a name, `IQ3_S` in a label — and a
  /// near-match here would report the wrong download size for the right model.
  static ModelVersion? _versionFor(RecommendedPick pick, ModelDetail detail) {
    for (final version in detail.versions) {
      final names = [
        for (final url in version.urls) url.split('/').last,
        if (version.pullSpec != null) pullSpecFileName(version.pullSpec!),
      ];
      if (names.any(
        (name) => name != null && name.toLowerCase() == pick.file.toLowerCase(),
      )) {
        return version;
      }
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
