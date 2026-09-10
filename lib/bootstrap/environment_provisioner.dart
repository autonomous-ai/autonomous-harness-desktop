import 'dart:async';
import 'dart:io';

import '../core/harness_cli_runner.dart';

/// Bumped by hand whenever environment provisioning (Harness CLI, tmux, Grid CLI installs/repairs)
/// needs to run again for every machine on the next release, independent of the app's own version,
/// which changes on every build. A machine whose persisted `ConfigStore.environmentSetupVersion` is
/// still below this forces a fresh `_prepareEnvironment()` pass even if it was confirmed ready before.
const int kEnvironmentSetupVersion = 2;

enum EnvironmentStep {
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

/// Prepares the only system dependencies required by the desktop transport.
///
/// Node lives beneath [harnessHome] rather than in Homebrew/nvm/PATH. The
/// CLI launcher is written against that exact binary, so launching Harness
/// from Finder and from Terminal has identical runtime behavior.
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

  /// Runs the three steps in order, same as always when [resumeFrom] is omitted.
  ///
  /// Passing [resumeFrom] (the caller's current [EnvironmentReadiness]) skips any step already
  /// `ready` — or, for [EnvironmentStep.grid], already `unavailable` — instead of re-running it from
  /// [EnvironmentReadiness.initial]. This is what lets a stuck step be rechecked on its own: the two
  /// `_ensureX` calls are already "check first, act only if missing", so re-entering a step the user
  /// just fixed by hand simply confirms it and moves on, without flashing an already-`ready` step
  /// back through `pending`/`running`.
  Future<EnvironmentReadiness> ensureReady({
    required void Function(EnvironmentReadiness value) onProgress,
    EnvironmentReadiness? resumeFrom,
  }) async {
    var state = resumeFrom ?? EnvironmentReadiness.initial();
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
        step: EnvironmentStep.harness,
        status: EnvironmentStepStatus.failed,
        message: 'Automatic environment setup is currently available on macOS and Linux only.',
      );
      return state;
    }

    try {
      if (state.steps[EnvironmentStep.harness] != EnvironmentStepStatus.ready) {
        emit(
          step: EnvironmentStep.harness,
          status: EnvironmentStepStatus.running,
          message: 'Installing Harness CLI…',
        );
        await _ensureHarness();
        emit(
          step: EnvironmentStep.harness,
          status: EnvironmentStepStatus.ready,
          output: 'Harness CLI ready',
        );
      }

      if (state.steps[EnvironmentStep.tmux] != EnvironmentStepStatus.ready) {
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
            message: 'Complete the setup in the terminal window, then click Recheck.',
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
      }

      if (state.steps[EnvironmentStep.grid] != EnvironmentStepStatus.ready &&
          state.steps[EnvironmentStep.grid] !=
              EnvironmentStepStatus.unavailable) {
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
              : 'Grid CLI unavailable — this computer cannot be shared with a '
                    'grid until it is installed.',
        );
      }
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

  Future<void> _ensureHarness() async {
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
    // No interpreter is named here. install.sh provisions the same
    // checksum-verified Node under `~/.harness/runtime` when the computer has
    // none, records it in `current-node`, and bakes its absolute path into the
    // `~/.local/bin/harness` launcher — which is what makes a Finder launch,
    // where PATH is launchd's bare `/usr/bin:/bin:/usr/sbin:/sbin`, still find
    // a Node. Doing it there rather than here keeps ONE implementation of that,
    // shared with everyone who installs the CLI from a terminal.
    final install = await _shell(
      // Served off the CDN-fronted public bucket (autonomous-code: apps/web/scripts/cli-install.sh,
      // published with `make upload-cli-install-sh`), not by the web app. The old web-app URL,
      // https://harness.autonomous.ai/cli/install.sh, still redirects here, but pointing at the CDN
      // URL directly avoids that extra hop.
      // A stale URL is worse here than anywhere else: a 404 piped into bash still exits 0 (measured),
      // so the `install.exitCode != 0` check below would pass and the failure would only surface as
      // the confusing "CLI did not start after installation" a few lines further down.
      'set -e; curl -fsSL https://cdn.autonomous.ai/harness/cli/install.sh | /bin/sh',
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
    final script = await _writeTerminalBootstrapScript();
    await _openTerminal(script.path);
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

  Future<File> _writeTerminalBootstrapScript() async {
    final directory = await Directory.systemTemp.createTemp('harness-tmux-');
    if (_isMacOS) {
      final script = File('${directory.path}/install-tmux.command');
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
brew install tmux
echo 'tmux is ready. Return to Harness.'
''', flush: true);
      await _run('/bin/chmod', ['700', script.path]);
      return script;
    }
    final script = File('${directory.path}/install-tmux.sh');
    await script.writeAsString(r'''#!/bin/bash
set -eu

finish() {
  status=$?
  if [ "$status" -eq 0 ]; then
    echo 'tmux is ready. Return to Harness and click Retry.'
  else
    echo
    echo 'tmux installation failed. Review the error above, then try again.'
    read -r -p 'Press Enter to close this window…' || true
  fi
  return "$status"
}
trap finish EXIT

if command -v apt-get >/dev/null 2>&1; then
  echo 'Installing tmux, xclip and wl-clipboard (you may be asked for your password)…'
  # Installing these packages does not require refreshing every configured apt
  # source first. An error in any source would otherwise abort this repair
  # before apt ever reached the install. xclip/wl-clipboard (native image paste
  # into a remote OS clipboard) are bundled into this one password prompt
  # rather than a second one, but — unlike tmux — are best-effort: this step
  # only gates on tmux, so a clipboard-tool failure here still lets the retry
  # succeed and just falls back to pasting a file path instead.
  sudo apt-get install -y tmux xclip wl-clipboard || sudo apt-get install -y tmux
  command -v tmux >/dev/null 2>&1
  tmux -V
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

  String _resultText(ProcessResult result) {
    final text = '${result.stderr}\n${result.stdout}'.trim();
    return text.length <= 700 ? text : text.substring(text.length - 700);
  }
}

extension on Iterable<EnvironmentStep> {
  EnvironmentStep? get firstOrNull => isEmpty ? null : first;
}
