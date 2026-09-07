import 'dart:io';

import 'package:cryptography/cryptography.dart';
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

  test(
    'uses a checksum-pinned official Node fallback for each Linux architecture',
    () {
      final x64 = ManagedNodeArtifact.officialFallback('linux-x64');
      final arm64 = ManagedNodeArtifact.officialFallback('linux-arm64');

      expect(x64.version, 'v22.23.2');
      expect(x64.url.host, 'nodejs.org');
      expect(x64.url.path, contains('linux-x64.tar.gz'));
      expect(x64.sha256, hasLength(64));
      expect(arm64.url.path, contains('linux-arm64.tar.gz'));
      expect(arm64.sha256, isNot(x64.sha256));
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
    expect(installEnvironments.single?['HARNESS_NODE_BINARY'], node.path);
  });

  test(
    'fails only when the platform is neither macOS nor Linux',
    () async {
      final provisioner = EnvironmentProvisioner(
        harnessHome: scratch,
        isMacOS: false,
        isLinux: false,
        architecture: () async => 'x86_64',
        run: (executable, arguments, {environment}) async => result(0),
      );

      final readiness = await provisioner.ensureReady(onProgress: (_) {});

      expect(readiness.isReady, isFalse);
      expect(
        readiness.steps[EnvironmentStep.node],
        EnvironmentStepStatus.failed,
      );
      expect(readiness.message, contains('macOS and Linux only'));
    },
  );

  test('provisions on Linux using an existing managed Node', () async {
    final runtime = Directory('${scratch.path}/runtime')
      ..createSync(recursive: true);
    final node = File('${runtime.path}/node-v22/bin/node')
      ..createSync(recursive: true);
    File('${runtime.path}/current-node').writeAsStringSync('${node.path}\n');
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: false,
      isLinux: true,
      architecture: () async => 'x86_64',
      run: (executable, arguments, {environment}) async {
        if (executable == node.path) return result(0, stdout: 'v22.4.1\n');
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
    final runtime = Directory('${scratch.path}/runtime')
      ..createSync(recursive: true);
    final node = File('${runtime.path}/node-v22/bin/node')
      ..createSync(recursive: true);
    File('${runtime.path}/current-node').writeAsStringSync('${node.path}\n');
    String? terminalScript;
    final shellCommands = <String>[];
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: false,
      isLinux: true,
      architecture: () async => 'x86_64',
      openTerminal: (path) async => terminalScript = path,
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        shellCommands.add(command);
        if (executable == node.path) return result(0, stdout: 'v22.4.1\n');
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

  // --- The Grid CLI step, which the managed-runtime revert must not disturb ---

  /// Lays down the managed Node the other Grid fixtures start from, so these
  /// exercise the Grid step and nothing else.
  ({Directory runtime, File node}) managedNode() {
    final runtime = Directory('${scratch.path}/runtime')
      ..createSync(recursive: true);
    final node = File('${runtime.path}/node-v22/bin/node')
      ..createSync(recursive: true);
    File('${runtime.path}/current-node').writeAsStringSync('${node.path}\n');
    return (runtime: runtime, node: node);
  }

  test('installs the Grid CLI once, and never over an existing one', () async {
    final node = managedNode().node;
    var gridProbes = 0;
    var gridInstalls = 0;
    var gridPresent = false;
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      architecture: () async => 'arm64',
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (executable == node.path) return result(0, stdout: 'v22.4.1\n');
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
    final node = managedNode().node;
    final provisioner = EnvironmentProvisioner(
      harnessHome: scratch,
      isMacOS: true,
      architecture: () async => 'arm64',
      run: (executable, arguments, {environment}) async {
        final command = arguments.join(' ');
        if (executable == node.path) return result(0, stdout: 'v22.4.1\n');
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
  test('downloads, verifies and installs a managed Node from the manifest', () async {
    const version = 'v22.23.2';
    const archiveRoot = 'node-$version-darwin-arm64';
    final harnessHome = Directory('${scratch.path}/home/.harness')
      ..createSync(recursive: true);

    // Build a genuine .tar.gz laid out the way nodejs.org ships one.
    final source = Directory('${scratch.path}/src')..createSync();
    File('${source.path}/$archiveRoot/bin/node')
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\necho $version\n');
    final archive = File('${scratch.path}/$archiveRoot.tar.gz');
    final packed = await Process.run('/usr/bin/tar', [
      '-czf', archive.path, '-C', source.path, archiveRoot,
    ]);
    expect(packed.exitCode, 0, reason: 'could not build the test archive');
    final bytes = await archive.readAsBytes();
    final digest = (await Sha256().hash(bytes)).bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    const archiveUrl = 'https://example.test/$archiveRoot.tar.gz';
    final requested = <String>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final url = options.uri.toString();
          requested.add(url);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: url == archiveUrl
                  ? bytes
                  : {
                      'node': {
                        'darwin-arm64': {
                          'version': version,
                          'url': archiveUrl,
                          'sha256': digest,
                          'size': bytes.length,
                          'archiveRoot': archiveRoot,
                        },
                      },
                    },
            ),
          );
        },
      ),
    );

    final provisioner = EnvironmentProvisioner(
      harnessHome: harnessHome,
      dio: dio,
      isMacOS: true,
      architecture: () async => 'arm64',
      run: (executable, arguments, {environment}) async {
        // The unpack and the private-mode calls have to really happen, or there
        // is nothing to assert about; everything else is stubbed.
        if (executable == '/usr/bin/tar' || executable == '/bin/chmod') {
          return Process.run(executable, arguments);
        }
        if (executable.endsWith('/bin/node')) {
          return result(0, stdout: '$version\n');
        }
        return result(0, stdout: '{"loggedIn":false}\n');
      },
    );

    final readiness = await provisioner.ensureReady(onProgress: (_) {});

    expect(readiness.isReady, isTrue);
    expect(requested, contains(archiveUrl));
    final installed = File(
      '${harnessHome.path}/runtime/node-$version-darwin-arm64/bin/node',
    );
    expect(installed.existsSync(), isTrue, reason: 'archive was not unpacked');
    expect(
      File('${harnessHome.path}/runtime/current-node').readAsStringSync().trim(),
      installed.path,
    );
    // Staging is cleaned up whatever happens.
    expect(
      Directory('${harnessHome.path}/runtime')
          .listSync()
          .map((entry) => entry.path.split('/').last)
          .where((name) => name.startsWith('.node-staging-')),
      isEmpty,
    );
  });

  test('refuses a managed Node whose bytes do not match the manifest', () async {
    final harnessHome = Directory('${scratch.path}/home/.harness')
      ..createSync(recursive: true);
    const archiveUrl = 'https://example.test/node.tar.gz';
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: options.uri.toString() == archiveUrl
                ? <int>[1, 2, 3, 4]
                : {
                    'node': {
                      'darwin-arm64': {
                        'version': 'v22.23.2',
                        'url': archiveUrl,
                        // Correct length, wrong content: the size check passes
                        // and only the checksum can catch this.
                        'sha256': 'a' * 64,
                        'size': 4,
                        'archiveRoot': 'node-v22.23.2-darwin-arm64',
                      },
                    },
                  },
          ),
        ),
      ),
    );

    final provisioner = EnvironmentProvisioner(
      harnessHome: harnessHome,
      dio: dio,
      isMacOS: true,
      architecture: () async => 'arm64',
      run: (executable, arguments, {environment}) async =>
          executable == '/bin/chmod'
          ? Process.run(executable, arguments)
          : result(0),
    );

    final readiness = await provisioner.ensureReady(onProgress: (_) {});

    expect(readiness.isReady, isFalse);
    expect(readiness.steps[EnvironmentStep.node], EnvironmentStepStatus.failed);
    expect(readiness.message, contains('checksum'));
    expect(
      File('${harnessHome.path}/runtime/current-node').existsSync(),
      isFalse,
      reason: 'a rejected download must not become the current runtime',
    );
  });
}
