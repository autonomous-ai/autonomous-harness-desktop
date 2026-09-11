import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/harness_cli_runner.dart';

/// The CLI-only installer contract for callers that already own host setup.
/// Desktop verifies system tools and tmux before reaching this command, then
/// performs its own complete verification again after Harness and Grid land.
const String kHarnessDesktopInstallCommand =
    'curl -fsSL https://cdn.autonomous.ai/harness/cli/install.sh | '
    '/bin/sh -s -- --desktop';

enum EnvironmentStep {
  harness,
  tmux,
  grid;

  /// Harness Desktop is only ready when every command in this list works.
  bool get isRequired => true;
}

enum EnvironmentSetupPhase {
  preflight,
  review,
  chooseMethod,
  installing,
  waitingForTerminal,
  verifying,
  ready,
  failed,
}

enum EnvironmentSetupMode { automatic, manual }

class EnvironmentFailure {
  final EnvironmentStep? step;
  final String title;
  final String detail;
  final String? command;
  final int? exitCode;

  const EnvironmentFailure({
    this.step,
    required this.title,
    required this.detail,
    this.command,
    this.exitCode,
  });
}

enum EnvironmentStepStatus {
  pending,
  running,
  ready,
  needsTerminal,
  failed,

  /// The host does not support this dependency. All current steps are required,
  /// so this status remains blocking.
  unavailable,
}

class EnvironmentReadiness {
  final Map<EnvironmentStep, EnvironmentStepStatus> steps;
  final String? message;
  final List<String> output;
  final EnvironmentSetupPhase phase;
  final EnvironmentSetupMode? mode;
  final EnvironmentFailure? failure;
  final String? terminalLogPath;
  final String? terminalResultPath;
  final bool systemReady;

  const EnvironmentReadiness({
    required this.steps,
    this.message,
    this.output = const [],
    this.phase = EnvironmentSetupPhase.preflight,
    this.mode,
    this.failure,
    this.terminalLogPath,
    this.terminalResultPath,
    this.systemReady = false,
  });

  factory EnvironmentReadiness.initial() => EnvironmentReadiness(
    steps: {
      for (final step in EnvironmentStep.values)
        step: EnvironmentStepStatus.pending,
    },
  );

  bool get isReady =>
      systemReady &&
      steps.values.every((status) => status == EnvironmentStepStatus.ready);

  bool get needsTerminal => steps.values.any(
    (status) => status == EnvironmentStepStatus.needsTerminal,
  );

  EnvironmentReadiness copyWith({
    Map<EnvironmentStep, EnvironmentStepStatus>? steps,
    String? message,
    List<String>? output,
    EnvironmentSetupPhase? phase,
    EnvironmentSetupMode? mode,
    EnvironmentFailure? failure,
    String? terminalLogPath,
    String? terminalResultPath,
    bool? systemReady,
    bool clearFailure = false,
  }) => EnvironmentReadiness(
    steps: steps ?? this.steps,
    message: message ?? this.message,
    output: output ?? this.output,
    phase: phase ?? this.phase,
    mode: mode ?? this.mode,
    failure: clearFailure ? null : failure ?? this.failure,
    terminalLogPath: terminalLogPath ?? this.terminalLogPath,
    terminalResultPath: terminalResultPath ?? this.terminalResultPath,
    systemReady: systemReady ?? this.systemReady,
  );
}

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

typedef TerminalLauncher = Future<void> Function(String scriptPath);

typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

/// The progress callback `ensureReady` builds for itself, named so the per-host paths below can be
/// separate methods rather than one very long function.
typedef EmitStep = void Function({
  EnvironmentStep? step,
  EnvironmentStepStatus? status,
  String? message,
  String? output,
});

