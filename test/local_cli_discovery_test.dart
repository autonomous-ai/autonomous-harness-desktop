import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/config.dart';
import 'package:harness/ws/local_cli_discovery.dart';

void main() {
  HttpServer? server;
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('local-cli-discovery-');
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  test('uses the stable Harness computer id path', () {
    final path = LocalMachineIdentity.defaultComputerIdPath(
      environment: {'HOME': '/Users/tester'},
    );
    expect(path, '/Users/tester/.harness/computer-id');
  }, skip: Platform.isWindows);

  test('discovers only an exact-computer loopback endpoint', () async {
    const computerId = '0123456789abcdef0123456789abcdef';
    final identityFile = File('${scratch.path}/computer-id')
      ..writeAsStringSync('$computerId\n');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'computerId': computerId,
          'localWs': {
            'path': '/api/local-ws',
            'protocolVersion': 1,
            'terminalProtocolVersion': 3,
            'e2ee': false,
          },
        }),
      );
      await request.response.close();
    });
    final endpoint = await LocalCliDiscovery(
      config: AppConfig(
        apiBaseUrl: 'https://harness-api.autonomous.ai',
        localCliBaseUrl: 'http://127.0.0.1:${server!.port}',
      ),
      identity: LocalMachineIdentity(computerIdFile: identityFile),
    ).discover();
    expect(endpoint?.computerId, computerId);
    expect(
      endpoint?.wsUri.toString(),
      'ws://127.0.0.1:${server!.port}/api/local-ws',
    );
  });

  test(
    'waits while a new CLI is still performing initial terminal discovery',
    () async {
      const computerId = '0123456789abcdef0123456789abcdef';
      final identityFile = File('${scratch.path}/computer-id')
        ..writeAsStringSync(computerId);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'computerId': computerId,
            'discoveryReady': false,
            'localWs': {
              'path': '/api/local-ws',
              'protocolVersion': 1,
              'terminalProtocolVersion': 3,
              'e2ee': false,
            },
          }),
        );
        await request.response.close();
      });

      final endpoint = await LocalCliDiscovery(
        config: AppConfig(
          apiBaseUrl: 'https://harness-api.autonomous.ai',
          localCliBaseUrl: 'http://127.0.0.1:${server!.port}',
        ),
        identity: LocalMachineIdentity(computerIdFile: identityFile),
      ).discover();

      expect(endpoint, isNull);
    },
  );

  test('rejects non-loopback and mismatched status endpoints', () async {
    const computerId = 'abcdef0123456789abcdef0123456789';
    final identityFile = File('${scratch.path}/computer-id')
      ..writeAsStringSync(computerId);
    final nonLoopback = await LocalCliDiscovery(
      config: const AppConfig(
        apiBaseUrl: 'https://harness-api.autonomous.ai',
        localCliBaseUrl: 'http://example.com:18473',
      ),
      identity: LocalMachineIdentity(computerIdFile: identityFile),
    ).discover();
    expect(nonLoopback, isNull);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'computerId': 'fedcba9876543210fedcba9876543210',
          'localWs': {
            'path': '/api/local-ws',
            'protocolVersion': 1,
            'terminalProtocolVersion': 3,
            'e2ee': false,
          },
        }),
      );
      await request.response.close();
    });
    final mismatch = await LocalCliDiscovery(
      config: AppConfig(
        apiBaseUrl: 'https://harness-api.autonomous.ai',
        localCliBaseUrl: 'http://127.0.0.1:${server!.port}',
      ),
      identity: LocalMachineIdentity(computerIdFile: identityFile),
    ).discover();
    expect(mismatch, isNull);
  });

  test('does not accept missing or malformed computer id files', () async {
    final missing = await LocalMachineIdentity(
      computerIdFile: File('${scratch.path}/missing'),
    ).computerId();
    final malformedFile = File('${scratch.path}/malformed')
      ..writeAsStringSync('not-a-computer-id');
    final malformed = await LocalMachineIdentity(computerIdFile: malformedFile)
        .computerId();
    expect(missing, isNull);
    expect(malformed, isNull);
  });

  test('honors a pinned CLI computer id before the local file', () async {
    const computerId = '0123456789abcdef0123456789abcdef';
    final identity = LocalMachineIdentity(
      computerIdFile: File('${scratch.path}/missing'),
      environment: {'ADAPTER_COMPUTER_ID': computerId},
    );
    expect(await identity.computerId(), computerId);
  });

  test('ensureRunning returns the endpoint immediately when the daemon is already up, '
      'never needing to spawn `harness start`', () async {
    const computerId = '0123456789abcdef0123456789abcdef';
    final identityFile = File('${scratch.path}/computer-id')
      ..writeAsStringSync(computerId);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'computerId': computerId,
          'localWs': {
            'path': '/api/local-ws',
            'protocolVersion': 1,
            'terminalProtocolVersion': 3,
            'e2ee': false,
          },
        }),
      );
      await request.response.close();
    });
    final endpoint = await LocalCliDiscovery(
      config: AppConfig(
        apiBaseUrl: 'https://harness-api.autonomous.ai',
        localCliBaseUrl: 'http://127.0.0.1:${server!.port}',
      ),
      identity: LocalMachineIdentity(computerIdFile: identityFile),
    ).ensureRunning();
    expect(endpoint?.computerId, computerId);
  });

  // `ensureRunning`'s own "daemon not up yet, spawn `harness start` and poll" branch is covered by
  // `startSupervising` below via the same injectable `spawnCommand` seam — no live process is ever
  // launched by this suite.

  test('startSupervising spawns harness start while down, and stops once discovery succeeds', () async {
    const computerId = '0123456789abcdef0123456789abcdef';
    final identityFile = File('${scratch.path}/computer-id')
      ..writeAsStringSync(computerId);
    var up = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      if (!up) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'computerId': computerId,
          'localWs': {
            'path': '/api/local-ws',
            'protocolVersion': 1,
            'terminalProtocolVersion': 3,
            'e2ee': false,
          },
        }),
      );
      await request.response.close();
    });

    var spawnCount = 0;
    final discovery = LocalCliDiscovery(
      config: AppConfig(
        apiBaseUrl: 'https://harness-api.autonomous.ai',
        localCliBaseUrl: 'http://127.0.0.1:${server!.port}',
      ),
      identity: LocalMachineIdentity(computerIdFile: identityFile),
      spawnCommand: () async {
        spawnCount++;
        up = true; // simulate `harness start` succeeding
      },
    );

    final timer = discovery.startSupervising(
      checkInterval: const Duration(milliseconds: 20),
      graceStep: const Duration(milliseconds: 10),
      graceWindow: const Duration(milliseconds: 100),
      initialBackoff: const Duration(milliseconds: 200),
      maxBackoff: const Duration(milliseconds: 200),
    );
    addTearDown(timer.cancel);

    await Future.delayed(const Duration(milliseconds: 80));
    expect(spawnCount, 1);
    expect(up, isTrue);

    // Discovery now succeeds on every tick — no further spawn should ever happen.
    await Future.delayed(const Duration(milliseconds: 200));
    expect(spawnCount, 1);
  });

  test('startSupervising backs off between failed spawn attempts instead of spawning every tick', () async {
    const computerId = '0123456789abcdef0123456789abcdef';
    final identityFile = File('${scratch.path}/computer-id')
      ..writeAsStringSync(computerId);
    // A port nothing listens on — every discover() fails fast (connection refused), so the daemon
    // never comes up no matter how many times spawnCommand "runs" it.
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = probe.port;
    await probe.close(force: true);

    var spawnCount = 0;
    final discovery = LocalCliDiscovery(
      config: AppConfig(
        apiBaseUrl: 'https://harness-api.autonomous.ai',
        localCliBaseUrl: 'http://127.0.0.1:$closedPort',
      ),
      identity: LocalMachineIdentity(computerIdFile: identityFile),
      spawnCommand: () async {
        spawnCount++;
      },
    );

    final timer = discovery.startSupervising(
      checkInterval: const Duration(milliseconds: 20),
      graceStep: const Duration(milliseconds: 10),
      graceWindow: const Duration(milliseconds: 50),
      initialBackoff: const Duration(milliseconds: 150),
      maxBackoff: const Duration(milliseconds: 150),
    );
    addTearDown(timer.cancel);

    await Future.delayed(const Duration(milliseconds: 500));
    // Without backoff, ~500ms / 20ms checkInterval would spawn on nearly every tick (~25 times).
    // With backoff (each failed attempt costs ~50ms grace window + a 150ms floor before the next),
    // attempts are bounded to roughly 500 / 200 ≈ 2-3.
    expect(spawnCount, greaterThan(0));
    expect(spawnCount, lessThan(6));
  });
}
