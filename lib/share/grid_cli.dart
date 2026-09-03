import 'dart:convert';
import 'dart:io';

/// Runs the **Grid** CLI, the way [HarnessCliRunner] runs the Harness one.
///
/// Two CLIs, on purpose. `harness` owns this app's machines, agents and
/// terminals; `grid` owns this computer's own inference — the models on its
/// disk, the engine that serves them, and the join that puts it on a grid.
/// Neither can do the other's job, and nothing in `~/.harness` knows how to
/// start a llama.cpp server.
///
/// Every command goes out as `grid --remote …`. The CLI has a *mode* — a
/// machine can be pointed at a grid on its own LAN instead of the cloud — and
/// it is stored in `~/.grid/state.json`, so a build that left it alone would do
/// what the user's last terminal session happened to leave it doing. The grids
/// this app picks from come from the control plane, so remote is the only mode
/// that can serve them, and saying so on every invocation is cheaper than
/// asking the user why their share went to a grid they cannot see.
///
/// Unlike the Harness CLI this app never installs `grid`. It is a tool the user
/// has or has not got, so [locate] returning null is an ordinary state the UI
/// is built to show, not a failure to repair.
class GridCli {
  GridCli({
    Map<String, String>? environment,
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    })?
    runProcess,
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    })?
    startProcess,
  }) : environment = environment ?? Platform.environment,
       _runProcess = runProcess ?? Process.run,
       _startProcess = startProcess ?? Process.start;

  final Map<String, String> environment;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  })
  _runProcess;
  final Future<Process> Function(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  })
  _startProcess;

  /// The mode flag every invocation carries. See the class comment.
  static const String remoteFlag = '--remote';

  String? _resolved;

  /// Where `grid` is, or null when this computer has not got it.
  ///
  /// The installer's own location first, then PATH — the same order and the
  /// same reason as [HarnessCliRunner]: a packaged macOS app inherits Finder's
  /// PATH, which has neither `~/.local/bin` nor Homebrew on it, so a bare
  /// `grid` would be "not installed" on a machine where the terminal finds it
  /// immediately.
  Future<String?> locate() async {
    final cached = _resolved;
    if (cached != null) return cached;
    final home = environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final launcher = File('$home/.local/bin/grid');
      if (await launcher.exists()) return _resolved = launcher.path;
    }
    for (final dir in const ['/opt/homebrew/bin', '/usr/local/bin']) {
      final candidate = File('$dir/grid');
      if (await candidate.exists()) return _resolved = candidate.path;
    }
    final onPath = await _which('grid');
    if (onPath != null) return _resolved = onPath;
    return null;
  }

  Future<String?> _which(String name) async {
    try {
      final result = await _runProcess('/usr/bin/which', [
        name,
      ], environment: commandEnvironment());
      final path = '${result.stdout}'.trim();
      return result.exitCode == 0 && path.isNotEmpty ? path : null;
    } on ProcessException {
      return null;
    }
  }

  /// One command, run to completion.
  ///
  /// A missing binary comes back as [GridCliResult.notInstalled] rather than an
  /// exception: every caller here has something to say about a computer with no
  /// Grid CLI, and none of them has anything to say about a `ProcessException`.
  Future<GridCliResult> run(List<String> arguments) async {
    final executable = await locate();
    if (executable == null) return GridCliResult.notInstalled;
    try {
      final result = await _runProcess(executable, [
        remoteFlag,
        ...arguments,
      ], environment: commandEnvironment());
      return GridCliResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      );
    } on ProcessException catch (error) {
      return GridCliResult(exitCode: -1, stdout: '', stderr: error.message);
    }
  }

  /// [run], with the output parsed as JSON. Null on any failure — a non-zero
  /// exit, an empty body, or output that is not the shape asked for — so a
  /// caller reads "the CLI could not tell me" once instead of three times.
  Future<T?> runJson<T>(List<String> arguments) async {
    final result = await run([...arguments, '--json']);
    if (!result.ok) return null;
    try {
      final decoded = jsonDecode(result.stdout.trim());
      return decoded is T ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// A long-running command whose output the caller wants line by line.
  ///
  /// [secrets] are merged into the child's environment and nowhere else. That
  /// is the whole reason this parameter exists rather than an extra argument:
  /// `ps` is world-readable for the life of a process, so a vendor API key on
  /// the command line is a key every other process on the machine can read.
  Future<Process> start(
    List<String> arguments, {
    Map<String, String> secrets = const {},
  }) async {
    final executable = await locate();
    if (executable == null) {
      throw const GridCliMissing();
    }
    return _startProcess(
      executable,
      [remoteFlag, ...arguments],
      environment: {...commandEnvironment(), ...secrets},
    );
  }

  /// The environment a child gets: this process's, with the CLI's own bin
  /// directory on PATH and a UTF-8 locale forced, so a model name with a
  /// non-ASCII character survives the round trip.
  Map<String, String> commandEnvironment() {
    final home = environment['HOME'];
    final path = environment['PATH'] ?? '';
    final extra = [
      if (home != null && home.isNotEmpty) '$home/.local/bin',
      '/opt/homebrew/bin',
      '/usr/local/bin',
    ].where((dir) => !path.split(':').contains(dir));
    final merged = <String, String>{
      ...environment,
      'PATH': [...extra, if (path.isNotEmpty) path].join(':'),
    };
    final locale = merged['LC_ALL'] ?? merged['LC_CTYPE'] ?? merged['LANG'];
    if ((Platform.isMacOS || Platform.isLinux) &&
        (locale == null ||
            !RegExp(r'utf-?8', caseSensitive: false).hasMatch(locale))) {
      merged['LC_ALL'] = 'C.UTF-8';
    }
    return merged;
  }
}

/// Thrown only by [GridCli.start], which has no result object to put it in.
class GridCliMissing implements Exception {
  const GridCliMissing();

  @override
  String toString() => 'The Grid CLI is not installed on this computer.';
}

/// How one `grid` command ended.
class GridCliResult {
  const GridCliResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.installed = true,
  });

  /// What every call returns on a computer with no `grid` binary.
  static const notInstalled = GridCliResult(
    exitCode: -1,
    stdout: '',
    stderr: 'The Grid CLI is not installed on this computer.',
    installed: false,
  );

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool installed;

  bool get ok => installed && exitCode == 0;

  /// What to show a person. stderr when the CLI wrote one, else stdout — a
  /// couple of its failures explain themselves on the wrong stream.
  String get errorMessage {
    final error = stderr.trim();
    return error.isNotEmpty ? error : stdout.trim();
  }

  /// The command failed because the CLI's own sign-in is gone, which no retry
  /// fixes — the user has to run `grid login` themselves. The CLI has no
  /// structured code for it, so its own sentences are matched, in one place.
  bool get signedOut {
    if (ok || !installed) return false;
    final message = errorMessage.toLowerCase();
    return message.contains('session has expired') ||
        message.contains('session expired or invalid') ||
        message.contains('access token has expired') ||
        message.contains("you're not signed in");
  }
}