Future<ProcessResult> _defaultRun(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(executable, arguments, environment: environment);

Future<Process> _defaultStart(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.start(executable, arguments, environment: environment);

/// macOS opens a real Terminal.app window. Linux has no single canonical
/// terminal, so this tries the Debian/Ubuntu `update-alternatives` target
/// first, then the two most common emulators, and gives up only if none of
/// them exist on the box.
Future<void> _defaultOpenTerminal(String scriptPath) async {
  if (Platform.isMacOS) {
    await Process.start('/usr/bin/open', ['-a', 'Terminal', scriptPath]);
    return;
  }
  final candidates = <List<String>>[
    ['x-terminal-emulator', '-e', scriptPath],
    ['gnome-terminal', '--', scriptPath],
    ['xterm', '-e', scriptPath],
  ];
  for (final candidate in candidates) {
    try {
      await Process.start(candidate.first, candidate.skip(1).toList());
      return;
    } on ProcessException {
      continue;
    }
  }
  throw StateError(
    'Could not find a terminal emulator to launch (tried x-terminal-emulator, '
    'gnome-terminal, xterm)',
  );
}

/// Prepares the only system dependencies required by the desktop transport.
///
/// Node lives beneath [harnessHome] rather than in Homebrew/nvm/PATH. The
/// CLI launcher is written against that exact binary, so launching Harness
/// from Finder and from Terminal has identical runtime behavior.
class EnvironmentProvisioner {
  final Directory harnessHome;
  final ProcessRunner _run;
  final ProcessStarter? _start;
  final TerminalLauncher _openTerminal;
  final bool _isMacOS;
  final bool _isLinux;
  final bool _isWindows;
  final bool _forceMissingAppleDeveloperTools;

  EnvironmentProvisioner({
    Directory? harnessHome,
    ProcessRunner? run,
    ProcessStarter? start,
    TerminalLauncher? openTerminal,
    bool? isMacOS,
    bool? isLinux,
    bool? isWindows,
    bool? forceMissingAppleDeveloperTools,
  }) : harnessHome = harnessHome ?? Directory(_defaultHarnessHome()),
       _run = run ?? _defaultRun,
       _start = start ?? (run == null ? _defaultStart : null),
       _openTerminal = openTerminal ?? _defaultOpenTerminal,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isLinux = isLinux ?? Platform.isLinux,
       _isWindows = isWindows ?? Platform.isWindows,
       _forceMissingAppleDeveloperTools =
           forceMissingAppleDeveloperTools ??
           const bool.fromEnvironment(
             'HARNESS_DESKTOP_FORCE_MISSING_APPLE_DEVELOPER_TOOLS',
           );

  /// HOME, then USERPROFILE. Windows sets only the latter, so a launch from Explorer used to throw
  /// out of this constructor before a single frame could render.
  static String? userHome() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return home;
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) return profile;
    return null;
  }

  static String _defaultHarnessHome() {
    final home = userHome();
    if (home == null) {
      throw StateError('Could not resolve the current user home directory');
    }
    return '$home${Platform.pathSeparator}.harness';
  }

  /// Checks the complete environment, and mutates it only when [install] is explicitly true.
  Future<EnvironmentReadiness> ensureReady({
    required void Function(EnvironmentReadiness value) onProgress,
    EnvironmentReadiness? resumeFrom,
    bool install = true,
    EnvironmentSetupMode? mode,
  }) async {
    var state = (resumeFrom ?? EnvironmentReadiness.initial()).copyWith(
      phase: install
          ? EnvironmentSetupPhase.installing
          : EnvironmentSetupPhase.preflight,
      mode: mode,
      clearFailure: true,
    );
    void emit({
      EnvironmentStep? step,
      EnvironmentStepStatus? status,
      String? message,
      String? output,
      EnvironmentSetupPhase? phase,
      EnvironmentFailure? failure,
      String? terminalLogPath,
      String? terminalResultPath,
      bool? systemReady,
    }) {
      final next = Map<EnvironmentStep, EnvironmentStepStatus>.from(
        state.steps,
      );
      if (step != null && status != null) next[step] = status;
      final lines = [...state.output];
      if (output != null && output.trim().isNotEmpty) {
        if (output.startsWith('Terminal log:\n')) {
          lines.removeWhere((line) => line.startsWith('Terminal log:\n'));
        }
        lines.add(output.trim());
        if (lines.length > 200) lines.removeRange(0, lines.length - 200);
      }
      state = EnvironmentReadiness(
        steps: next,
        message: message ?? state.message,
        output: lines,
        phase: phase ?? state.phase,
        mode: mode ?? state.mode,
        failure: failure ?? state.failure,
        terminalLogPath: terminalLogPath ?? state.terminalLogPath,
        terminalResultPath: terminalResultPath ?? state.terminalResultPath,
        systemReady: systemReady ?? state.systemReady,
      );
      onProgress(state);
    }

    final previousTerminalLog = state.terminalLogPath;
    if (previousTerminalLog != null) {
      try {
        final text = await File(previousTerminalLog).readAsString();
        final snapshot = 'Terminal log:\n${text.trim()}';
        if (text.trim().isNotEmpty && !state.output.contains(snapshot)) {
          emit(output: snapshot);
        }
      } on FileSystemException {
        // The terminal may not have created its log yet.
      }
    }
    final previousTerminalResult = state.terminalResultPath;
    if (previousTerminalResult != null) {
      try {
        final exitCode = int.tryParse(
          (await File(previousTerminalResult).readAsString()).trim(),
        );
        if (exitCode != null && exitCode != 0) {
          emit(
            step: EnvironmentStep.tmux,
            status: EnvironmentStepStatus.failed,
            message: 'The Terminal setup exited with code $exitCode.',
            phase: EnvironmentSetupPhase.failed,
            failure: EnvironmentFailure(
              step: EnvironmentStep.tmux,
              title: 'System package installation failed',
              detail:
                  'Terminal exited with code $exitCode. Review the complete log below.',
              command: _manualCommandFor(EnvironmentStep.tmux),
              exitCode: exitCode,
            ),
          );
          return state;
        }
      } on FileSystemException {
        // Still running: the result file is written by the terminal script's EXIT trap.
      }
    }
    onProgress(state);

    if (!_isMacOS && !_isLinux) {
      if (_isWindows) {
        await _verifyWindows(emit);
        return state;
      }
      emit(
        step: EnvironmentStep.harness,
        status: EnvironmentStepStatus.failed,
        message: 'Automatic environment setup is currently available on macOS and Linux only.',
        phase: EnvironmentSetupPhase.failed,
      );
      return state;
    }

    try {
      final systemFailure = await _systemPreflightFailure();
      if (systemFailure != null) {
        emit(
          message: systemFailure.detail,
          phase: EnvironmentSetupPhase.failed,
          failure: systemFailure,
        );
        return state;
      }
      final systemReady = !_isMacOS || await _hasAppleDeveloperTools();
      emit(
        systemReady: systemReady,
        output: systemReady
            ? '✓ required system tools · writable home'
            : '✗ Apple developer tools · xcrun --find clang',
      );

      final homebrewReady = !_isMacOS || await _hasHomebrew();
      final tmuxBinaryReady = await _hasTmux();
      var tmuxReady =
          (!_isMacOS || homebrewReady) && systemReady && tmuxBinaryReady;
      emit(
        step: EnvironmentStep.tmux,
        status: tmuxReady
            ? EnvironmentStepStatus.ready
            : EnvironmentStepStatus.failed,
        message: tmuxReady
            ? (_isMacOS ? 'Homebrew and tmux are ready.' : 'tmux is ready.')
            : !systemReady
            ? 'Apple developer tools are required.'
            : _isMacOS && !homebrewReady
            ? 'Homebrew is required.'
            : 'tmux is required.',
        output: tmuxReady
            ? (_isMacOS ? '✓ Homebrew · tmux --version' : '✓ tmux --version')
            : !systemReady
            ? '✗ Apple developer tools · xcrun --find clang'
            : _isMacOS && !homebrewReady
            ? '✗ Homebrew · brew --version'
            : '✗ tmux --version',
      );

      final harnessReady = await _hasHarness();
      emit(
        step: EnvironmentStep.harness,
        status: harnessReady
            ? EnvironmentStepStatus.ready
            : EnvironmentStepStatus.failed,
        message: harnessReady
            ? 'Harness CLI and managed Node are ready.'
            : 'Harness CLI or its managed Node runtime is missing.',
        output: harnessReady
            ? '✓ managed Node >= 20 · harness version'
            : '✗ managed Node >= 20 · harness version',
      );

      final gridReady = await _hasGrid();
      emit(
        step: EnvironmentStep.grid,
        status: gridReady
            ? EnvironmentStepStatus.ready
            : EnvironmentStepStatus.failed,
        message: gridReady ? 'Grid CLI is ready.' : 'Grid CLI is required.',
        output: gridReady ? '✓ grid --version' : '✗ grid --version',
      );

      if (state.isReady) {
        emit(
          message: 'All required tools passed verification.',
          phase: EnvironmentSetupPhase.ready,
        );
        return state;
      }

      if (!install) {
        emit(
          message: 'Review what Harness will install before continuing.',
          phase: EnvironmentSetupPhase.review,
        );
        return state;
      }

      // Strict dependency order: system tools -> tmux -> managed Node/Harness -> Grid.
      if (_isMacOS && systemReady && homebrewReady && !tmuxBinaryReady) {
        emit(
          step: EnvironmentStep.tmux,
          status: EnvironmentStepStatus.running,
          message: 'Installing tmux via Homebrew…',
        );
        ProcessResult? installResult;
        try {
          installResult = await _shellStreaming(
            'brew install tmux',
            onOutput: (line) => emit(output: line),
          );
        } catch (error) {
          emit(output: 'Background tmux install failed: $error');
        }
        tmuxReady = installResult?.exitCode == 0 && await _hasTmux();
        if (tmuxReady) {
          emit(
            step: EnvironmentStep.tmux,
            status: EnvironmentStepStatus.ready,
            message: 'Homebrew and tmux are ready.',
            output: '✓ tmux installed via Homebrew',
          );
        } else {
          if (installResult != null) {
            emit(
              output: installResult.exitCode == 0
                  ? 'Homebrew finished, but tmux did not pass verification.'
                  : 'Background tmux install exited ${installResult.exitCode}: '
                        '${_resultText(installResult)}',
            );
          }
          emit(
            step: EnvironmentStep.tmux,
            status: EnvironmentStepStatus.running,
            message: 'tmux needs attention in Terminal…',
          );
          final terminal = await _launchTmuxSetup();
          emit(
            step: EnvironmentStep.tmux,
            status: EnvironmentStepStatus.needsTerminal,
            message: 'Complete the visible Homebrew prompts in Terminal. Harness never sees your password.',
            output: 'Background install failed; Terminal opened to retry tmux.',
            phase: EnvironmentSetupPhase.waitingForTerminal,
            terminalLogPath: terminal.log.path,
            terminalResultPath: terminal.result.path,
          );
          return state;
        }
      } else if (!tmuxReady) {
        emit(
          step: EnvironmentStep.tmux,
          status: EnvironmentStepStatus.running,
          message: 'Preparing tmux in a secure terminal…',
        );
        final terminal = await _launchTmuxSetup();
        emit(
          step: EnvironmentStep.tmux,
          status: EnvironmentStepStatus.needsTerminal,
          message: 'Complete any password or macOS prompts in Terminal. Harness never sees your password.',
          output: _isMacOS
              ? 'Terminal opened to install Homebrew and tmux.'
              : 'Terminal opened to install tmux.',
          phase: EnvironmentSetupPhase.waitingForTerminal,
          terminalLogPath: terminal.log.path,
          terminalResultPath: terminal.result.path,
        );
        return state;
      }

      if (!harnessReady) {
        emit(
          step: EnvironmentStep.harness,
          status: EnvironmentStepStatus.running,
          message: 'Installing managed Node and Harness CLI…',
        );
        await _ensureHarness((line) => emit(output: line));
        emit(
          step: EnvironmentStep.harness,
          status: EnvironmentStepStatus.ready,
          output: '✓ Harness CLI ready',
        );
      }

      if (!gridReady) {
        emit(
          step: EnvironmentStep.grid,
          status: EnvironmentStepStatus.running,
          message: 'Installing Grid CLI…',
        );
        await _ensureGrid((line) => emit(output: line));
        emit(
          step: EnvironmentStep.grid,
          status: EnvironmentStepStatus.ready,
          output: '✓ Grid CLI ready',
        );
      }

      emit(
        message: 'Verifying every required command…',
        phase: EnvironmentSetupPhase.verifying,
      );
      final finalChecks = <EnvironmentStep, Future<bool> Function()>{
        EnvironmentStep.tmux: _isTmuxEnvironmentReady,
        EnvironmentStep.harness: _hasHarness,
        EnvironmentStep.grid: _hasGrid,
      };
      for (final entry in finalChecks.entries) {
        if (!await entry.value()) {
          emit(step: entry.key, status: EnvironmentStepStatus.failed);
          throw StateError(
            '${entry.key.name} did not pass final version verification.',
          );
        }
      }
      emit(message: 'Environment ready.', phase: EnvironmentSetupPhase.ready);
      return state;
    } catch (error) {
      final failed =
          state.steps.entries
              .where((entry) => entry.value == EnvironmentStepStatus.running)
              .map((entry) => entry.key)
              .firstOrNull ??
          state.steps.entries
              .where((entry) => entry.value == EnvironmentStepStatus.failed)
              .map((entry) => entry.key)
              .firstOrNull;
      emit(
        step: failed,
        status: EnvironmentStepStatus.failed,
        message: 'Environment setup failed: $error',
        phase: EnvironmentSetupPhase.failed,
        failure: EnvironmentFailure(
          step: failed,
          title: 'Setup could not finish',
          detail: '$error',
          command: failed == null ? null : _manualCommandFor(failed),
        ),
      );
      return state;
    }
  }

  /// Windows gets a VERIFY pass rather than the install pass above.
  ///
  /// Every installer this class drives is a POSIX shell script — `install.sh` piped into `/bin/sh`,
  /// a `zsh`/`bash` login shell for each probe, `brew`, `apt-get` — and none of it exists here. So
  /// instead of refusing to boot a Windows box that is in fact provisioned, this checks what is
  /// actually on it and names the command for whatever is missing. Windows packaging remains out
  /// of scope for this release.
  Future<void> _verifyWindows(EmitStep emit) async {
    emit(
      step: EnvironmentStep.harness,
      status: EnvironmentStepStatus.running,
      message: 'Checking the Harness CLI…',
    );
    var harnessReady = false;
    try {
      final runner = HarnessCliRunner(
        harnessHome: harnessHome,
        runProcess: _run,
      );
      final status = await runner.run(['auth', 'status', '--json']);
      harnessReady =
          status.exitCode == 0 && (status.stdout as String).trim().isNotEmpty;
    } on ProcessException {
      harnessReady = false;
    } on StateError {
      // No managed node/cli.js pair recorded under ~/.harness yet.
      harnessReady = false;
    }
    if (!harnessReady) {
      emit(
        step: EnvironmentStep.harness,
        status: EnvironmentStepStatus.failed,
        message:
            'The Harness CLI is not installed for this user. There is no Windows installer yet — '
            'from a checkout of the CLI run: npm install && npm run bundle && '
            'bash scripts/install-cli.sh — then click Recheck.',
      );
      return;
    }
    emit(
      step: EnvironmentStep.harness,
      status: EnvironmentStepStatus.ready,
      output: 'Harness CLI ready',
    );

    emit(
      step: EnvironmentStep.tmux,
      status: EnvironmentStepStatus.unavailable,
      output:
          'tmux does not exist on Windows — terminals come from Herdr instead.',
    );

    emit(
      step: EnvironmentStep.grid,
      status: EnvironmentStepStatus.running,
      message: 'Checking the Grid CLI…',
    );
    final grid = await _hasGridOnWindows();
    emit(
      step: EnvironmentStep.grid,
      status: grid ? EnvironmentStepStatus.ready : EnvironmentStepStatus.failed,
      message: grid ? 'Grid CLI ready.' : 'Grid CLI is required.',
      output: grid ? 'Grid CLI ready' : 'Grid CLI unavailable.',
    );
  }

  /// [_hasGrid]'s probe is `command -v` inside a login shell, neither of which Windows has. This
  /// names the path the installer writes first, then falls back to PATH.
  Future<bool> _hasGridOnWindows() async {
    final home = userHome();
    final candidates = <String>[
      if (home != null)
        '$home${Platform.pathSeparator}.local${Platform.pathSeparator}bin'
            '${Platform.pathSeparator}grid.exe',
      'grid',
    ];
    for (final candidate in candidates) {
      try {
        final probe = await _run(candidate, ['--version']);
        if (probe.exitCode == 0) return true;
      } on ProcessException {
        continue;
      }
    }
    return false;
  }

  Future<EnvironmentFailure?> _systemPreflightFailure() async {
    final tools = _isMacOS
        ? 'command -v sh zsh bash curl tar sed awk shasum >/dev/null'
        : 'command -v sh bash curl tar sed awk sha256sum >/dev/null';
    final base = await _shell(tools);
    if (base.exitCode != 0) {
      return EnvironmentFailure(
        title: 'Required system tools are missing',
        detail: _resultText(base).isEmpty
            ? 'Harness needs curl, tar, sed, awk, checksum tools and a POSIX shell.'
            : _resultText(base),
        command: _isMacOS
            ? 'xcode-select --install'
            : 'sudo apt-get install -y bash curl tar sed gawk coreutils',
      );
    }
    final writable = await _shell('test -w "\$HOME"');
    if (writable.exitCode != 0) {
      return const EnvironmentFailure(
        title: 'Home directory is not writable',
        detail: 'Harness needs to write ~/.harness and ~/.local/bin.',
      );
    }
    return null;
  }

  Future<bool> _hasHarness() async {
    final currentNode = File('${harnessHome.path}/runtime/current-node');
    if (!await currentNode.exists()) return false;
    final nodePath = (await currentNode.readAsString()).trim();
    if (nodePath.isEmpty || !File(nodePath).existsSync()) return false;
    final runtimeRoot = '${harnessHome.absolute.path}/runtime/';
    if (!File(nodePath).absolute.path.startsWith(runtimeRoot)) return false;
    final node = await _run(nodePath, ['--version']);
    if (node.exitCode != 0) return false;
    final match = RegExp(r'^v?(\d+)').firstMatch('${node.stdout}'.trim());
    if (match == null || int.parse(match.group(1)!) < 20) return false;
    try {
      final cli = File('${harnessHome.path}/cli/cli.js');
      if (!await cli.exists()) return false;
      final version = await _run(nodePath, [cli.path, 'version']);
      return version.exitCode == 0;
    } on ProcessException {
      return false;
    } on StateError {
      return false;
    }
  }

  Future<void> _ensureHarness(void Function(String line) onOutput) async {
    final runner = HarnessCliRunner(harnessHome: harnessHome, runProcess: _run);
    if (await _hasHarness()) return;
    // No interpreter is named here. install.sh provisions the same
    // checksum-verified Node under `~/.harness/runtime` when the computer has
    // none, records it in `current-node`, and bakes its absolute path into the
    // `~/.local/bin/harness` launcher — which is what makes a Finder launch,
    // where PATH is launchd's bare `/usr/bin:/bin:/usr/sbin:/sbin`, still find
    // a Node. Doing it there rather than here keeps ONE implementation of that,
    // shared with everyone who installs the CLI from a terminal.
    final install = await _shellStreaming(
      // Served off the CDN-fronted public bucket (autonomous-code: apps/web/scripts/cli-install.sh,
      // published with `make upload-cli-install-sh`), not by the web app. The old web-app URL,
      // https://harness.autonomous.ai/cli/install.sh, still redirects here, but pointing at the CDN
      // URL directly avoids that extra hop.
      // A stale URL is worse here than anywhere else: a 404 piped into bash still exits 0 (measured),
      // so the `install.exitCode != 0` check below would pass and the failure would only surface as
      // the confusing "CLI did not start after installation" a few lines further down.
      'set -e; $kHarnessDesktopInstallCommand',
      onOutput: onOutput,
    );
    if (install.exitCode != 0) {
      throw StateError(
        'Harness installer exited ${install.exitCode}: ${_resultText(install)}',
      );
    }
    final verified = await runner.run(['version']);
    if (verified.exitCode != 0 || !await _hasHarness()) {
      throw StateError(
        'Harness CLI verification exited ${verified.exitCode}: ${_resultText(verified)}',
      );
    }
  }

  Future<({File log, File result})> _launchTmuxSetup() async {
    // Package-manager installs can ask for a password. Always hand them to a
    // visible OS terminal instead of guessing whether this particular run will
    // prompt in a headless Process.run child.
    final script = await _writeTerminalBootstrapScript();
    await _openTerminal(script.path);
    return (
      log: File('${script.parent.path}/terminal.log'),
      result: File('${script.parent.path}/terminal.exit'),
    );
  }

  /// Installs the required Grid CLI when this computer has not got it.
  ///
  /// Install-if-missing, never upgrade-if-old. A developer running a build of
  /// `grid` from source must not have it replaced by a release on every launch
  /// — the same mistake the Harness CLI's self-update makes, and the reason
  /// [_ensureHarness] also stops at the first working answer.
  Future<void> _ensureGrid(void Function(String line) onOutput) async {
    if (await _hasGrid()) return;
    final install = await _shellStreaming(
      // The vendor installer: a `grid` binary on Linux, the universal wheel
      // via uv on macOS (which it bootstraps itself). It is `bash`, not `sh`.
      'set -e; curl -fsSL https://grid.autonomous.ai/install.sh | bash',
      onOutput: onOutput,
      // A first install pulls uv, a Python and the wheel's dependencies. The
      // ceiling is not a budget for that, it is a guard: an installer that
      // hangs on a captive-portal proxy must not hold the whole boot open.
      timeout: const Duration(minutes: 5),
    );
    if (install.exitCode != 0) {
      throw StateError(
        'Grid installer exited ${install.exitCode}: ${_resultText(install)}',
      );
    }
    if (!await _hasGrid()) {
      throw StateError(
        'Grid CLI did not pass `grid --version` after installation.',
      );
    }
  }

  /// Must agree with `GridCli.locate`, which reads `~/.local/bin/grid` first —
  /// [_shell] puts exactly that directory in front of a login shell's PATH, so
  /// "the provisioner installed it" and "the app can find it" cannot disagree.
  Future<bool> _hasGrid() async {
    final result = await _shell('command -v grid >/dev/null && grid --version');
    return result.exitCode == 0;
  }

  Future<bool> _hasTmux() async {
    final result = await _shell('command -v tmux >/dev/null && tmux -V');
    return result.exitCode == 0;
  }

  Future<bool> _hasHomebrew() async {
    final result = await _shell('command -v brew >/dev/null && brew --version');
    return result.exitCode == 0;
  }

  Future<bool> _isTmuxEnvironmentReady() async {
    if (_isMacOS && !await _hasAppleDeveloperTools()) return false;
    if (_isMacOS && !await _hasHomebrew()) return false;
    return _hasTmux();
  }

  /// `xcode-select -p` only proves that a path was selected. It also succeeds
  /// for an incomplete or moved Command Line Tools directory. Resolve a tool
  /// through xcrun so pre-flight reflects whether Homebrew can actually use
  /// the selected Apple toolchain.
  Future<bool> _hasAppleDeveloperTools() async {
    if (_forceMissingAppleDeveloperTools) return false;
    final result = await _shell(
      'command -v /usr/bin/xcrun >/dev/null 2>&1 && '
      '/usr/bin/xcrun --find clang >/dev/null 2>&1',
    );
    return result.exitCode == 0;
  }

  Future<File> _writeTerminalBootstrapScript() async {
    final directory = Directory(
      '${harnessHome.path}/desktop-app/setup-runs/${DateTime.now().millisecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    await _run('/bin/chmod', ['700', directory.path]);
    if (_isMacOS) {
      final script = File('${directory.path}/install-tmux.command');
      await script.writeAsString('''#!/bin/zsh
set -e
umask 077
LOG_FILE="${directory.path}/terminal.log"
RESULT_FILE="${directory.path}/terminal.exit"
exec > >(tee -a "\$LOG_FILE") 2>&1
finish() {
  status=\$?
  printf '%s\\n' "\$status" > "\$RESULT_FILE"
  if [ "\$status" -ne 0 ]; then
    echo
    echo 'System setup failed. Review the error above, then return to Harness.'
    read -r '?Press Enter to close this window…' || true
  fi
  return "\$status"
}
trap finish EXIT
apple_developer_tools_ready() {
  /usr/bin/xcrun --find clang >/dev/null 2>&1
}
if ! apple_developer_tools_ready; then
  if [ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]; then
    echo 'Xcode is installed but is not the active developer directory.'
    echo 'macOS may ask for your password to select it.'
    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  else
    echo 'Apple developer tools are missing. Installing Command Line Tools; finish the macOS dialog to continue.'
    xcode-select --install || true
  fi
  attempts=0
  until apple_developer_tools_ready; do
    attempts=\$((attempts + 1))
    if [ "\$attempts" -ge 200 ]; then
      echo 'Apple developer tools did not become ready within 10 minutes.' >&2
      echo 'Finish the macOS installer, then retry setup.' >&2
      exit 12
    fi
    sleep 3
  done
fi
if ! command -v brew >/dev/null 2>&1; then
  echo 'Installing Homebrew (macOS may ask for your password)…'
  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "\$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
brew install tmux
echo 'tmux is ready. Return to Harness.'
''', flush: true);
      await _run('/bin/chmod', ['700', script.path]);
      return script;
    }
    final script = File('${directory.path}/install-tmux.sh');
    await script.writeAsString('''#!/bin/bash
set -eu
umask 077
LOG_FILE="${directory.path}/terminal.log"
RESULT_FILE="${directory.path}/terminal.exit"
exec > >(tee -a "\$LOG_FILE") 2>&1

finish() {
  status=\$?
  printf '%s\\n' "\$status" > "\$RESULT_FILE"
  if [ "\$status" -eq 0 ]; then
    echo 'tmux is ready. Return to Harness and click Retry.'
  else
    echo
    echo 'tmux installation failed. Review the error above, then try again.'
    read -r -p 'Press Enter to close this window…' || true
  fi
  return "\$status"
}
trap finish EXIT

if command -v apt-get >/dev/null 2>&1; then
  apt_as_root() {
    if [ "\$(id -u)" -eq 0 ]; then apt-get "\$@"; else sudo apt-get "\$@"; fi
  }
  install_with_apt() {
    apt_as_root install -y "\$@" && return 0
    echo 'Refreshing package indexes before retrying…'
    apt_as_root update || true
    apt_as_root install -y "\$@"
  }
  echo 'Installing tmux (you may be asked for your password)…'
  install_with_apt tmux
  command -v tmux >/dev/null 2>&1
  tmux -V
  # Clipboard helpers improve image paste on Linux, but do not gate Desktop.
  install_with_apt xclip wl-clipboard || echo 'Clipboard helpers could not be installed; file-path paste remains available.'
else
  echo 'Automatic tmux install only supports apt-based distributions (Ubuntu/Debian).'
  echo "Install tmux with your distribution's package manager, then return to Harness and click Retry."
  exit 1
fi
''', flush: true);
    await _run('/bin/chmod', ['700', script.path]);
    return script;
  }

  Future<ProcessResult> _shell(
    String command, {
    Map<String, String>? environment,
    Duration? timeout,
  }) {
    final run = _run(_isMacOS ? '/bin/zsh' : '/bin/bash', [
      '-l',
      '-c',
      // The Homebrew prefixes are named rather than trusted to be on PATH, for
      // the same reason `GridCli.locate` names them: `-l` is a LOGIN shell but
      // not an interactive one, so it reads `~/.zprofile` and never `~/.zshrc`
      // — which is where `brew shellenv` sits on plenty of machines. A Finder
      // launch then starts from launchd's bare `/usr/bin:/bin:/usr/sbin:/sbin`
      // and this probe reports tmux missing on a computer that has it, then
      // "installs" it through whichever `brew` it can see. Measured: an Apple
      // Silicon Mac with both Homebrews picked up Intel `/usr/local/bin/brew`
      // and built openssl@3 from source under Rosetta, holding the boot open
      // on "Checking tmux…" for as long as that took. Apple Silicon first, so
      // a machine with both never installs through the Intel one. The CLI
      // closed the same gap in `lib/tmuxOnPath.ts`.
      'export PATH="\$HOME/.local/bin${_isMacOS ? ':/opt/homebrew/bin:/usr/local/bin' : ''}:\$PATH"; $command',
    ], environment: environment);
    if (timeout == null) return run;
    // The child keeps running — Process.run gives us no handle to kill. That is
    // the intent: a slow install finishes in the background and the next launch
    // finds it, while this one stops waiting.
    return run.timeout(
      timeout,
      onTimeout: () => ProcessResult(0, 124, '', 'timed out after $timeout'),
    );
  }

  Future<ProcessResult> _shellStreaming(
    String command, {
    required void Function(String line) onOutput,
    Duration? timeout,
  }) async {
    final shell = _isMacOS ? '/bin/zsh' : '/bin/bash';
    final wrapped =
        'export PATH="\$HOME/.local/bin${_isMacOS ? ':/opt/homebrew/bin:/usr/local/bin' : ''}:\$PATH"; $command';
    if (_start == null) {
      final result = await _shell(command, timeout: timeout);
      for (final line in '${result.stdout}\n${result.stderr}'.split('\n')) {
        if (line.trim().isNotEmpty) onOutput(line);
      }
      return result;
    }

    final process = await _start(shell, ['-l', '-c', wrapped]);
    final stdoutLines = <String>[];
    final stderrLines = <String>[];
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdoutLines.add(line);
          onOutput(line);
        });
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderrLines.add(line);
          onOutput(line);
        });
    final stdoutDone = stdoutSubscription.asFuture<void>();
    final stderrDone = stderrSubscription.asFuture<void>();
    var timedOut = false;
    final exit = timeout == null
        ? await process.exitCode
        : await process.exitCode.timeout(
            timeout,
            onTimeout: () {
              timedOut = true;
              process.kill();
              return 124;
            },
          );
    if (timedOut) {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    } else {
      await Future.wait([stdoutDone, stderrDone]);
    }
    return ProcessResult(
      process.pid,
      exit,
      stdoutLines.join('\n'),
      stderrLines.join('\n'),
    );
  }

  String _manualCommandFor(EnvironmentStep step) => switch (step) {
    EnvironmentStep.tmux =>
      _isMacOS
          ? 'brew install tmux && tmux -V'
          : 'sudo apt-get install -y tmux && tmux -V',
    EnvironmentStep.harness =>
      '$kHarnessDesktopInstallCommand && harness version',
    EnvironmentStep.grid => 'curl -fsSL https://grid.autonomous.ai/install.sh | bash && grid --version',
  };

  String _resultText(ProcessResult result) {
    final text = '${result.stderr}\n${result.stdout}'.trim();
    return text.length <= 700 ? text : text.substring(text.length - 700);
  }
}

extension on Iterable<EnvironmentStep> {
  EnvironmentStep? get firstOrNull => isEmpty ? null : first;
}
