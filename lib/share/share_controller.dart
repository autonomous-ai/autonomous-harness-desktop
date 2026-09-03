import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'engine_run.dart';
import 'grid_cli.dart';
import 'join_args.dart';
import 'node_identity.dart';
import 'share_discovery.dart';
import 'share_route.dart';

/// Where a share is in its life.
enum ShareStatus {
  /// Nothing of ours is serving this grid.
  idle,

  /// A `grid join` is running. It has not joined until that command exits.
  starting,

  /// An engine is serving, detached, and outlives this window.
  live,

  /// Stopping, which is a `grid leave` round trip and takes seconds.
  stopping,

  /// The last attempt failed and [ShareController.error] says how.
  failed,
}

/// The state of "is this computer sharing", and the two commands that change it.
///
/// A [ChangeNotifier] because that is how this app carries state (see
/// `state/app_state.dart`); the Grid app's own version of this screen is a
/// stack of Riverpod providers, and porting those wholesale would have put a
/// second state idiom in an app that deliberately has one.
///
/// The engine it starts is **detached**. `grid join` hands the machine to the
/// CLI and exits; what serves afterwards is the CLI's own process, and it keeps
/// serving when this window closes. That is the point of it, and it is why
/// [reconcile] exists: after a restart the only truthful answer to "am I
/// sharing?" is the run record on disk.
class ShareController extends ChangeNotifier {
  ShareController({
    GridCli? cli,
    FreePortFinder? freePort,
    List<EngineRunRecord> Function(String gridId)? readRuns,
  }) : _cli = cli ?? GridCli(),
       _freePort = freePort ?? findFreePort,
       _readRuns = readRuns ?? readEngineRuns;

  final GridCli _cli;
  final FreePortFinder _freePort;

  /// How "is something already serving this grid" is answered. Injected so a
  /// test can drive the state machine without a `~/.grid` on the machine
  /// running it.
  final List<EngineRunRecord> Function(String gridId) _readRuns;

  /// The most a log is allowed to grow to. A join prints its progress and then
  /// stops; anything past this is a run that is failing loudly, and the tail is
  /// the part worth keeping.
  static const int _maxLogLines = 200;

  ShareCapabilities capabilities = ShareCapabilities.empty;
  bool loading = true;
  ShareStatus status = ShareStatus.idle;
  String? error;
  List<String> log = const [];

  /// What is serving, when something is. Read from the CLI's run record, so it
  /// is equally right about an engine this session started and one it adopted.
  EngineRunRecord? liveRun;

  /// The route the reader picked, or null while the page follows the default.
  /// Null rather than a seeded value: discovery lands a frame or two after the
  /// page opens, and a controller that had to be *told* the default would need
  /// a side effect in `build`.
  ShareRoute? _pickedRoute;

  String? _gridId;

  /// The grid every command here is about. Null until [refresh] names one.
  String? get gridId => _gridId;
  Process? _process;
  bool _stopping = false;
  bool _disposed = false;

  ShareRoute get route => _pickedRoute ?? capabilities.defaultRoute;

  void pickRoute(ShareRoute value) {
    if (_pickedRoute == value) return;
    _pickedRoute = value;
    _notify();
  }

  /// Probe the machine and adopt anything already serving [gridId].
  Future<void> refresh(String gridId) async {
    _gridId = gridId;
    loading = true;
    _notify();
    capabilities = await discoverShareCapabilities(_cli);
    loading = false;
    reconcile(gridId);
    _notify();
  }

  /// Adopt an engine that is already serving this grid — one this window
  /// started before it was closed, or one started from a terminal.
  ///
  /// Reading rather than remembering. The record is the CLI's, written at join
  /// and removed at leave, so it is right across restarts of this app in a way
  /// that no note we kept could be.
  void reconcile(String gridId) {
    final record = firstLiveRun(_readRuns(gridId));
    liveRun = record;
    if (record != null) {
      status = ShareStatus.live;
      error = null;
      return;
    }
    // Never downgrade a run this session is in the middle of: the record does
    // not exist until `join` writes it, and a reconcile mid-start would read
    // that gap as "not sharing".
    if (status == ShareStatus.live) status = ShareStatus.idle;
  }

  /// Bind a grid and a set of capabilities without probing this machine.
  ///
  /// [refresh] is the production path and it asks the machine three HTTP
  /// questions and spawns the CLI twice; a test of the start/stop state machine
  /// has nothing to say about any of that, and would answer them differently on
  /// every developer's laptop.
  @visibleForTesting
  void bindGridForTest(String gridId, ShareCapabilities capabilities) {
    _gridId = gridId;
    this.capabilities = capabilities;
    loading = false;
    reconcile(gridId);
    _notify();
  }

  /// Serve a local GGUF through the CLI's built-in engine.
  Future<void> startLocal({
    required String modelFile,
    required String nodeName,
    String? advertiseAs,
    int? contextSize,
  }) async {
    final gridId = _gridId;
    if (gridId == null) return;
    Future<List<String>> build() async => localJoinArgs(
      gridId: gridId,
      modelFile: modelFile,
      endpointPort: await _freePort(),
      nodeName: _nameOr(nodeName),
      advertiseAs: advertiseAs,
      contextSize: contextSize,
    );
    await _join(await build(), gridId: gridId, rebuild: build);
  }

