import 'dart:io';

import 'package:dio/dio.dart';
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

  test('rejects malformed or non-HTTPS managed runtime metadata', () {
    expect(
      () => ManagedNodeArtifact.fromJson({
        'version': '22.1.0',
        'url': 'http://example.test/node.tar.gz',
        'sha256': 'a' * 64,
        'size': 10,
        'archiveRoot': 'node-v22.1.0-darwin-arm64',
      }),
      throwsFormatException,
    );
    expect(
      () => ManagedNodeArtifact.fromJson({
        'version': '22.1.0',
        'url': 'https://example.test/node.tar.gz',
        'sha256': 'bad',
        'size': 10,
        'archiveRoot': 'node-v22.1.0-darwin-arm64',
      }),
      throwsFormatException,
    );
  });

  test(
    'uses a checksum-pinned official Node fallback for each Mac architecture',
    () {
      final arm = ManagedNodeArtifact.officialFallback('darwin-arm64');
      final intel = ManagedNodeArtifact.officialFallback('darwin-x64');

      expect(arm.version, 'v22.23.2');
      expect(arm.url.host, 'nodejs.org');
      expect(arm.url.path, contains('darwin-arm64.tar.gz'));
      expect(arm.sha256, hasLength(64));
      expect(intel.url.path, contains('darwin-x64.tar.gz'));
      expect(intel.sha256, isNot(arm.sha256));
    },
  );

  test('uses an existing managed Node and skips all downloads', () async {
    final runtime = Directory('${scratch.path}/runtime')
      ..createSync(recursive: true);
    final node = File('${runtime.path}/node-v22/bin/node')
      ..createSync(recursive: true);
    File('${runtime.path}/current-node').writeAsStringSync('${node.path}\n');
    final commands = <String>[];
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      dio: Dio(),
      isMacOS: true,
      architecture: () async => 'arm64',
      run: (executable, arguments, {environment}) async {
        commands.add('$executable ${arguments.join(' ')}');
        if (executable == node.path) return result(0, stdout: 'v22.4.1\n');
        return result(0, stdout: '{"loggedIn":false}\n');
      },
    );

    final states = <EnvironmentReadiness>[];
    final ready = await provisioner.ensureReady(onProgress: states.add);

    expect(ready.isReady, isTrue);
    expect(commands, contains(startsWith(node.path)));
    expect(commands.any((command) => command.contains('curl -fsSL')), isFalse);
    expect(states.last.steps.values, everyElement(EnvironmentStepStatus.ready));
  });

  test('repairs Harness with the managed Node binary', () async {
    final runtime = Directory('${scratch.path}/runtime')
      ..createSync(recursive: true);
    final node = File('${runtime.path}/node-v22/bin/node')
      ..createSync(recursive: true);
    File('${runtime.path}/current-node').writeAsStringSync('${node.path}\n');
    var statusCalls = 0;
    final installEnvironments = <Map<String, String>?>[];
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      architecture: () async => 'arm64',
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (executable == node.path) return result(0, stdout: 'v22.4.1\n');
        if (arguments.contains('auth') && arguments.contains('status')) {
          statusCalls++;
          return statusCalls == 1
              ? result(1, stderr: 'harness: command not found')
              : result(0, stdout: '{"loggedIn":false}\n');
        }
        if (command.contains('curl -fsSL')) {
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
    expect(installEnvironments.single?['HARNESS_NODE_BINARY'], node.path);
  });

  test('opens Terminal when tmux and Homebrew are unavailable', () async {
    final runtime = Directory('${scratch.path}/runtime')
      ..createSync(recursive: true);
    final node = File('${runtime.path}/node-v22/bin/node')
      ..createSync(recursive: true);
    File('${runtime.path}/current-node').writeAsStringSync('${node.path}\n');
    String? terminalScript;
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      architecture: () async => 'arm64',
      openTerminal: (path) async => terminalScript = path,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (executable == node.path) return result(0, stdout: 'v22.4.1\n');
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
}
