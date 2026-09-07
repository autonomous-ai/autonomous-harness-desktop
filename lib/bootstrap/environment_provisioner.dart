import 'dart:async';
import 'dart:io';

import '../core/harness_cli_runner.dart';

enum EnvironmentStep {
  node,
  harness,
  tmux,
  grid;

  /// Whether the app refuses to boot without this step.
  ///
  /// Everything but [grid] is: no Node, no `harness`, no tmux means no
  /// terminals, which is the whole app. The Grid CLI only powers Share
  /// Intelligence, so a machine that could not install it still signs in and
  /// runs agents — `SharePane` explains the gap on the one screen that needs it.
  bool get isRequired => this != EnvironmentStep.grid;
}

enum EnvironmentStepStatus {
  pending,
  running,
  ready,
  needsTerminal,
  failed,

  /// Optional and not here: tried, did not land, and nothing is blocked by it.
  /// Distinct from [failed] so the setup screen does not offer a Retry for a
  /// step the app is content to go without.
  unavailable,
}

class EnvironmentReadiness {
  final Map<EnvironmentStep, EnvironmentStepStatus> steps;
  final String? message;
  final List<String> output;

  const EnvironmentReadiness({
    required this.steps,
    this.message,
    this.output = const [],
  });

  factory EnvironmentReadiness.initial() => EnvironmentReadiness(
    steps: {
      for (final step in EnvironmentStep.values)
        step: EnvironmentStepStatus.pending,
    },
  );

  bool get isReady => steps.entries
      .where((entry) => entry.key.isRequired)
      .every((entry) => entry.value == EnvironmentStepStatus.ready);

  bool get needsTerminal => steps.values.any(
    (status) => status == EnvironmentStepStatus.needsTerminal,
  );

  EnvironmentReadiness copyWith({
    Map<EnvironmentStep, EnvironmentStepStatus>? steps,
    String? message,
    List<String>? output,
  }) => EnvironmentReadiness(
    steps: steps ?? this.steps,
    message: message,
    output: output ?? this.output,
  );
}

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

typedef TerminalLauncher = Future<void> Function(String scriptPath);

