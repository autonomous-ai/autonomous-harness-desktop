import 'dart:io';

import 'grid_paths.dart';

/// The GGUF weights on this computer, as the local route needs to see them.
///
/// Read straight off `~/.grid/models` rather than asked of the CLI. It is a
/// directory listing either way, one spawn cheaper this way, and the picker
/// stays honest about a file the user dropped in themselves — which the CLI
/// serves perfectly well.
class LocalModel {
  const LocalModel({
    required this.file,
    required this.sizeBytes,
    required this.parts,
    this.expectedParts,
  });

  /// The filename to hand `grid join --serve` — the first shard of a split set,
  /// which is how llama.cpp is pointed at one (it finds the siblings itself).
  final String file;

  /// Every byte of the model, shards included, so a split set does not read as
  /// one fifth of its real size.
  final int sizeBytes;

  /// How many files are actually here.
  final int parts;

  /// How many a split set says it needs. Null for a standalone file.
  final int? expectedParts;

  /// Whether every shard landed. A set that is missing one cannot be loaded, so
  /// it is offered as unfinished rather than quietly failing at start.
  bool get isComplete => expectedParts == null || parts >= expectedParts!;

  /// What the model is called once the shard marker and quantisation tag are
  /// off — the name this computer advertises unless the user renames it.
  String get displayName => deriveAdvertiseName(file);
}

/// Matches a llama.cpp split-GGUF shard suffix, `-00001-of-00005.gguf`.
final _splitShard = RegExp(r'-(\d+)-of-(\d+)\.gguf$', caseSensitive: false);

/// Trailing quantisation tag: an optional imatrix marker plus a quant code like
/// `IQ3_S`, `Q4_K_M`, `Q8_0`, `F16`. Anchored to the end.
final _quantSuffix = RegExp(
  r'([._-](UD|i1|imat|imatrix))*[._-]((I?Q\d+(_\w+)*)|F16|F32|BF16|FP16|FP32)$',
  caseSensitive: false,
);

/// `Qwen3.6-35B-A3B-UD-IQ3_S.gguf` -> `Qwen3.6-35B-A3B`.
///
/// What is stripped is what identifies the *file* rather than the model: which
/// shard it is, and how hard it was squashed. Both belong on the disk and
/// neither belongs on a grid, where the name is what somebody picks a model by.
String deriveAdvertiseName(String modelFile) {
  final name = modelFile.split('/').last.replaceFirst(_splitShard, '.gguf');
  final base = name.replaceFirst(RegExp(r'\.gguf$', caseSensitive: false), '');
  final stripped = base.replaceFirst(_quantSuffix, '');
  return stripped.isEmpty ? base : stripped;
}

/// Group a flat list of filenames and sizes into servable models, largest
/// first. Pure, so the shard rules are testable without a disk.
List<LocalModel> groupLocalModels(Map<String, int> filesBySize) {
  final groups = <String, List<MapEntry<String, int>>>{};
  for (final entry in filesBySize.entries) {
    if (!entry.key.toLowerCase().endsWith('.gguf')) continue;
    groups
        .putIfAbsent(entry.key.replaceFirst(_splitShard, ''), () => [])
        .add(entry);
  }
  final models = <LocalModel>[];
  for (final files in groups.values) {
    files.sort((a, b) => a.key.compareTo(b.key));
    final first = files.first.key;
    final expected = _splitShard.firstMatch(first)?.group(2);
    models.add(
      LocalModel(
        file: first,
        sizeBytes: files.fold(0, (sum, entry) => sum + entry.value),
        parts: files.length,
        expectedParts: expected == null ? null : int.tryParse(expected),
      ),
    );
  }
  models.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  return models;
}

/// The models on this computer's disk. Empty — never an exception — when the
/// directory is missing, which is simply a computer that has pulled nothing.
List<LocalModel> readLocalModels({Directory? modelsDir}) {
  final dir = modelsDir ?? GridPaths.modelsDir;
  if (!dir.existsSync()) return const [];
  final sizes = <String, int>{};
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    try {
      sizes[name] = entity.lengthSync();
    } on FileSystemException {
      // A file that vanished mid-scan is one the picker should not offer.
      continue;
    }
  }
  return groupLocalModels(sizes);
}

/// `15 GB`, `900 MB`. Decimal units, because that is what a download is
/// measured in and the number is compared against a download far more often
/// than against a disk.
String modelSizeLabel(int bytes) {
  if (bytes < 1000000000) return '${(bytes / 1e6).round()} MB';
  final gb = bytes / 1e9;
  return gb >= 10 ? '${gb.toStringAsFixed(0)} GB' : '${gb.toStringAsFixed(1)} GB';
}
