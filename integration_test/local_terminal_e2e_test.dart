import 'dart:async';

import 'package:harness/core/models.dart';
import 'package:harness/e2ee/client.dart';
import 'package:harness/e2ee/core.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:harness/ws/ws_conn.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const enabled = bool.fromEnvironment('LOCAL_TERMINAL_E2E');
  const wsBaseUrl = String.fromEnvironment('LOCAL_E2E_WS_BASE_URL');
  const apiKey = String.fromEnvironment('LOCAL_E2E_API_KEY');
  const machineId = String.fromEnvironment('LOCAL_E2E_MACHINE_ID');
  const setupToken = String.fromEnvironment('LOCAL_E2E_SETUP_TOKEN');
  const tmuxPane = String.fromEnvironment('LOCAL_E2E_TMUX_PANE');
  const marker = String.fromEnvironment(
    'LOCAL_E2E_TERMINAL_MARKER',
    defaultValue: 'LOCAL_TERMINAL_E2E_READY',
  );
  const input = String.fromEnvironment(
    'LOCAL_E2E_TERMINAL_INPUT',
    defaultValue: 'local-e2e-input-✓',
  );

  testWidgets('local backend + local CLI E2EE terminal stream', (tester) async {
    if (!enabled) {
      fail('Refusing local stack access without LOCAL_TERMINAL_E2E=true');
    }
    if (wsBaseUrl.isEmpty ||
        apiKey.isEmpty ||
        machineId.isEmpty ||
        setupToken.isEmpty ||
        tmuxPane.isEmpty) {
      fail(
        'Local E2E endpoint, machine key/id, setup token and exact pane are required',
      );
    }

    final client = _LocalTerminalClient(
      wsBaseUrl: wsBaseUrl,
      apiKey: apiKey,
      machineId: machineId,
      setupToken: setupToken,
    );
    addTearDown(client.close);
    await client.connect();

    final agent = await client.waitForAgent(
      engine: 'codex',
      tmuxPane: tmuxPane,
    );
    final capability = await client.connection.request(
      'terminal_capabilities',
      payload: {'protocolVersion': TerminalSession.protocolVersion},
    );
    expect(capability, containsPair('available', true));
    expect(capability, containsPair('backend', 'tmux'));
    expect(
      capability,
      containsPair('protocolVersion', TerminalSession.protocolVersion),
    );

    final terminal = client.openTerminal(agent);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: terminal,
            builder: (context, _) => ColoredBox(
              color: Colors.black,
              child: TerminalView(
                terminal.terminal,
                key: ValueKey(terminal.terminal),
                autofocus: true,
                readOnly: !terminal.acceptsInput,
                theme: TerminalThemes.whiteOnBlack,
              ),
            ),
          ),
        ),
      ),
    );
    await terminal.open(initialCols: 92, initialRows: 27);
    await _pumpUntil(
      tester,
      () =>
          terminal.status == TerminalSessionStatus.controlling &&
          terminal.terminal.buffer.getText().contains(marker),
      const Duration(seconds: 30),
      'initial keyframe marker',
    );

    terminal.terminal.textInput(input);
    terminal.terminal.keyInput(TerminalKey.enter);
    await _pumpUntil(
      tester,
      () =>
          terminal.terminal.buffer.getText().contains('LOCAL_E2E_ECHO:$input'),
      const Duration(seconds: 15),
      'round-trip keyboard input',
    );

    terminal.terminal.paste('local-paste-one\nlocal-paste-two');
    await _pumpUntil(
      tester,
      () => terminal.terminal.buffer.getText().contains(
        'LOCAL_E2E_ECHO:local-paste-one',
      ),
      const Duration(seconds: 15),
      'first line of multiline paste',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      terminal.terminal.buffer.getText(),
      isNot(contains('LOCAL_E2E_ECHO:local-paste-two')),
      reason: 'paste must preserve content without appending Enter',
    );
    terminal.terminal.keyInput(TerminalKey.enter);
    await _pumpUntil(
      tester,
      () => terminal.terminal.buffer.getText().contains(
        'LOCAL_E2E_ECHO:local-paste-two',
      ),
      const Duration(seconds: 15),
      'second line after explicit Enter',
    );

    // The fixture enabled DECSET 1000 + 1006 before the keyframe. A real
    // pointer gesture must therefore cross xterm -> TerminalSession -> CLI ->
    // tmux and make the fixture print its mouse acknowledgement.
    await tester.tapAt(tester.getCenter(find.byType(TerminalView)));
    await _pumpUntil(
      tester,
      () => terminal.terminal.buffer.getText().contains('LOCAL_E2E_MOUSE_OK'),
      const Duration(seconds: 15),
      'SGR mouse round trip',
    );

    terminal.resize(101, 33);
    await _pumpUntil(
      tester,
      () =>
          terminal.cols == 101 &&
          terminal.rows == 33 &&
          terminal.terminal.buffer.getText().contains(
            'LOCAL_E2E_RESIZE:101x33',
          ),
      const Duration(seconds: 15),
      'remote tmux resize',
    );

    // A real backend connId dies with the WebSocket. The Backend must notify
    // Harness so the old controller lease is released immediately; reconnect
    // remains non-resuming until an explicit new terminal_open.
    final oldStreamId = terminal.streamId;
    await client.dropTransport();
    await _pumpUntil(
      tester,
      () => terminal.status == TerminalSessionStatus.error,
      const Duration(seconds: 10),
      'local terminal freeze after transport drop',
    );
    await client.waitForReconnect();
    expect(terminal.status, TerminalSessionStatus.error);
    expect(terminal.streamId, isNull);

    await terminal.open(initialCols: 101, initialRows: 33);
    await _pumpUntil(
      tester,
      () =>
          terminal.status == TerminalSessionStatus.controlling &&
          terminal.streamId != oldStreamId &&
          terminal.terminal.buffer.getText().contains(marker),
      const Duration(seconds: 20),
      'explicit local attach after reconnect',
    );
  });
}

