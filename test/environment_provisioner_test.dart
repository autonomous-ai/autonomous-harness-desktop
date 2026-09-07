import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/bootstrap/environment_provisioner.dart';

ProcessResult result(int exitCode, {String stdout = '', String stderr = ''}) =>
    ProcessResult(1, exitCode, stdout, stderr);

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp(
      'harness-environment-test-',
    );
  });

  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  test('installs the Harness CLI, letting it bring its own Node', () async {
    var statusCalls = 0;
    final installEnvironments = <Map<String, String>?>[];
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (arguments.contains('auth') && arguments.contains('status')) {
          statusCalls++;
          return statusCalls == 1
              ? result(1, stderr: 'harness: command not found')
              : result(0, stdout: '{"loggedIn":false}\n');
        }
        // Matched exactly, not on a bare `curl -fsSL`: the Grid CLI's installer
        // is one too, so a loose match would make this test depend on the Grid
        // probe happening to succeed first.
        if (command.contains('harness.autonomous.ai/cli/install.sh')) {
          installEnvironments.add(environment);
          return result(0, stdout: 'installed');
        }
        return result(0, stdout: 'tmux 3.4');
      },
    );

    final ready = await provisioner.ensureReady(onProgress: (_) {});

    expect(ready.isReady, isTrue);
    expect(statusCalls, 2);
    expect(installEnvironments, hasLength(1));
    // Deliberately NOT naming an interpreter any more: install.sh provisions and
    // records the managed runtime itself, so the app has none to hand over.
    expect(installEnvironments.single?.containsKey('HARNESS_NODE_BINARY'), isNot(isTrue));
  });

  test(
    'fails only when the platform is neither macOS nor Linux',
    () async {
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: false,
        isLinux: false,
          run: (executable, arguments, {environment}) async => result(0),
      );

      final readiness = await provisioner.ensureReady(onProgress: (_) {});

      expect(readiness.isReady, isFalse);
      // The message hangs off the first step, which is now the CLI one.
      expect(
        readiness.steps[EnvironmentStep.harness],
        EnvironmentStepStatus.failed,
      );
      expect(readiness.message, contains('macOS and Linux only'));
    },
  );

  test('provisions on Linux', () async {
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: false,
      isLinux: true,
      run: (executable, arguments, {environment}) async {
        if (arguments.contains('auth') && arguments.contains('status')) {
          return result(0, stdout: '{"loggedIn":false}\n');
        }
        return result(0, stdout: 'tmux 3.4');
      },
    );

    final ready = await provisioner.ensureReady(onProgress: (_) {});

    expect(ready.isReady, isTrue);
  });

  test('opens a terminal with an apt-based script on Linux', () async {
    String? terminalScript;
    final shellCommands = <String>[];
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: false,
      isLinux: true,
      openTerminal: (path) async => terminalScript = path,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        shellCommands.add(command);
        if (command.contains('tmux')) return result(1);
        if (arguments.contains('auth') && arguments.contains('status')) {
          return result(0, stdout: '{"loggedIn":false}\n');
        }
        return result(0);
      },
    );

    final readiness = await provisioner.ensureReady(onProgress: (_) {});

    expect(readiness.isReady, isFalse);
    expect(readiness.needsTerminal, isTrue);
    expect(terminalScript, isNotNull);
    // Linux never shells out to Homebrew.
    expect(shellCommands.any((c) => c.contains('brew')), isFalse);
    expect(
      await File(terminalScript!).readAsString(),
      contains('apt-get install -y tmux'),
    );
  });

  test('opens Terminal when tmux and Homebrew are unavailable', () async {
    String? terminalScript;
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      openTerminal: (path) async => terminalScript = path,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (command.contains('tmux')) return result(1);
        if (command.contains('command -v brew')) return result(1);
        if (arguments.contains('auth') && arguments.contains('status')) {
          return result(0, stdout: '{"loggedIn":false}\n');
        }
        return result(0);
      },
    );

    final readiness = await provisioner.ensureReady(onProgress: (_) {});

    expect(readiness.isReady, isFalse);
    expect(readiness.needsTerminal, isTrue);
    expect(
      readiness.steps[EnvironmentStep.tmux],
      EnvironmentStepStatus.needsTerminal,
    );
    expect(terminalScript, isNotNull);
    expect(
      await File(terminalScript!).readAsString(),
      contains('brew install tmux'),
    );
  });

  // --- The Grid CLI step, which the managed-runtime revert must not disturb ---


  test('installs the Grid CLI once, and never over an existing one', () async {
    var gridProbes = 0;
    var gridInstalls = 0;
    var gridPresent = false;
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (arguments.contains('auth') && arguments.contains('status')) {
          return result(0, stdout: '{"loggedIn":false}\n');
        }
        if (command.contains('grid.autonomous.ai/install.sh')) {
          gridInstalls++;
          gridPresent = true;
          return result(0, stdout: 'installed');
        }
        if (command.contains('grid --version')) {
          gridProbes++;
          return gridPresent ? result(0, stdout: 'grid 0.3.37') : result(1);
        }
        return result(0, stdout: 'tmux 3.4\n');
      },
    );

    final first = await provisioner.ensureReady(onProgress: (_) {});
    expect(first.isReady, isTrue);
    expect(first.steps[EnvironmentStep.grid], EnvironmentStepStatus.ready);
    expect(gridInstalls, 1);
    expect(gridProbes, 2); // missing, then verified after the install

    final second = await provisioner.ensureReady(onProgress: (_) {});
    expect(second.steps[EnvironmentStep.grid], EnvironmentStepStatus.ready);
    expect(gridInstalls, 1, reason: 'a present Grid CLI is left alone');
  });

  test('a Grid CLI that will not install does not block the app', () async {
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (arguments.contains('auth') && arguments.contains('status')) {
          return result(0, stdout: '{"loggedIn":false}\n');
        }
        if (command.contains('grid.autonomous.ai/install.sh')) {
          return result(1, stderr: 'could not resolve host');
        }
        if (command.contains('grid --version')) return result(1);
        return result(0, stdout: 'tmux 3.4\n');
      },
    );

    final readiness = await provisioner.ensureReady(onProgress: (_) {});

    // Optional means optional: `isReady` counts the REQUIRED steps, and the
    // step reads `unavailable` rather than `failed` so the setup screen offers
    // no Retry for something the app is content to go without.
    expect(readiness.isReady, isTrue);
    expect(
      readiness.steps[EnvironmentStep.grid],
      EnvironmentStepStatus.unavailable,
    );
    expect(readiness.needsTerminal, isFalse);
    expect(readiness.output.last, contains('Share Intelligence'));
  });

  /// The one path nothing else covers, and the whole point of the managed
  /// runtime: manifest → download → size → sha256 → `tar -xzf` → rename →
  /// `current-node`. It was deleted from production for a while, so it gets a
  /// real gzip archive and a real `tar`, not a stubbed one — the only fakes are
  /// the two HTTP responses and the `--version` probe of the dummy binary.
}
