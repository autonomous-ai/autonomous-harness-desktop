import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'grid_cli.dart';

/// A model the CLI offers to download for THIS machine.
///
/// The catalog is host-filtered — `grid catalog` answers with what this
/// computer's memory and chip can actually run — so a row here is a model that
/// will work, not one that merely exists.
class CatalogModel {
  const CatalogModel({
    required this.label,
    required this.file,
    required this.minVramGb,
  });

  /// What `grid pull` takes.
  final String label;

  /// The GGUF it lands as, which is how "already downloaded" is answered.
  final String file;
  final int minVramGb;

  factory CatalogModel.fromJson(Map<String, dynamic> json) => CatalogModel(
    label: '${json['label'] ?? ''}',
    file: '${json['file'] ?? ''}',
    minVramGb: json['min_vram_gb'] is int ? json['min_vram_gb'] as int : 0,
  );
}

/// How far a download has got.
class PullProgress {
  const PullProgress({required this.doneMb, this.totalMb, this.percent});

  final double doneMb;
  final double? totalMb;
  final double? percent;

  /// A download whose total the server never declared. Real, and common enough
  /// that it needs a shape rather than a zero — the bar goes indeterminate
  /// instead of sitting at 0% while megabytes land.
  bool get isIndeterminate => percent == null;

  /// `1.2 GB of 15.0 GB`, or `1.2 GB` when the total is unknown.
  String get label {
    String gb(double mb) => mb >= 1000
        ? '${(mb / 1000).toStringAsFixed(1)} GB'
        : '${mb.round()} MB';
    final total = totalMb;
    return total == null ? gb(doneMb) : '${gb(doneMb)} of ${gb(total)}';
  }

  /// Parsed from the CLI's hand-rolled bar, which is `\r`-delimited and comes
  /// in two shapes: `123.4 / 456.7 MB ( 27.0%)`, or a bare `123.4 MB` when the
  /// total is unknown. The one genuinely fragile parser here — a miss shows an
  /// indeterminate bar rather than a wrong number.
  static PullProgress? parse(String chunk) {
    final full = _full.firstMatch(chunk);
    if (full != null) {
      return PullProgress(
        doneMb: double.parse(full[1]!),
        totalMb: double.parse(full[2]!),
        percent: double.parse(full[3]!),
      );
    }
    final mb = _mbOnly.firstMatch(chunk);
    return mb == null ? null : PullProgress(doneMb: double.parse(mb[1]!));
  }

  static final RegExp _full = RegExp(
    r'([\d.]+)\s*/\s*([\d.]+)\s*MB\s*\(\s*([\d.]+)%\)',
  );
  static final RegExp _mbOnly = RegExp(r'([\d.]+)\s*MB');
}

/// Downloads one model, and says how it is going.
///
/// Separate from [ShareController] because the two have nothing to say to each
/// other beyond "the model list changed": a download can be running while
/// nothing is shared, and a share can be running while nothing downloads.
class ModelPullController extends ChangeNotifier {
  ModelPullController({GridCli? cli}) : _cli = cli ?? GridCli();

  final GridCli _cli;

  List<CatalogModel> catalog = const [];
  String? pulling;
  PullProgress? progress;
  String? error;
  bool _disposed = false;
  Process? _process;

  bool get isPulling => pulling != null;

  /// What this machine can run, minus what it already has.
  Future<void> loadCatalog(Set<String> alreadyOnDisk) async {
    final rows = await _cli.runJson<List<dynamic>>(['catalog']);
    catalog = [
      for (final row in rows ?? const [])
        if (row is Map)
          CatalogModel.fromJson(Map<String, dynamic>.from(row)),
    ].where((model) => !alreadyOnDisk.contains(model.file)).toList();
    _notify();
  }

  /// Pull [label], returning true when the file landed.
  ///
  /// The caller re-reads the model list on true rather than being handed one:
  /// what is on disk is a directory listing, and this controller is not the
  /// place that owns it.
  Future<bool> pull(String label) async {
    if (isPulling) return false;
    pulling = label;
    progress = null;
    error = null;
    _notify();
    try {
      _process = await _cli.start(['pull', label]);
    } on GridCliMissing catch (missing) {
      pulling = null;
      error = '$missing';
      _notify();
      return false;
    }
    final process = _process!;
    // The bar is written to stderr with carriage returns, so it never arrives
    // as lines — it is read as raw chunks and the freshest segment wins.
    final bar = process.stderr.transform(utf8.decoder).listen((chunk) {
      for (final segment in chunk.split('\r').reversed) {
        final parsed = PullProgress.parse(segment);
        if (parsed == null) continue;
        progress = parsed;
        _notify();
        break;
      }
    });
    final tail = <String>[];
    final out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(tail.add);
    final exitCode = await process.exitCode;
    await bar.cancel();
    await out.cancel();
    _process = null;
    pulling = null;
    progress = null;
    if (exitCode != 0) {
      error = tail.isEmpty
          ? 'The download did not finish (exit $exitCode).'
          : tail.last;
      _notify();
      return false;
    }
    _notify();
    return true;
  }

  /// Stop a download in progress. The CLI resumes a partial file on the next
  /// attempt, so this loses time and not bytes.
  void cancel() {
    _process?.kill();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _process?.kill();
    super.dispose();
  }
}