class _LocalTerminalClient {
  final String wsBaseUrl;
  final String apiKey;
  final String machineId;
  final String setupToken;
  final E2eePeer peer;
  final Completer<void> _connected = Completer<void>();
  final Completer<void> _e2eeReady = Completer<void>();
  Completer<void>? _reconnected;
  var _connectedCount = 0;
  TerminalSession? terminal;
  late final WsConn connection;

  _LocalTerminalClient({
    required this.wsBaseUrl,
    required this.apiKey,
    required this.machineId,
    required this.setupToken,
  }) : peer = E2eePeer(machineId) {
    connection = WsConn(
      wsBaseUrl: wsBaseUrl,
      autonomousEnv: 'prod',
      machineId: machineId,
      accessTokenProvider: (_, _) async => apiKey,
      onAuthFailure: (message) {
        if (!_connected.isCompleted) {
          _connected.completeError(StateError(message));
        }
      },
      onEvent: (event) async {
        final active = terminal;
        if (active == null) return;
        await active.handleFrame(
          event['type'] as String? ?? '',
          (event['payload'] as Map<String, dynamic>?) ?? const {},
        );
      },
      onStatus: (status) {
        if (status == ConnectionStatus.connected) {
          _connectedCount++;
          if (!_connected.isCompleted) {
            _connected.complete();
          } else {
            unawaited(_helloAfterReconnect());
          }
        } else if (status == ConnectionStatus.reconnecting ||
            status == ConnectionStatus.disconnected) {
          terminal?.transportLost();
        }
      },
    );
    connection.onOutgoing = (type, payload) =>
        wrapOutgoing(peer, type, payload);
    connection.onE2eeFrame = _handleE2eeFrame;
    connection.onBinaryFrame = (raw) async {
      final frame = await unwrapIncomingTerminalBinary(peer, raw);
      if (frame != null) await terminal?.handleBinary(frame);
    };
  }

