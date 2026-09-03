import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/share/engine_run.dart';
import 'package:harness/share/grid_cli.dart';
import 'package:harness/share/share_controller.dart';
import 'package:harness/share/share_discovery.dart';

const _grid = 'grid-3378218621364f16';

const _capable = ShareCapabilities(
  cliInstalled: true,
  engineInstalled: true,
  models: [],
  backends: [],
  keyProviders: [],
);

/// A `grid` process the test drives: it prints what it was told to and exits
/// with the code it was given.
class _FakeProcess implements Process {
  _FakeProcess({this.exit = 0, this.stdoutLines = const [], this.stderrLines = const []});

  final int exit;
  final List<String> stdoutLines;
  final List<String> stderrLines;
  final _exit = Completer<int>();
  bool killed = false;

  /// Nothing happens until this is called, so a test can inspect the state the
  /// controller is in *while* a join is running.
  void finish() {
    if (!_exit.isCompleted) _exit.complete(exit);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish();
    return true;
  }

  @override
  int get pid => 4242;

  @override
  Stream<List<int>> get stdout => Stream.value(utf8.encode(stdoutLines.join('\n')));

  @override
  Stream<List<int>> get stderr => Stream.value(utf8.encode(stderrLines.join('\n')));

  @override
  IOSink get stdin => throw UnimplementedError();
}

/// A `grid` CLI that records what it was asked to do.
class _FakeCli extends GridCli {
  _FakeCli({this.processes = const [], this.results = const {}})
    : super(environment: const {'HOME': '/tmp/fake-home'});

  /// One per `start`, in order.
  final List<_FakeProcess> processes;

  /// Keyed on the first argument (`leave`, `catalog`).
  final Map<String, GridCliResult> results;

  final List<List<String>> started = [];
  final List<List<String>> ran = [];
  final List<Map<String, String>> secretsSeen = [];
  int _next = 0;

  @override
  Future<String?> locate() async => '/usr/local/bin/grid';

