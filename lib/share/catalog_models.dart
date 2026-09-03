/// The Grid model catalogue, as this app reads it.
///
/// The catalogue is the control plane's, not the CLI's. `grid catalog` answers
/// with a handful of picks ranked for *this* machine — good, and far too few to
/// browse; the shelf itself is `POST /v1/grid/catalog`, which is the same
/// Hugging Face-backed list the Grid app searches. Both are used, for the two
/// different questions they answer.
library;

/// One repository in the catalogue list. Repo-level: it names no file, because
/// a repo holds a dozen quantisations and which one this Mac wants is a
/// question only [ModelDetail] can answer.
class CatalogEntry {
  const CatalogEntry({
    required this.repoId,
    required this.downloads,
    required this.likes,
    this.paramsB,
    this.format,
    this.architecture,
    this.file,
  });

  final String repoId;
  final int downloads;
  final int likes;

  /// Parameter count in billions. Null when the catalogue does not know.
  final double? paramsB;

  /// `GGUF`, `safetensors`, …
  final String? format;

  /// `qwen2`, `llama`, `mistral` — from the GGUF metadata when it is there,
  /// else read off the repo id.
  final String? architecture;

  /// The exact GGUF this entry lands on disk as, when the source knew it.
  /// `grid catalog` does; the shelf does not, because a repo is many files.
  final String? file;

  /// What to show as the model's name: the half after the owner.
  String get name => repoId.contains('/') ? repoId.split('/').last : repoId;

  String get owner => repoId.contains('/') ? repoId.split('/').first : '';

  factory CatalogEntry.fromJson(Map<String, dynamic> json) => CatalogEntry(
    repoId: json['repo_id'] as String? ?? '',
    downloads: (json['downloads'] as num?)?.toInt() ?? 0,
    likes: (json['likes'] as num?)?.toInt() ?? 0,
    paramsB: (json['params_b'] as num?)?.toDouble(),
    format: json['format'] as String?,
    architecture: _archLabel(json['arch']),
  );
}

/// How a version reads against the machine that asked.
///
/// The verdict comes from the control plane, which was told this Mac's memory
/// and backend. Every value is a real answer including the unflattering ones —
/// a quant that is too large has to say so, or the only feedback is a download
/// that takes ten minutes and then will not load.
enum VersionStatus {
  runnable('runnable', 'Runs on this Mac'),
  partial('partial', 'Partial — slow'),
  lowQuality('low_quality', 'Runs — lower quality'),
  tooLarge('too_large', 'Too large for memory');

  const VersionStatus(this.wire, this.label);

  final String wire;
  final String label;

  static VersionStatus? fromJson(Object? value) {
    for (final status in VersionStatus.values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}

/// One downloadable quantisation of a model.
class ModelVersion {
  const ModelVersion({
    required this.version,
    required this.sizeBytes,
    required this.pullSpec,
    required this.urls,
    this.status,
    this.maxCtx,
  });

  /// The quant label, `Q5_K_M`. Null when the catalogue did not tag it.
  final String? version;
  final int sizeBytes;

  /// The `<repo>:<file>` spec `grid pull` takes — for the FIRST file only, which
  /// is why [urls] exists. See `pull_spec.dart`.
  final String? pullSpec;

  /// Every file this version is made of. More than one for a split GGUF.
  final List<String> urls;

  final VersionStatus? status;
  final int? maxCtx;

  String get label => version ?? 'default';

  factory ModelVersion.fromJson(Map<String, dynamic> json) => ModelVersion(
    version: json['version'] as String?,
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    pullSpec: json['pull_spec'] as String?,
    urls: [
      for (final url in (json['urls'] as List?) ?? const [])
        if (url is String) url,
    ],
    status: VersionStatus.fromJson(json['status']),
    maxCtx: (json['max_ctx'] as num?)?.toInt(),
  );
}

/// One model, with every version it offers.
class ModelDetail {
  const ModelDetail({
    required this.repoId,
    required this.versions,
    this.name,
    this.paramsB,
    this.architecture,
    this.likes = 0,
    this.downloads = 0,
  });

  final String repoId;
  final List<ModelVersion> versions;
  final String? name;
  final double? paramsB;
  final String? architecture;
  final int likes;
  final int downloads;

  factory ModelDetail.fromJson(Map<String, dynamic> json) => ModelDetail(
    repoId: json['repo_id'] as String? ?? '',
    versions: [
      for (final version in (json['versions'] as List?) ?? const [])
        if (version is Map)
          ModelVersion.fromJson(Map<String, dynamic>.from(version)),
    ],
    name: json['name'] as String?,
    paramsB: (json['params_b'] as num?)?.toDouble(),
    architecture: _archLabel(json['arch']),
    likes: (json['likes'] as num?)?.toInt() ?? 0,
    downloads: (json['downloads'] as num?)?.toInt() ?? 0,
  );
}

String? _archLabel(Object? raw) {
  if (raw is Map) {
    final value = raw['architecture'];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

/// `7B`, `35B`, `1.5B` — how a parameter count is written on a model card.
String? formatParams(double? billions) {
  if (billions == null || billions <= 0) return null;
  return billions >= 10 || billions == billions.roundToDouble()
      ? '${billions.round()}B'
      : '${billions.toStringAsFixed(1)}B';
}

/// `1.2M`, `45k`, `912` — a download count as people write one.
String formatCount(int value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    return '${millions >= 10 ? millions.round() : millions.toStringAsFixed(1)}M';
  }
  if (value >= 1000) return '${(value / 1000).round()}k';
  return '$value';
}