  Future<void> connect() async {
    final verified = await verifySetupToken(
      setupToken,
      expectedMachineId: machineId,
      now: DateTime.now().millisecondsSinceEpoch,
    );
    if (verified == null) throw StateError('Harness setup token is invalid');
    peer.identity = await newIdentity();
    peer.identityPub = (await peer.identity!.extractPublicKey()).bytes;
    peer.peerPub = verified.adapterPub;

    await connection.connect();
    await _connected.future.timeout(const Duration(seconds: 15));
    final claim = await connection.request(
      'e2e_setup_claim',
      payload: {
        'token': setupToken,
        'identityPub': b64e(peer.identityPub!),
        'label': 'Flutter local terminal E2E',
        'sig': b64e(
          await setupClaimSig(
            peer.identity!,
            machineId,
            setupToken,
            peer.identityPub!,
          ),
        ),
      },
      timeout: const Duration(seconds: 10),
    );
    if (claim['ok'] != true) {
      throw StateError('Harness rejected setup claim: ${claim['error']}');
    }
    await sendHello(peer, connection.sendRaw, (_) {});
    await _e2eeReady.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _helloAfterReconnect() async {
    resetPeerSession(peer);
    await sendHello(peer, connection.sendRaw, (_) {});
  }

  Future<Map<String, dynamic>?> _handleE2eeFrame(
    Map<String, dynamic> frame,
  ) async {
    final type = frame['type'] as String? ?? '';
    final payload = (frame['payload'] as Map<String, dynamic>?) ?? const {};
    if (type == 'e2e_welcome') {
      await onWelcome(peer, payload, (_) {});
      if (peer.ready && !_e2eeReady.isCompleted) _e2eeReady.complete();
      if (peer.ready && _connectedCount > 1) {
        final waiting = _reconnected;
        if (waiting != null && !waiting.isCompleted) waiting.complete();
      }
      return null;
    }
    if (!payload.containsKey('__e2e')) {
      return {'type': type, 'payload': payload};
    }
    final envelope = payload['__e2e'];
    if (envelope is! Map<String, dynamic>) return null;
    final clear = await unwrapIncoming(
      peer,
      type,
      envelope,
      frame['dbSessionId'] as String?,
    );
    if (clear is! Map<String, dynamic>) return null;
    return {'type': type, 'payload': clear};
  }

  Future<Map<String, dynamic>> waitForAgent({
    required String engine,
    required String tmuxPane,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await connection.request(
          'agents_list',
          timeout: const Duration(seconds: 5),
        );
        for (final raw in response['agents'] as List<dynamic>? ?? const []) {
          final agent = raw as Map<String, dynamic>;
          final terminal = agent['terminal'];
          final runtimes = terminal is Map ? terminal['runtimes'] : null;
          final ownsFixturePane =
              runtimes is List &&
              runtimes.any(
                (runtime) =>
                    runtime is Map &&
                    runtime['backend'] == 'tmux' &&
                    runtime['paneId'] == tmuxPane,
              );
          if (agent['engine'] == engine && ownsFixturePane) {
            return agent;
          }
        }
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError(
      'No $engine agent for disposable pane $tmuxPane appeared: $lastError',
    );
  }

  TerminalSession openTerminal(Map<String, dynamic> agent) {
    return terminal = TerminalSession(
      machineId: machineId,
      agentId: agent['id'] as String,
      agentName: (agent['name'] as String?) ?? 'local-codex-fixture',
      engineId: agent['engine'] as String?,
      send: connection.sendTerminalFrame,
      sendBinary: (frame) async {
        final sealed = await wrapOutgoingTerminalBinary(peer, frame);
        return sealed != null && await connection.sendTerminalBinary(sealed);
      },
    );
  }

  Future<void> dropTransport() async {
    _reconnected = Completer<void>();
    await connection.debugDropTransport();
  }

  Future<void> waitForReconnect() async {
    final waiting = _reconnected;
    if (waiting == null) throw StateError('transport was not dropped');
    await waiting.future.timeout(const Duration(seconds: 20));
  }

  Future<void> close() async {
    await terminal?.close();
    terminal?.dispose();
    terminal = null;
    await connection.close();
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
  Duration timeout,
  String label,
) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $label');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