  @override
  Future<GridCliResult> run(List<String> arguments) async {
    ran.add(arguments);
    return results[arguments.first] ??
        const GridCliResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<Process> start(
    List<String> arguments, {
    Map<String, String> secrets = const {},
  }) async {
    started.add(arguments);
    secretsSeen.add(secrets);
    return processes[_next++];
  }
}

ShareController _controller(
  _FakeCli cli, {
  List<EngineRunRecord> Function(String)? runs,
}) => ShareController(
  cli: cli,
  freePort: () async => 51234,
  readRuns: runs ?? (_) => const [],
);

/// A record with no pid, which reads as alive without asking the kernel about a
/// process this test does not have. Liveness by pid is pinned separately, with
/// the check injected, in `share_logic_test.dart`.
EngineRunRecord _record({List<String> models = const ['Qwen3.6']}) =>
    EngineRunRecord.fromJson({
      'engine_id': 'remote',
      'grid_id': _grid,
      'models': models,
    });

void main() {
  test('a started engine is live only once the join command exits', () async {
    final process = _FakeProcess(stdoutLines: ['joining…']);
    final cli = _FakeCli(processes: [process]);
    var runsExist = false;
    final controller = _controller(
      cli,
      runs: (_) => runsExist ? [_record()] : const [],
    )..bindGridForTest(_grid, _capable);

    final started = controller.startLocal(
      modelFile: 'Qwen3.6-UD-IQ3_S.gguf',
      nodeName: 'mac',
      advertiseAs: 'Qwen3.6',
      contextSize: 204800,
    );
    await Future<void>.delayed(Duration.zero);
    // The engine has not joined until `grid join` comes back — saying "live"
    // here would put a green dot over a machine that is not answering.
    expect(controller.status, ShareStatus.starting);

    runsExist = true;
    process.finish();
    await started;

    expect(controller.status, ShareStatus.live);
    expect(controller.liveRun?.models, ['Qwen3.6']);
    expect(cli.started.single, [
      'join', _grid,
      '--serve', 'Qwen3.6-UD-IQ3_S.gguf',
      '--endpoint-port', '51234',
      '--advertise-as', 'Qwen3.6',
      '--ctx-size', '204800',
      '--name', 'mac',
    ]);
    controller.dispose();
  });

  test('a key travels in the environment, never in argv', () async {
    final process = _FakeProcess();
    final cli = _FakeCli(processes: [process]);
    final controller = _controller(cli, runs: (_) => [_record()])
      ..bindGridForTest(_grid, _capable);

    final started = controller.startKey(
      kind: 'openai',
      envVar: 'OPENAI_API_KEY',
      apiKey: 'sk-secret',
      nodeName: 'mac',
      models: const ['openai:gpt-5.5'],
    );
    process.finish();
    await started;

    expect(cli.started.single.join(' '), isNot(contains('sk-secret')));
    expect(cli.secretsSeen.single, {'OPENAI_API_KEY': 'sk-secret'});
    controller.dispose();
  });

  test('an empty key reuses the one the CLI already stored', () async {
    final process = _FakeProcess();
    final cli = _FakeCli(processes: [process]);
    final controller = _controller(cli)..bindGridForTest(_grid, _capable);

    final started = controller.startKey(
      kind: 'openai',
      envVar: 'OPENAI_API_KEY',
      apiKey: '',
      nodeName: 'mac',
    );
    process.finish();
    await started;

    expect(cli.secretsSeen.single, isEmpty);
    controller.dispose();
  });

  test('a lost port race retries on a fresh one instead of failing', () async {
    final failed = _FakeProcess(exit: 1, stderrLines: ['Port 51234 already in use; aborting'])..finish();
    final ok = _FakeProcess()..finish();
    final cli = _FakeCli(processes: [failed, ok]);
    final controller = _controller(cli, runs: (_) => [_record()])
      ..bindGridForTest(_grid, _capable);

    await controller.startLocal(modelFile: 'm.gguf', nodeName: 'mac');

    expect(cli.started, hasLength(2));
    expect(controller.status, ShareStatus.live);
    controller.dispose();
  });

  test('a leftover engine is dropped, then the join is tried once more', () async {
    final blocked = _FakeProcess(exit: 1, stderrLines: ['engine "mac" has already joined'])..finish();
    final ok = _FakeProcess()..finish();
    final cli = _FakeCli(processes: [blocked, ok]);
    final controller = _controller(cli, runs: (_) => [_record()])
      ..bindGridForTest(_grid, _capable);

    await controller.startLocal(modelFile: 'm.gguf', nodeName: 'mac');

    expect(cli.ran.single, ['leave', _grid]);
    expect(cli.started, hasLength(2));
    expect(controller.status, ShareStatus.live);
    controller.dispose();
  });

  test('it retries once, not forever', () async {
    final first = _FakeProcess(exit: 1, stderrLines: ['already in use'])..finish();
    final second = _FakeProcess(exit: 1, stderrLines: ['already in use'])..finish();
    final cli = _FakeCli(processes: [first, second]);
    final controller = _controller(cli)..bindGridForTest(_grid, _capable);

    await controller.startLocal(modelFile: 'm.gguf', nodeName: 'mac');

    expect(cli.started, hasLength(2));
    expect(controller.status, ShareStatus.failed);
    expect(controller.error, contains('already in use'));
    controller.dispose();
  });

  test('a failed leave is not reported as stopped', () async {
    final cli = _FakeCli(
      results: {
        'leave': const GridCliResult(
          exitCode: 1,
          stdout: '',
          stderr: 'the relay did not answer',
        ),
      },
    );
    final controller = _controller(cli, runs: (_) => [_record()])
      ..bindGridForTest(_grid, _capable);
    expect(controller.status, ShareStatus.live);

    await controller.stop();

    // Saying "stopped" here would leave a machine on the grid that this page
    // claims is off it.
    expect(controller.status, ShareStatus.failed);
    expect(controller.error, contains('did not answer'));
    controller.dispose();
  });

  test('an engine from a previous session is adopted, not ignored', () {
    final controller = _controller(_FakeCli(), runs: (_) => [_record()])
      ..bindGridForTest(_grid, _capable);
    expect(controller.status, ShareStatus.live);
    expect(controller.liveRun?.engineId, 'remote');
    controller.dispose();
  });

  test('refuses to start at all without the Grid CLI', () async {
    final cli = _FakeCli();
    final controller = _controller(cli)
      ..bindGridForTest(_grid, ShareCapabilities.empty);

    await controller.startLocal(modelFile: 'm.gguf', nodeName: 'mac');

    expect(cli.started, isEmpty);
    expect(controller.status, ShareStatus.failed);
    expect(controller.error, contains('not installed'));
    controller.dispose();
  });

  test('closing the page stops the join, never the engine', () async {
    final process = _FakeProcess();
    final cli = _FakeCli(processes: [process]);
    final controller = _controller(cli, runs: (_) => [_record()])
      ..bindGridForTest(_grid, _capable);

    unawaited(controller.startLocal(modelFile: 'm.gguf', nodeName: 'mac'));
    await Future<void>.delayed(Duration.zero);
    controller.dispose();

    // The join process — the one still printing at us — is killed. `grid leave`
    // is NOT run: closing a window is not a request to stop sharing.
    expect(process.killed, isTrue);
    expect(cli.ran, isEmpty);
  });
}
