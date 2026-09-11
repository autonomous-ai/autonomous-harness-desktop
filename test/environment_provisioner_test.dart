import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/bootstrap/environment_provisioner.dart';

ProcessResult result(int exitCode, {String stdout = '', String stderr = ''}) =>
    ProcessResult(1, exitCode, stdout, stderr);

void main() {
  late Directory scratch;
  late File managedNode;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('harness-env-test-');
    managedNode = File('${scratch.path}/runtime/node-v20/bin/node');
  });

  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  Future<void> createManagedHarness() async {
    await managedNode.parent.create(recursive: true);
    await managedNode.writeAsString('node');
    await File('${scratch.path}/runtime/current-node')
        .writeAsString(managedNode.path);
    final cli = File('${scratch.path}/cli/cli.js');
    await cli.parent.create(recursive: true);
    await cli.writeAsString('cli');
  }

  ProcessRunner runner({
    required bool Function() tmuxPresent,
    required bool Function() gridPresent,
    bool developerToolsPresent = true,
    Future<void> Function()? installHarness,
    Future<void> Function()? installGrid,
    List<String>? calls,
    int gridInstallExitCode = 0,
  }) {
    return (executable, arguments, {environment}) async {
      final command = '$executable ${arguments.join(' ')}';
      calls?.add(command);
      final shell = arguments.isNotEmpty ? arguments.last : '';
      if (shell.contains('command -v tmux')) {
        return developerToolsPresent && tmuxPresent()
            ? result(0, stdout: 'tmux 3.4')
            : result(1);
      }
      if (shell.contains('/usr/bin/xcrun --find clang')) {
        return developerToolsPresent
            ? result(0, stdout: '/usr/bin/clang')
            : result(1, stderr: 'unable to find utility clang');
      }
      if (shell.contains('command -v grid')) {
        return gridPresent() ? result(0, stdout: 'grid 1.0') : result(1);
      }
      if (shell.contains('cdn.autonomous.ai/harness/cli/install.sh')) {
        await installHarness?.call();
        return result(0, stdout: 'Harness installed');
      }
      if (shell.contains('grid.autonomous.ai/install.sh')) {
        if (gridInstallExitCode == 0) await installGrid?.call();
        return result(
          gridInstallExitCode,
          stdout: gridInstallExitCode == 0 ? 'Grid installed' : '',
          stderr: gridInstallExitCode == 0 ? '' : 'network unavailable',
        );
      }
      if (executable == managedNode.path &&
          arguments.length == 1 &&
          arguments.first == '--version') {
        return result(0, stdout: 'v20.18.0');
      }
      if (executable == managedNode.path && arguments.contains('version')) {
        return result(0, stdout: 'harness 1.2.3');
      }
      // System tools, writable HOME and chmod.
      return result(0);
    };
  }

  test(
    'launch pre-flight is read-only when required tools are missing',
    () async {
      var terminalLaunches = 0;
      final calls = <String>[];
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: true,
        openTerminal: (_) async => terminalLaunches++,
        run: runner(
          tmuxPresent: () => false,
          gridPresent: () => false,
          calls: calls,
        ),
      );

      final readiness = await provisioner.ensureReady(
        onProgress: (_) {},
        install: false,
      );

      expect(readiness.isReady, isFalse);
      expect(readiness.phase, EnvironmentSetupPhase.review);
      expect(terminalLaunches, 0);
      expect(calls.where((line) => line.contains('install.sh')), isEmpty);
    },
  );

  test('an unusable selected developer directory is shown as missing during pre-flight', () async {
    var terminalLaunches = 0;
    final calls = <String>[];
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      openTerminal: (_) async => terminalLaunches++,
      run: runner(
        developerToolsPresent: false,
        tmuxPresent: () => true,
        gridPresent: () => false,
        calls: calls,
      ),
    );

    final readiness = await provisioner.ensureReady(
      onProgress: (_) {},
      install: false,
    );

    expect(readiness.phase, EnvironmentSetupPhase.review);
    expect(readiness.systemReady, isFalse);
    expect(readiness.output.join('\n'), contains('xcrun --find clang'));
    expect(
      calls.any((line) => line.contains('/usr/bin/xcrun --find clang')),
      isTrue,
    );
    expect(terminalLaunches, 0);
  });

  test('automatic setup repairs or installs Apple developer tools in Terminal', () async {
    String? terminalScript;
    final calls = <String>[];
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      openTerminal: (path) async => terminalScript = path,
      run: runner(
        developerToolsPresent: false,
        tmuxPresent: () => false,
        gridPresent: () => false,
        calls: calls,
      ),
    );

    final readiness = await provisioner.ensureReady(
      onProgress: (_) {},
      install: true,
      mode: EnvironmentSetupMode.automatic,
    );

    expect(readiness.phase, EnvironmentSetupPhase.waitingForTerminal);
    expect(readiness.systemReady, isFalse);
    expect(terminalScript, isNotNull);
    expect(calls.where((line) => line.contains('install.sh')), isEmpty);
    final script = await File(terminalScript!).readAsString();
    expect(script, contains('/usr/bin/xcrun --find clang'));
    expect(
      script,
      contains(
        'sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer',
      ),
    );
    expect(script, contains('xcode-select --install'));
    expect(script, contains('did not become ready within 10 minutes'));
    expect(
      (await Process.run('/bin/zsh', ['-n', terminalScript!])).exitCode,
      0,
    );
  });

  test(
    'automatic setup installs Harness before required Grid then verifies',
    () async {
      var gridPresent = false;
      final calls = <String>[];
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: true,
        run: runner(
          tmuxPresent: () => true,
          gridPresent: () => gridPresent,
          installHarness: createManagedHarness,
          installGrid: () async => gridPresent = true,
          calls: calls,
        ),
      );

      final readiness = await provisioner.ensureReady(
        onProgress: (_) {},
        install: true,
        mode: EnvironmentSetupMode.automatic,
      );

      final harnessInstall = calls.indexWhere(
        (line) => line.contains('cdn.autonomous.ai/harness/cli/install.sh'),
      );
      final gridInstall = calls.indexWhere(
        (line) => line.contains('grid.autonomous.ai/install.sh'),
      );
      expect(readiness.isReady, isTrue);
      expect(readiness.phase, EnvironmentSetupPhase.ready);
      expect(harnessInstall, greaterThan(-1));
      expect(gridInstall, greaterThan(harnessInstall));
      expect(calls[harnessInstall], contains('/bin/sh -s -- --desktop'));
    },
  );

  test(
    'missing tmux opens a real terminal before either CLI installer',
    () async {
      String? terminalScript;
      final calls = <String>[];
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: false,
        isLinux: true,
        openTerminal: (path) async => terminalScript = path,
        run: runner(
          tmuxPresent: () => false,
          gridPresent: () => false,
          calls: calls,
        ),
      );

      final readiness = await provisioner.ensureReady(
        onProgress: (_) {},
        install: true,
        mode: EnvironmentSetupMode.automatic,
      );

      expect(readiness.phase, EnvironmentSetupPhase.waitingForTerminal);
      expect(
        readiness.steps[EnvironmentStep.tmux],
        EnvironmentStepStatus.needsTerminal,
      );
      expect(terminalScript, isNotNull);
      expect(calls.where((line) => line.contains('install.sh')), isEmpty);
      final script = await File(terminalScript!).readAsString();
      expect(script, contains('install_with_apt tmux'));
      expect(script, contains('if [ "\$(id -u)" -eq 0 ]'));
      expect(script, contains('terminal.log'));
      expect(script, contains('tmux -V'));
      expect(
        (await Process.run('/bin/bash', ['-n', terminalScript!])).exitCode,
        0,
      );
    },
  );

  test('Grid install failure is a blocking, actionable error', () async {
    await createManagedHarness();
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      run: runner(
        tmuxPresent: () => true,
        gridPresent: () => false,
        gridInstallExitCode: 7,
      ),
    );

    final readiness = await provisioner.ensureReady(
      onProgress: (_) {},
      install: true,
      mode: EnvironmentSetupMode.automatic,
    );

    expect(readiness.isReady, isFalse);
    expect(readiness.phase, EnvironmentSetupPhase.failed);
    expect(readiness.steps[EnvironmentStep.grid], EnvironmentStepStatus.failed);
    expect(readiness.failure?.command, contains('grid --version'));
    expect(readiness.failure?.detail, contains('network unavailable'));
  });

  test(
    'a failed admin Terminal run surfaces its exit code and full log',
    () async {
      var launches = 0;
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: false,
        isLinux: true,
        openTerminal: (_) async => launches++,
        run: runner(tmuxPresent: () => false, gridPresent: () => false),
      );
      final waiting = await provisioner.ensureReady(
        onProgress: (_) {},
        install: true,
        mode: EnvironmentSetupMode.automatic,
      );
      await File(waiting.terminalLogPath!).writeAsString('apt: package failed');
      await File(waiting.terminalResultPath!).writeAsString('42\n');

      final failed = await provisioner.ensureReady(
        onProgress: (_) {},
        resumeFrom: waiting,
        install: false,
        mode: EnvironmentSetupMode.automatic,
      );

      expect(failed.phase, EnvironmentSetupPhase.failed);
      expect(failed.failure?.exitCode, 42);
      expect(failed.output.join('\n'), contains('apt: package failed'));
      expect(launches, 1, reason: 'a polling probe must not reopen Terminal');
    },
  );

  test(
    'a fully prepared machine passes a fresh read-only launch probe',
    () async {
      await createManagedHarness();
      final calls = <String>[];
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: true,
        run: runner(
          tmuxPresent: () => true,
          gridPresent: () => true,
          calls: calls,
        ),
      );

      final readiness = await provisioner.ensureReady(
        onProgress: (_) {},
        install: false,
      );

      expect(readiness.isReady, isTrue);
      expect(readiness.phase, EnvironmentSetupPhase.ready);
      expect(calls.where((line) => line.contains('install.sh')), isEmpty);
    },
  );
}
