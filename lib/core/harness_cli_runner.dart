import 'dart:io';

/// Runs the Harness CLI owned by this desktop app without depending on a
/// terminal shell, its rc files, or Finder's inherited PATH.
///
/// The setup flow installs both of these private, versioned files:
///
/// - `~/.harness/runtime/current-node` -> the managed Node binary
/// - `~/.harness/cli/cli.js` -> the installed Harness CLI bundle
///
/// Prefer that exact pair. Older installations can still use the installed
/// `~/.local/bin/harness` launcher, and only then fall back to PATH for a
/// developer-managed installation. None of those paths require zsh.
class HarnessCliRunner {
  final Directory harnessHome;
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

  HarnessCliRunner({
    Directory? harnessHome,
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
       harnessHome = harnessHome ?? Directory(_defaultHarnessHome()),
       _runProcess = runProcess ?? Process.run,
       _startProcess = startProcess ?? Process.start;

  static String _defaultHarnessHome() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Could not resolve the current user home directory');
    }
    return '$home${Platform.pathSeparator}.harness';
  }

  Directory get _runtimeDirectory =>
      Directory('${harnessHome.path}${Platform.pathSeparator}runtime');

  File get _currentNodeFile =>
      File('${_runtimeDirectory.path}${Platform.pathSeparator}current-node');

  File get _cliFile => File(
    '${harnessHome.path}${Platform.pathSeparator}cli${Platform.pathSeparator}cli.js',
  );

  /// Builds the direct invocation used by [run] and [start]. Public for
  /// focused tests and diagnostics; callers should generally call [run].
  Future<HarnessCliInvocation> resolve(List<String> arguments) async {
    final node = await _managedNode();
    if (node != null && await _cliFile.exists()) {
      return HarnessCliInvocation(
        executable: node.path,
        arguments: [_cliFile.path, ...arguments],
        environment: _commandEnvironment(),
        source: HarnessCliSource.managed,
      );
    }

    final home = environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final launcher = File(
        '$home${Platform.pathSeparator}.local${Platform.pathSeparator}bin${Platform.pathSeparator}harness',
      );
      if (await launcher.exists()) {
        return HarnessCliInvocation(
          executable: launcher.path,
          arguments: arguments,
          environment: _commandEnvironment(),
          source: HarnessCliSource.launcher,
        );
      }
    }

    return HarnessCliInvocation(
      executable: 'harness',
      arguments: arguments,
      environment: _commandEnvironment(),
      source: HarnessCliSource.path,
    );
  }

  Future<ProcessResult> run(List<String> arguments) async {
    final invocation = await resolve(arguments);
    return _runProcess(
      invocation.executable,
      invocation.arguments,
      environment: invocation.environment,
    );
  }

  Future<Process> start(List<String> arguments) async {
    final invocation = await resolve(arguments);
    return _startProcess(
      invocation.executable,
      invocation.arguments,
      environment: invocation.environment,
    );
  }

  Future<File?> _managedNode() async {
    try {
      final raw = (await _currentNodeFile.readAsString()).trim();
      if (raw.isEmpty) return null;
      final runtimeRoot =
          '${_runtimeDirectory.absolute.path}${Platform.pathSeparator}';
      if (!raw.startsWith(runtimeRoot)) return null;
      final node = File(raw);
      return await node.exists() ? node : null;
    } on FileSystemException {
      return null;
    }
  }

  Map<String, String> _commandEnvironment() {
    final home = environment['HOME'];
    final launcherDirectory = home == null || home.isEmpty
        ? null
        : '$home${Platform.pathSeparator}.local${Platform.pathSeparator}bin';
    final path = environment['PATH'] ?? '';
    final commandEnvironment = <String, String>{
      ...environment,
      if (launcherDirectory != null)
        'PATH': path.isEmpty ? launcherDirectory : '$launcherDirectory:$path',
    };
    final configuredLocale =
        commandEnvironment['LC_ALL'] ??
        commandEnvironment['LC_CTYPE'] ??
        commandEnvironment['LANG'];
    if ((Platform.isMacOS || Platform.isLinux) &&
        (configuredLocale == null ||
            !RegExp(
              r'utf-?8',
              caseSensitive: false,
            ).hasMatch(configuredLocale))) {
      commandEnvironment['LC_ALL'] = 'C.UTF-8';
    }
    return commandEnvironment;
  }
}

enum HarnessCliSource { managed, launcher, path }

class HarnessCliInvocation {
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final HarnessCliSource source;

  const HarnessCliInvocation({
    required this.executable,
    required this.arguments,
    required this.environment,
    required this.source,
  });
}