Future<ProcessResult> _defaultRun(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(executable, arguments, environment: environment);

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

/// Prepares the only system dependencies required by the desktop transport:
/// a real, system-wide Node.js (`>= 22`) and tmux — both installed through the
/// OS's own package manager (Homebrew on macOS, `apt`/NodeSource on Linux),
/// on the PATH for every terminal and tool on the machine, not a private copy
/// under `harnessHome`. Neither install can always happen silently — a fresh
/// Homebrew install and any `apt-get install` need a real tty for a password
/// prompt — so this falls back to opening a terminal and asking the user to
/// retry once it's done, same as the CLI's own installer would.
class EnvironmentProvisioner {
  final Directory harnessHome;
  final ProcessRunner _run;
  final TerminalLauncher _openTerminal;
  final bool _isMacOS;
  final bool _isLinux;

  EnvironmentProvisioner({
    Directory? harnessHome,
    ProcessRunner? run,
    TerminalLauncher? openTerminal,
    bool? isMacOS,
    bool? isLinux,
  }) : harnessHome = harnessHome ?? Directory(_defaultHarnessHome()),
       _run = run ?? _defaultRun,
       _openTerminal = openTerminal ?? _defaultOpenTerminal,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isLinux = isLinux ?? Platform.isLinux;

  static String _defaultHarnessHome() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Could not resolve the current user home directory');
    }
    return '$home/.harness';
  }

  Future<EnvironmentReadiness> ensureReady({
    required void Function(EnvironmentReadiness value) onProgress,
  }) async {
    var state = EnvironmentReadiness.initial();
    void emit({
      EnvironmentStep? step,
      EnvironmentStepStatus? status,
      String? message,
      String? output,
    }) {
      final next = Map<EnvironmentStep, EnvironmentStepStatus>.from(
        state.steps,
      );
      if (step != null && status != null) next[step] = status;
      final lines = [...state.output];
      if (output != null && output.trim().isNotEmpty) {
        lines.add(output.trim());
        if (lines.length > 12) lines.removeRange(0, lines.length - 12);
      }
      state = EnvironmentReadiness(
        steps: next,
        message: message,
        output: lines,
      );
      onProgress(state);
    }

    if (!_isMacOS && !_isLinux) {
      emit(
        step: EnvironmentStep.node,
        status: EnvironmentStepStatus.failed,
        message: 'Automatic environment setup is currently available on macOS and Linux only.',
      );
      return state;
    }

    try {
      emit(
        step: EnvironmentStep.node,
        status: EnvironmentStepStatus.running,
        message: 'Checking Node.js…',
      );
      final node = await _ensureNode();
      if (node == null) {
        emit(
          step: EnvironmentStep.node,
          status: EnvironmentStepStatus.needsTerminal,
          message:
              'Complete the setup in the terminal window, then click Retry.',
          output: _isMacOS
              ? 'Terminal opened to install Homebrew, Node.js, and tmux.'
              : 'Terminal opened to install Node.js and tmux.',
        );
        return state;
      }
      emit(
        step: EnvironmentStep.node,
        status: EnvironmentStepStatus.ready,
        output: 'Node ready: ${node.path}',
      );

      emit(
        step: EnvironmentStep.harness,
        status: EnvironmentStepStatus.running,
        message: 'Installing Harness CLI…',
      );
      await _ensureHarness(node);
      emit(
        step: EnvironmentStep.harness,
        status: EnvironmentStepStatus.ready,
        output: 'Harness CLI ready',
      );

      emit(
        step: EnvironmentStep.tmux,
        status: EnvironmentStepStatus.running,
        message: 'Checking tmux…',
      );
      final tmux = await _ensureTmux();
      if (!tmux) {
        emit(
          step: EnvironmentStep.tmux,
          status: EnvironmentStepStatus.needsTerminal,
          message:
              'Complete the setup in the terminal window, then click Retry.',
          output: _isMacOS
              ? 'Terminal opened to install Homebrew and tmux.'
              : 'Terminal opened to install tmux.',
        );
        return state;
      }
      emit(
        step: EnvironmentStep.tmux,
        status: EnvironmentStepStatus.ready,
        output: 'tmux ready',
      );

      emit(
        step: EnvironmentStep.grid,
        status: EnvironmentStepStatus.running,
        message: 'Checking the Grid CLI…',
      );
      final grid = await _ensureGrid();
      emit(
        step: EnvironmentStep.grid,
        status: grid
            ? EnvironmentStepStatus.ready
            : EnvironmentStepStatus.unavailable,
        message: 'Environment ready.',
        output: grid
            ? 'Grid CLI ready'
            : 'Grid CLI unavailable — Share Intelligence stays off until it is '
                  'installed.',
      );
      return state;
    } catch (error) {
      final failed = state.steps.entries
          .where((entry) => entry.value == EnvironmentStepStatus.running)
          .map((entry) => entry.key)
          .firstOrNull;
      emit(
        step: failed,
        status: EnvironmentStepStatus.failed,
        message: 'Environment setup failed: $error',
      );
      return state;
    }
  }

  /// Resolves and validates the system Node, installing/upgrading it via the
  /// OS package manager when missing or too old. Returns null (not a thrown
  /// error) when that install needs an interactive terminal — the caller
  /// treats that as "needs terminal", not "failed".
  Future<File?> _ensureNode() async {
    final existing = await _systemNode();
    if (existing != null && await _isHealthyNode(existing)) return existing;

    if (_isMacOS) {
      final brew = await _shell('command -v brew');
      if (brew.exitCode == 0 && (brew.stdout as String).trim().isNotEmpty) {
        final install = await _shell(
          'brew list --versions node >/dev/null 2>&1 && brew upgrade node || brew install node',
        );
        if (install.exitCode != 0) {
          throw StateError(
            'Could not install Node via Homebrew: ${_resultText(install)}',
          );
        }
        final node = await _systemNode();
        if (node == null || !await _isHealthyNode(node)) {
          throw StateError(
            'Installed Node does not satisfy the Harness requirement',
          );
        }
        return node;
      }
    }
    // Linux (any distro), or a Mac without Homebrew: a fresh Homebrew install
    // wants a real tty the first time, and `apt-get install` needs sudo —
    // neither works from a non-interactive Process.run. Hand off to an
    // opened terminal instead, same escalation _ensureTmux() falls back to.
    await _openSystemSetupTerminal();
    return null;
  }

  Future<File?> _systemNode() async {
    final which = await _shell('command -v node');
    if (which.exitCode != 0) return null;
    final path = (which.stdout as String).trim();
    return path.isEmpty ? null : File(path);
  }

  Future<bool> _isHealthyNode(File node) async {
    final result = await _run(node.path, ['--version']);
    if (result.exitCode != 0) return false;
    final match = RegExp(r'^v?(\d+)\.')
        .firstMatch((result.stdout as String).trim());
    return match != null && int.parse(match.group(1)!) >= 22;
  }

  /// [node] is the runtime [_ensureNode] just validated. It has to be handed
  /// to the installer explicitly: a Finder/Dock launch inherits launchd's
  /// default PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), which contains neither
  /// `/opt/homebrew/bin` nor `/usr/local/bin`, so `command -v node` inside
  /// install.sh finds nothing and the script exits 1 with "Node.js (>= 20) is
  /// required but was not found" — directly under a Node step this same run
  /// reported ready. `HARNESS_NODE_BINARY` is the installer's documented hook
  /// for exactly this, and it also pins the launcher's shebang to the runtime
  /// we checked rather than to whatever the install-time PATH happened to hold.
  Future<void> _ensureHarness(File node) async {
    final runner = HarnessCliRunner(harnessHome: harnessHome, runProcess: _run);
    ProcessResult? status;
    try {
      status = await runner.run(['auth', 'status', '--json']);
    } on ProcessException {
      // No legacy launcher on a clean install yet; install below.
    }
    if (status != null &&
        status.exitCode == 0 &&
        (status.stdout as String).trim().isNotEmpty) {
      return;
    }
    final install = await _shell(
      // Served by the Harness web application; the retired top-level /install.sh is gone.
      // A stale URL is worse here than anywhere else: a 404 piped into bash still exits 0 (measured),
      // so the `install.exitCode != 0` check below would pass and the failure would only surface as
      // the confusing "CLI did not start after installation" a few lines further down.
      'set -e; curl -fsSL https://harness.autonomous.ai/cli/install.sh | /bin/sh',
      environment: {'HARNESS_NODE_BINARY': node.path},
    );
    if (install.exitCode != 0) {
      throw StateError('Harness installer failed: ${_resultText(install)}');
    }
    final verified = await runner.run(['auth', 'status', '--json']);
    if (verified.exitCode != 0 || (verified.stdout as String).trim().isEmpty) {
      throw StateError(
        'Harness CLI did not start after installation: ${_resultText(verified)}',
      );
    }
  }

  Future<bool> _ensureTmux() async {
    if (await _hasTmux()) return true;
    if (_isMacOS) {
      final brew = await _shell('command -v brew');
      if (brew.exitCode == 0 && (brew.stdout as String).trim().isNotEmpty) {
        final install = await _shell('brew install tmux');
        if (install.exitCode != 0) {
          throw StateError('Could not install tmux: ${_resultText(install)}');
        }
        return _hasTmux();
      }
    }
    // Linux (and a Mac without Homebrew): a package manager install needs a
    // password prompt with a real tty, which a non-interactive Process.run
    // can't supply — hand it to an opened terminal instead, same as the
    // Homebrew-install fallback above.
    await _openSystemSetupTerminal();
    return false;
  }

  /// Installs the Grid CLI when this computer has not got it.
  ///
  /// The second CLI this app depends on, and the only optional one: `grid`
  /// owns this computer's own inference — the models on its disk and the engine
  /// that serves them — which is what Share Intelligence drives. Nothing else
  /// in the app needs it, so this never throws: a machine that could not reach
  /// the installer signs in and runs agents exactly as before.
  ///
  /// Install-if-missing, never upgrade-if-old. A developer running a build of
  /// `grid` from source must not have it replaced by a release on every launch
  /// — the same mistake the Harness CLI's self-update makes, and the reason
  /// [_ensureHarness] also stops at the first working answer.
  Future<bool> _ensureGrid() async {
    try {
      if (await _hasGrid()) return true;
      final install = await _shell(
        // The vendor installer: a `grid` binary on Linux, the universal wheel
        // via uv on macOS (which it bootstraps itself). It is `bash`, not `sh`.
        'set -e; curl -fsSL https://grid.autonomous.ai/install.sh | bash',
        // A first install pulls uv, a Python and the wheel's dependencies. The
        // ceiling is not a budget for that, it is a guard: an installer that
        // hangs on a captive-portal proxy must not hold the whole boot open.
        timeout: const Duration(minutes: 5),
      );
      if (install.exitCode != 0) return false;
      return await _hasGrid();
    } catch (_) {
      // Nothing this can raise — a missing shell, a killed child — is worth
      // failing a boot the Grid CLI is not needed for.
      return false;
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

  /// Opens a terminal running the OS bootstrap script, which installs
  /// EVERYTHING this app needs system-wide (Node and tmux) rather than just
  /// whichever one dependency triggered the call — each install command is
  /// idempotent, so whichever step (node or tmux) hits this path first fixes
  /// both, and the other step's own check passes silently on retry without a
  /// second terminal round-trip.
  Future<void> _openSystemSetupTerminal() async {
    final script = await _writeSystemSetupScript();
    await _openTerminal(script.path);
  }

  Future<File> _writeSystemSetupScript() async {
    final directory = await Directory.systemTemp.createTemp('harness-setup-');
    if (_isMacOS) {
      final script = File('${directory.path}/harness-setup.command');
      await script.writeAsString('''#!/bin/zsh
set -e
if ! xcode-select -p >/dev/null 2>&1; then
  echo 'Installing Apple Command Line Tools. Finish the macOS dialog, then return to Harness and click Retry.'
  xcode-select --install || true
  exit 0
fi
if ! command -v brew >/dev/null 2>&1; then
  echo 'Installing Homebrew (macOS may ask for your password)…'
  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "\$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
echo 'Installing Node.js…'
brew list --versions node >/dev/null 2>&1 && brew upgrade node || brew install node
echo 'Installing tmux…'
brew install tmux
echo 'Node.js and tmux are ready. Return to Harness.'
''', flush: true);
      await _run('/bin/chmod', ['700', script.path]);
      return script;
    }
    final script = File('${directory.path}/harness-setup.sh');
    await script.writeAsString('''#!/bin/bash
set -e
if ! command -v apt-get >/dev/null 2>&1; then
  echo 'Automatic install only supports apt-based distributions (Ubuntu/Debian).'
  echo "Install Node.js >= 22 and tmux with your distribution's package manager, then return to Harness and click Retry."
  read -r -p 'Press Enter to close this window…'
  exit 0
fi
echo 'Installing Node.js and tmux (you may be asked for your password)…'
sudo apt-get update
NODE_MAJOR="\$(command -v node >/dev/null 2>&1 && node -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
if [ "\${NODE_MAJOR:-0}" -lt 22 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
sudo apt-get install -y tmux
echo 'Node.js and tmux are ready. Return to Harness.'
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
      'export PATH="\$HOME/.local/bin:\$PATH"; $command',
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

  String _resultText(ProcessResult result) {
    final text = '${result.stderr}\n${result.stdout}'.trim();
    return text.length <= 700 ? text : text.substring(text.length - 700);
  }
}

extension on Iterable<EnvironmentStep> {
  EnvironmentStep? get firstOrNull => isEmpty ? null : first;
}
