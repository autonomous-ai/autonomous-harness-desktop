import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'grid_cli.dart';

/// How far a download has got.
class PullProgress {
  const PullProgress({
    required this.doneMb,
    this.totalMb,
    this.percent,
    this.fileIndex = 0,
    this.fileCount = 1,
  });

  final double doneMb;
  final double? totalMb;
  final double? percent;

  /// Which file of a split set this is, and how many there are. A five-shard
  /// model reaching 100% four times over is not a bar anybody can read.
  final int fileIndex;
  final int fileCount;

  /// A download whose total the server never declared. Real, and common enough
  /// that it needs a shape rather than a zero — the bar goes indeterminate
  /// instead of sitting at 0% while megabytes land.
  bool get isIndeterminate => percent == null;

  /// Progress across the whole set, not just the file in flight.
  double? get overall => percent == null
      ? null
      : (fileIndex + percent! / 100) / fileCount;

  /// `1.2 GB of 15.0 GB`, with `· part 2 of 5` when there is more than one.
  String get label {
    String size(double mb) =>
        mb >= 1000 ? '${(mb / 1000).toStringAsFixed(1)} GB' : '${mb.round()} MB';
    final total = totalMb;
    final head = total == null ? size(doneMb) : '${size(doneMb)} of ${size(total)}';
    return fileCount > 1 ? '$head · part ${fileIndex + 1} of $fileCount' : head;
  }

  PullProgress inFile(int index, int count) => PullProgress(
    doneMb: doneMb,
    totalMb: totalMb,
    percent: percent,
    fileIndex: index,
    fileCount: count,
  );

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

/// Downloads a model, and says how it is going.
///
/// One model can be several files — a split GGUF is downloaded shard by shard —
/// so a pull is a *queue*, and it stops at the first failure. Half a split set
/// is not a partial success: it is a model that will not load, and carrying on
/// would spend another ten gigabytes proving it.
class ModelPullController extends ChangeNotifier {
  ModelPullController({GridCli? cli}) : _cli = cli ?? GridCli();

  final GridCli _cli;

  /// What is being downloaded, as the user would name it. Null when nothing is.
  String? pulling;
  PullProgress? progress;
  String? error;
  bool _cancelled = false;
  bool _disposed = false;
  Process? _process;

  bool get isPulling => pulling != null;

  /// Download every file of [specs] in order, under the display name [label].
  ///
  /// Returns true only when all of them landed. The caller re-reads the disk on
  /// true rather than being handed a list: what is downloaded is a directory
  /// listing, and this controller is not the place that owns it.
  Future<bool> pull(List<String> specs, {required String label}) async {
    if (isPulling || specs.isEmpty) return false;
    pulling = label;
    progress = null;
    error = null;
    _cancelled = false;
    _notify();
    for (final (index, spec) in specs.indexed) {
      final ok = await _pullOne(spec, index, specs.length);
      if (!ok) {
        pulling = null;
        progress = null;
        _notify();
        return false;
      }
    }
    pulling = null;
    progress = null;
    _notify();
    return true;
  }

  Future<bool> _pullOne(String spec, int index, int count) async {
    try {
      _process = await _cli.start(['pull', spec]);
    } on GridCliMissing catch (missing) {
      error = '$missing';
      return false;
    }
    final process = _process!;
    // The bar is written to stderr with carriage returns, so it never arrives
    // as lines — it is read as raw chunks and the freshest segment wins.
    final bar = process.stderr.transform(utf8.decoder).listen((chunk) {
      for (final segment in chunk.split('\r').reversed) {
        final parsed = PullProgress.parse(segment);
        if (parsed == null) continue;
        progress = parsed.inFile(index, count);
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
    if (exitCode == 0) return true;
    // A cancel is the user's decision, not a failure to report back at them.
    error = _cancelled
        ? null
        : (tail.isEmpty
              ? 'The download did not finish (exit $exitCode).'
              : tail.last);
    return false;
  }

  /// Stop a download in progress.
  ///
  /// This loses time, not bytes: the CLI keeps a `.part` file and asks for the
  /// rest with a Range header next time (`shared/models/download.py`).
  void cancel() {
    _cancelled = true;
    _process?.kill();
  }

  void clearError() {
    if (error == null) return;
    error = null;
    _notify();
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
