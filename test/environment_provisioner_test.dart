import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/bootstrap/environment_provisioner.dart';

ProcessResult result(int exitCode, {String stdout = '', String stderr = ''}) =>
    ProcessResult(1, exitCode, stdout, stderr);

/// True for the executable `_shell()` always dispatches through (`/bin/zsh`
/// on macOS, `/bin/bash` on Linux) — the actual command is matched
/// separately, as a substring of the wrapped `-l -c` argument, same style
/// the provisioner's own tests have always used.
bool isShellCall(String executable) =>
    executable == '/bin/zsh' || executable == '/bin/bash';

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

  test('fails only when the platform is neither macOS nor Linux', () async {
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: false,
      isLinux: false,
      run: (executable, arguments, {environment}) async => result(0),
    );

    final readiness = await provisioner.ensureReady(onProgress: (_) {});

    expect(readiness.isReady, isFalse);
    expect(
      readiness.steps[EnvironmentStep.node],
      EnvironmentStepStatus.failed,
    );
    expect(readiness.message, contains('macOS and Linux only'));
  });

  test('uses a healthy system Node already on PATH, no install at all', () async {
    const nodePath = '/usr/local/bin/node';
    final commands = <String>[];
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        commands.add('$executable $command');
        if (isShellCall(executable) && command.contains('command -v node')) {
          return result(0, stdout: '$nodePath\n');
        }
        if (executable == nodePath) return result(0, stdout: 'v22.4.1\n');
        if (isShellCall(executable) && command.contains('command -v tmux')) {
          return result(0, stdout: 'tmux 3.4\n');
        }
        return result(0, stdout: '{"loggedIn":false}\n');
      },
    );

    final states = <EnvironmentReadiness>[];
    final ready = await provisioner.ensureReady(onProgress: states.add);

    expect(ready.isReady, isTrue);
    expect(commands, contains('$nodePath --version'));
    expect(commands.any((c) => c.contains('brew')), isFalse);
    expect(commands.any((c) => c.contains('apt-get')), isFalse);
    expect(states.last.steps.values, everyElement(EnvironmentStepStatus.ready));
  });

  test(
    'treats a system Node below the v22 floor as unhealthy and upgrades it via Homebrew',
    () async {
      const oldNode = '/usr/bin/node'; // some pre-existing, too-old install
      const upgradedNode = '/opt/homebrew/bin/node';
      var nodeInstalled = false;
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: true,
        run: (executable, arguments, {environment}) async {
          final command = arguments.join(' ');
          if (isShellCall(executable) && command.contains('command -v node')) {
            return result(
              0,
              stdout: nodeInstalled ? '$upgradedNode\n' : '$oldNode\n',
            );
          }
          if (executable == oldNode) return result(0, stdout: 'v20.4.1\n');
          if (executable == upgradedNode) return result(0, stdout: 'v22.4.1\n');
          if (isShellCall(executable) && command.contains('command -v brew')) {
            return result(0, stdout: '/opt/homebrew/bin/brew\n');
          }
          if (isShellCall(executable) && command.contains('brew upgrade node')) {
            nodeInstalled = true;
            return result(0);
          }
          if (isShellCall(executable) && command.contains('command -v tmux')) {
            return result(0, stdout: 'tmux 3.4\n');
          }
          return result(0, stdout: '{"loggedIn":false}\n');
        },
      );

      final ready = await provisioner.ensureReady(onProgress: (_) {});

      expect(ready.isReady, isTrue);
      expect(nodeInstalled, isTrue);
    },
  );

  test(
    'macOS with Homebrew present installs Node silently, no terminal',
    () async {
      const nodePath = '/opt/homebrew/bin/node';
      var nodeInstalled = false;
      String? terminalScript;
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: true,
        openTerminal: (path) async => terminalScript = path,
        run: (executable, arguments, {environment}) async {
          final command = arguments.join(' ');
          if (isShellCall(executable) && command.contains('command -v node')) {
            return nodeInstalled
                ? result(0, stdout: '$nodePath\n')
                : result(1);
          }
          if (executable == nodePath) return result(0, stdout: 'v22.4.1\n');
          if (isShellCall(executable) && command.contains('command -v brew')) {
            return result(0, stdout: '/opt/homebrew/bin/brew\n');
          }
          if (isShellCall(executable) &&
              (command.contains('brew upgrade node') ||
                  command.contains('brew install node'))) {
            nodeInstalled = true;
            return result(0);
          }
          if (isShellCall(executable) && command.contains('command -v tmux')) {
            return result(0, stdout: 'tmux 3.4\n');
          }
          return result(0, stdout: '{"loggedIn":false}\n');
        },
      );

      final ready = await provisioner.ensureReady(onProgress: (_) {});

      expect(ready.isReady, isTrue);
      expect(nodeInstalled, isTrue);
      expect(terminalScript, isNull);
    },
  );

  test(
    'macOS without Homebrew opens ONE terminal that installs Homebrew, Node, and tmux together',
    () async {
      String? terminalScript;
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: true,
        openTerminal: (path) async => terminalScript = path,
        run: (executable, arguments, {environment}) async {
          final command = arguments.join(' ');
          if (isShellCall(executable) && command.contains('command -v node')) {
            return result(1);
          }
          if (isShellCall(executable) && command.contains('command -v brew')) {
            return result(1);
          }
          return result(0);
        },
      );

      final readiness = await provisioner.ensureReady(onProgress: (_) {});

      expect(readiness.isReady, isFalse);
      expect(readiness.needsTerminal, isTrue);
      expect(
        readiness.steps[EnvironmentStep.node],
        EnvironmentStepStatus.needsTerminal,
      );
      // Node needing a terminal stops the flow before harness/tmux ever run.
      expect(readiness.steps[EnvironmentStep.harness], EnvironmentStepStatus.pending);
      expect(readiness.steps[EnvironmentStep.tmux], EnvironmentStepStatus.pending);
      expect(terminalScript, isNotNull);
      final script = await File(terminalScript!).readAsString();
      expect(script, contains('brew install node'));
      expect(script, contains('brew install tmux'));
    },
  );

  test(
    'Linux always escalates the Node install to a terminal (apt needs sudo), combined with tmux',
    () async {
      String? terminalScript;
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: false,
        isLinux: true,
        openTerminal: (path) async => terminalScript = path,
        run: (executable, arguments, {environment}) async {
          final command = arguments.join(' ');
          if (isShellCall(executable) && command.contains('command -v node')) {
            return result(1);
          }
          return result(0);
        },
      );

      final readiness = await provisioner.ensureReady(onProgress: (_) {});

      expect(readiness.isReady, isFalse);
      expect(readiness.needsTerminal, isTrue);
      expect(
        readiness.steps[EnvironmentStep.node],
        EnvironmentStepStatus.needsTerminal,
      );
      expect(terminalScript, isNotNull);
      final script = await File(terminalScript!).readAsString();
      expect(script, contains('deb.nodesource.com/setup_22.x'));
      expect(script, contains('apt-get install -y nodejs'));
      expect(script, contains('apt-get install -y tmux'));
      // Linux never shells out to Homebrew.
      expect(script.contains('brew'), isFalse);
    },
  );

  test('repairs Harness once a healthy system Node is present', () async {
    const nodePath = '/usr/local/bin/node';
    var statusCalls = 0;
    var installCalled = false;
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (isShellCall(executable) && command.contains('command -v node')) {
          return result(0, stdout: '$nodePath\n');
        }
        if (executable == nodePath) return result(0, stdout: 'v22.4.1\n');
        if (arguments.contains('auth') && arguments.contains('status')) {
          statusCalls++;
          return statusCalls == 1
              ? result(1, stderr: 'harness: command not found')
              : result(0, stdout: '{"loggedIn":false}\n');
        }
        if (command.contains('curl -fsSL')) {
          installCalled = true;
          return result(0, stdout: 'installed');
        }
        if (isShellCall(executable) && command.contains('command -v tmux')) {
          return result(0, stdout: 'tmux 3.4\n');
        }
        return result(0);
      },
    );

    final ready = await provisioner.ensureReady(onProgress: (_) {});

    expect(ready.isReady, isTrue);
    expect(statusCalls, 2);
    expect(installCalled, isTrue);
  });

  test('opens a terminal when only tmux is missing on Linux', () async {
    const nodePath = '/usr/bin/node';
    String? terminalScript;
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: false,
      isLinux: true,
      openTerminal: (path) async => terminalScript = path,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (isShellCall(executable) && command.contains('command -v node')) {
          return result(0, stdout: '$nodePath\n');
        }
        if (executable == nodePath) return result(0, stdout: 'v22.4.1\n');
        if (arguments.contains('auth') && arguments.contains('status')) {
          return result(0, stdout: '{"loggedIn":false}\n');
        }
        if (isShellCall(executable) && command.contains('command -v tmux')) {
          return result(1);
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
    // Node and harness both already passed before tmux triggered the terminal.
    expect(readiness.steps[EnvironmentStep.node], EnvironmentStepStatus.ready);
    expect(readiness.steps[EnvironmentStep.harness], EnvironmentStepStatus.ready);
    expect(terminalScript, isNotNull);
    expect(
      await File(terminalScript!).readAsString(),
      contains('apt-get install -y tmux'),
    );
  });

  test(
    'opens Terminal when only tmux is missing and Homebrew is unavailable on macOS',
    () async {
      const nodePath = '/usr/local/bin/node';
      String? terminalScript;
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: true,
        openTerminal: (path) async => terminalScript = path,
        run: (executable, arguments, {environment}) async {
          final command = arguments.join(' ');
          if (isShellCall(executable) && command.contains('command -v node')) {
            return result(0, stdout: '$nodePath\n');
          }
          if (executable == nodePath) return result(0, stdout: 'v22.4.1\n');
          if (arguments.contains('auth') && arguments.contains('status')) {
            return result(0, stdout: '{"loggedIn":false}\n');
          }
          if (isShellCall(executable) && command.contains('command -v tmux')) {
            return result(1);
          }
          if (isShellCall(executable) && command.contains('command -v brew')) {
            return result(1);
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
    },
  );
}
