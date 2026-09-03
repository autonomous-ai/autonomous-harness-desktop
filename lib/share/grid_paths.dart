import 'dart:io';

/// Locations under `~/.grid`, mirroring the Grid CLI's own `paths.py`.
///
/// This app owns `~/.harness` and nothing else; `~/.grid` belongs to the `grid`
/// CLI, and everything here is **read**. The one thing written under it is
/// written by the CLI on our behalf — a run record for an engine `grid join`
/// launched — which is exactly why those paths are known here: an engine that
/// outlives the app has to be findable again on the next launch.
///
/// `GRID_HOME` is honoured because the CLI honours it. A developer who moves
/// their grid home and finds this app still reading `~/.grid` would be looking
/// at a different machine's models and a run record that was never written.
abstract final class GridPaths {
  static String get _userHome =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;

  static Directory get home {
    final override = Platform.environment['GRID_HOME'];
    return Directory(
      override != null && override.isNotEmpty ? override : '$_userHome/.grid',
    );
  }

  /// Where `grid pull` puts GGUF weights — the models the local route offers.
  static Directory get modelsDir => Directory('${home.path}/models');

  /// The CLI's private binaries. Its presence is how "can this computer run a
  /// model at all" is answered without asking the CLI.
  static File get llamaServerBin => File('${home.path}/bin/llama-server');

  /// One `<engine_id>.json` per detached engine, per grid.
  static Directory engineRunDir(String gridId) =>
      Directory('${home.path}/run/engines/$gridId');
}