  /// Serve an OpenAI-compatible server already running on this computer.
  Future<void> startExternal({
    required String endpoint,
    required String model,
    required String nodeName,
    String? advertiseAs,
    int? contextLength,
  }) async {
    final gridId = _gridId;
    if (gridId == null) return;
    await _join(
      externalJoinArgs(
        gridId: gridId,
        endpoint: endpoint,
        model: model,
        nodeName: _nameOr(nodeName),
        advertiseAs: advertiseAs,
        contextLength: contextLength,
      ),
      gridId: gridId,
    );
  }

  /// Serve a hosted provider on the user's own key.
  ///
  /// [apiKey] travels in [secrets] and nowhere else — see [apiJoinArgs]. Empty
  /// falls back to the key the CLI already stored for this kind, which is how a
  /// second share avoids asking for it again.
  Future<void> startKey({
    required String kind,
    required String envVar,
    required String apiKey,
    required String nodeName,
    List<String> models = const [],
  }) async {
    final gridId = _gridId;
    if (gridId == null) return;
    await _join(
      apiJoinArgs(
        gridId: gridId,
        kind: kind,
        nodeName: _nameOr(nodeName),
        models: models,
      ),
      gridId: gridId,
      secrets: apiKey.isEmpty ? const {} : {envVar: apiKey},
    );
  }

  /// Stop sharing. Leaves every engine this machine has on the grid.
  Future<void> stop() async {
    final gridId = _gridId;
    if (gridId == null) return;
    _stopping = true;
    status = ShareStatus.stopping;
    error = null;
    _notify();
    _process?.kill();
    final result = await _cli.run(leaveArgs(gridId: gridId));
    _stopping = false;
    liveRun = null;
    if (!result.ok) {
      // The engine may well be gone anyway — but saying "stopped" when the
      // leave failed would leave a machine on the grid that the page says is
      // off it, which is the one wrong answer worth avoiding here.
      status = ShareStatus.failed;
      error = result.errorMessage;
      _notify();
      return;
    }
    status = ShareStatus.idle;
    log = const [];
    _notify();
  }

  /// Dismiss a failure so the form comes back.
  void clearError() {
    if (status != ShareStatus.failed) return;
    status = ShareStatus.idle;
    error = null;
    _notify();
  }

  String _nameOr(String? typed) {
    final name = typed?.trim() ?? '';
    return name.isEmpty ? thisComputerName : name;
  }

  /// Run one `grid join` and settle the state on how it ended.
  ///
  /// [rebuild] regenerates the arguments with a freshly picked port, so a race
  /// lost for a port self-heals on a second one instead of failing at the user.
  Future<void> _join(
    List<String> args, {
    required String gridId,
    Map<String, String> secrets = const {},
    Future<List<String>> Function()? rebuild,
    bool retried = false,
  }) async {
    if (!capabilities.cliInstalled) {
      status = ShareStatus.failed;
      error = 'The Grid CLI is not installed on this computer.';
      _notify();
      return;
    }
    _stopping = false;
    status = ShareStatus.starting;
    error = null;
    log = const [];
    _notify();

    final lines = <String>[];
    try {
      _process = await _cli.start(args, secrets: secrets);
    } on GridCliMissing catch (missing) {
      status = ShareStatus.failed;
      error = '$missing';
      _notify();
      return;
    }
    final process = _process!;
    final drained = Future.wait([
      _drain(process.stdout, lines),
      _drain(process.stderr, lines),
    ]);
    final exitCode = await process.exitCode;
    await drained;
    _process = null;

    // A stop that arrived mid-start owns the ending: settling here would drop
    // the page out of "Stopping…" while `grid leave` was still running.
    if (_stopping) return;

    if (exitCode == 0) {
      // The engine is detached and serving now, and has written its record.
      reconcile(gridId);
      status = ShareStatus.live;
      _notify();
      return;
    }

    final failure = lines.isEmpty
        ? 'The engine failed to start (exit $exitCode).'
        : lines.last;
    final lower = failure.toLowerCase();
    // A leftover engine from a previous session blocks a join under the same
    // name. Drop it and try once more, so the user is not stuck unable to start
    // and unable to stop a run this app never tracked.
    if (!retried && lower.contains('already joined')) {
      await _cli.run(leaveArgs(gridId: gridId));
      return _join(args, gridId: gridId, secrets: secrets, retried: true);
    }
    // Something took the port between our picking it and the engine binding it.
    if (!retried && rebuild != null && lower.contains('already in use')) {
      return _join(
        await rebuild(),
        gridId: gridId,
        secrets: secrets,
        rebuild: rebuild,
        retried: true,
      );
    }
    status = ShareStatus.failed;
    error = failure;
    _notify();
  }

  Future<void> _drain(Stream<List<int>> stream, List<String> sink) {
    return stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          // Nothing a cancelled run says can change what was already decided.
          if (_stopping) return;
          sink.add(line);
          if (sink.length > _maxLogLines) {
            sink.removeRange(0, sink.length - _maxLogLines);
          }
          log = List.unmodifiable(sink);
          _notify();
        });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Deliberately NOT killing the engine: it is detached and serving, and
    // closing a window is not a request to stop sharing. Only the join process
    // — the one still printing at us — goes.
    _process?.kill();
    super.dispose();
  }
}
