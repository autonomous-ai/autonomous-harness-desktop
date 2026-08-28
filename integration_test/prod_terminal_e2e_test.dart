import 'dart:async';
import 'dart:convert';

import 'package:harness/e2ee/client.dart';
import 'package:harness/e2ee/peer_store.dart';
import 'package:harness/main.dart' as app;
import 'package:harness/core/models.dart';
import 'package:harness/screens/home_screen.dart';
import 'package:harness/screens/login_screen.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:harness/widgets/remote_setup_screen.dart';
import 'package:harness/widgets/terminal_panel.dart';
import 'package:harness/ws/ws_conn.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const enabled = bool.fromEnvironment('PROD_TERMINAL_E2E');
  const machineName = String.fromEnvironment('E2E_MACHINE_NAME');
  const agentName = String.fromEnvironment('E2E_AGENT_NAME');
  const secondAgentName = String.fromEnvironment('E2E_SECOND_AGENT_NAME');
  const marker = String.fromEnvironment('E2E_TERMINAL_MARKER');
  const secondMarker = String.fromEnvironment('E2E_SECOND_TERMINAL_MARKER');
  const autonomousEnv = String.fromEnvironment(
    'E2E_AUTONOMOUS_ENV',
    defaultValue: 'prod',
  );
  const input = String.fromEnvironment(
    'E2E_TERMINAL_INPUT',
    defaultValue: 'terminal-e2e-input-✓',
  );

  testWidgets('prod terminal/E2EE/controller lifecycle', (tester) async {
    if (!enabled) {
      fail('Refusing prod access without --dart-define=PROD_TERMINAL_E2E=true');
    }
    if ([
      machineName,
      agentName,
      secondAgentName,
      marker,
      secondMarker,
    ].any((value) => value.isEmpty)) {
      fail(
        'Prod E2E machine, two disposable agents and both markers are required',
      );
    }
    if (autonomousEnv != 'prod' && autonomousEnv != 'stag') {
      fail('E2E_AUTONOMOUS_ENV must be prod or stag');
    }

    app.main();
    await _pumpUntil(
      tester,
      () =>
          find.byType(HomeScreen).evaluate().isNotEmpty ||
          find.text('Sign in').evaluate().isNotEmpty,
      const Duration(seconds: 30),
      'saved production login',
    );
    if (find.text('Sign in').evaluate().isNotEmpty) {
      // The first run after clearing ~/.harness/desktop-app requires the normal
      // SSO flow. Real pointer events are captured by Flutter's integration-test
      // binding, so start it through WidgetTester and keep this process alive
      // while the operator completes the browser step. No token is passed
      // through source, dart-define or test logs.
      final login = tester.widget<LoginScreen>(find.byType(LoginScreen));
      await login.notifier.selectAutonomousEnv(autonomousEnv);
      await tester.pump();
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      // ignore: avoid_print
      print('MANUAL_LOGIN_REQUIRED: complete the $autonomousEnv SSO flow');
      await _pumpUntil(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
        const Duration(minutes: 10),
        'manual production SSO login',
      );
    }

    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    final notifier = home.notifier;
    await _pumpUntil(
      tester,
      () => find.text(machineName).evaluate().isNotEmpty,
      const Duration(seconds: 30),
      'dedicated machine row',
    );
    await tester.tap(find.text(machineName).first);
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          find.text(agentName).evaluate().isNotEmpty ||
          find.byType(RemoteSetupScreen).evaluate().isNotEmpty,
      const Duration(seconds: 30),
      'E2EE pairing or first disposable agent',
    );
    if (find.byType(RemoteSetupScreen).evaluate().isNotEmpty) {
      // Pair in this process as well so the ephemeral E2EE identity remains in
      // RAM and is shared by the second-controller assertion below.
      final machine = notifier.machines.singleWhere(
        (candidate) => candidate.displayName == machineName,
      );
      await _pumpUntil(
        tester,
        () => notifier.stateOf(machine.machineId)?.pairCode != null,
        const Duration(seconds: 10),
        'ephemeral E2EE pair code',
      );
      final pairCode = notifier.stateOf(machine.machineId)!.pairCode!;
      // ignore: avoid_print
      print('MANUAL_PAIR_REQUIRED: harness pair $pairCode');
      await _pumpUntil(
        tester,
        () => find.text(agentName).evaluate().isNotEmpty,
        const Duration(minutes: 5),
        'manual Harness E2EE pairing',
      );
    }
    await _pumpUntil(
      tester,
      () => find.text(secondAgentName).evaluate().isNotEmpty,
      const Duration(seconds: 30),
      'second disposable agent',
    );

    // Explicit user action: login/reconnect never auto-attaches a terminal.
    expect(find.byType(TerminalPanel), findsNothing);
    await tester.tap(find.text(agentName).first);
    final primary = await _waitForTerminal(
      tester,
      marker,
      expectedAgentName: agentName,
    );

    primary.terminal.textInput(input);
    primary.terminal.keyInput(TerminalKey.enter);
    await _waitForText(tester, primary, 'LOCAL_E2E_ECHO:$input');

    primary.terminal.keyInput(TerminalKey.arrowUp);
    primary.terminal.keyInput(TerminalKey.enter);
    await _waitForText(tester, primary, r'LOCAL_E2E_ECHO:\x1b[A');

    primary.terminal.keyInput(TerminalKey.keyC, ctrl: true);
    await _waitForText(tester, primary, 'LOCAL_E2E_CTRL_C');

    primary.terminal.paste('paste-one\npaste-two');
    await _waitForText(tester, primary, 'LOCAL_E2E_ECHO:paste-one');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      primary.terminal.buffer.getText(),
      isNot(contains('LOCAL_E2E_ECHO:paste-two')),
      reason: 'paste must not append an implicit Enter',
    );
    primary.terminal.keyInput(TerminalKey.enter);
    await _waitForText(tester, primary, 'LOCAL_E2E_ECHO:paste-two');

    await tester.tapAt(tester.getCenter(find.byType(TerminalView)));
    await _waitForText(tester, primary, 'LOCAL_E2E_MOUSE_OK');

    primary.resize(117, 36);
    await _waitForText(tester, primary, 'LOCAL_E2E_RESIZE:117x36');

    // Inject a client-observed gap, then prove the resync request crosses prod
    // and returns a fresh encrypted keyframe from the real Harness stream.
    await primary.handleFrame('terminal_output', {
      'protocolVersion': TerminalSession.protocolVersion,
      'streamId': primary.streamId,
      'seq': 1000000,
      'encoding': 'none',
      'data': base64Encode(utf8.encode('synthetic-gap')),
    });
    expect(primary.status, TerminalSessionStatus.resyncing);
    await _pumpUntil(
      tester,
      () =>
          primary.status == TerminalSessionStatus.controlling &&
          primary.terminal.buffer.getText().contains(marker),
      const Duration(seconds: 20),
      'prod keyframe resync',
    );

    final machine = notifier.machines.singleWhere(
      (candidate) => candidate.displayName == machineName,
    );
    final machineState = notifier.stateOf(machine.machineId)!;
    final primaryAgent = machineState.agents.singleWhere(
      (candidate) => candidate.name == agentName,
    );
    final secondController = _SecondController(
      machineId: machine.machineId,
      agentId: primaryAgent.id,
      accessToken: notifier.token!,
      wsBaseUrl: notifier.config.wsBaseUrl,
      autonomousEnv: notifier.autonomousEnv,
    );
    addTearDown(secondController.close);
    await secondController.connect();
    await secondController.open();
    await _pumpUntil(
      tester,
      () =>
          secondController.terminal?.status == TerminalSessionStatus.error &&
          secondController.terminal?.errorCode == 'CONTROL_LEASE_HELD',
      const Duration(seconds: 15),
      'second controller rejection',
    );

    // Switching agents closes the old stream before opening the new one.
    await tester.tap(find.text(secondAgentName).first);
    final secondary = await _waitForTerminal(
      tester,
      secondMarker,
      expectedAgentName: secondAgentName,
    );
    await secondController.open();
    await _pumpUntil(
      tester,
      () =>
          secondController.terminal?.status ==
              TerminalSessionStatus.controlling &&
          secondController.terminal!.terminal.buffer.getText().contains(marker),
      const Duration(seconds: 20),
      'released primary controller lease',
    );

    // Drop a live production socket while it controls the primary pane. The
    // old stream must freeze, input typed while disconnected must be discarded,
    // and reconnecting E2EE must not implicitly attach a replacement stream.
    final disconnected = secondController.terminal!;
    final oldStreamId = disconnected.streamId;
    final noReplaySentinel =
        'PROD_E2E_MUST_NOT_REPLAY_${DateTime.now().microsecondsSinceEpoch}';
    await secondController.dropTransport();
    await _pumpUntil(
      tester,
      () => disconnected.status == TerminalSessionStatus.error,
      const Duration(seconds: 10),
      'terminal freeze after production WebSocket disconnect',
    );
    disconnected.terminal.textInput(noReplaySentinel);
    disconnected.terminal.keyInput(TerminalKey.enter);
    await secondController.waitForReconnect();
    await tester.pump(const Duration(milliseconds: 500));
    expect(secondController.terminal, same(disconnected));
    expect(disconnected.status, TerminalSessionStatus.error);
    expect(disconnected.streamId, isNull);
    expect(
      disconnected.terminal.buffer.getText(),
      isNot(contains(noReplaySentinel)),
    );

    await secondController.open();
    await _pumpUntil(
      tester,
      () =>
          disconnected.status == TerminalSessionStatus.controlling &&
          disconnected.streamId != oldStreamId &&
          disconnected.terminal.buffer.getText().contains(marker),
      const Duration(seconds: 20),
      'explicit attach after production WebSocket reconnect',
    );
    expect(
      disconnected.terminal.buffer.getText(),
      isNot(contains(noReplaySentinel)),
    );
    await secondController.closeTerminal();

    // End the disposable process itself and require an explicit closed state.
    secondary.terminal.textInput('__EXIT__');
    secondary.terminal.keyInput(TerminalKey.enter);
    await _pumpUntil(
      tester,
      () =>
          secondary.status == TerminalSessionStatus.closed ||
          secondary.status == TerminalSessionStatus.error,
      const Duration(seconds: 20),
      'remote pane/process close',
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}

Future<TerminalSession> _waitForTerminal(
  WidgetTester tester,
  String marker, {
  required String expectedAgentName,
}) async {
  await _pumpUntil(
    tester,
    () => find.byType(TerminalPanel).evaluate().isNotEmpty,
    const Duration(seconds: 20),
    'terminal panel for $expectedAgentName',
  );
  late TerminalSession session;
  await _pumpUntil(
    tester,
    () {
      session = tester
          .widget<TerminalPanel>(find.byType(TerminalPanel))
          .session;
      return session.agentName == expectedAgentName &&
          session.status == TerminalSessionStatus.controlling &&
          session.terminal.buffer.getText().contains(marker);
    },
    const Duration(seconds: 30),
    'keyframe marker for $expectedAgentName',
  );
  return session;
}

Future<void> _waitForText(
  WidgetTester tester,
  TerminalSession session,
  String text,
) => _pumpUntil(
  tester,
  () => session.terminal.buffer.getText().contains(text),
  const Duration(seconds: 20),
  text,
);

class _SecondController {
  final String machineId;
  final String agentId;
  final String accessToken;
  final String wsBaseUrl;
  final String autonomousEnv;
  final E2eePeer peer;
  final Completer<void> _connected = Completer<void>();
  final Completer<void> _e2eeReady = Completer<void>();
  Completer<void>? _reconnected;
  var _connectedCount = 0;
  late final WsConn connection;
  TerminalSession? terminal;

  _SecondController({
    required this.machineId,
    required this.agentId,
    required this.accessToken,
    required this.wsBaseUrl,
    required this.autonomousEnv,
  }) : peer = E2eePeer(machineId) {
    connection = WsConn(
      wsBaseUrl: wsBaseUrl,
      autonomousEnv: autonomousEnv,
      machineId: machineId,
      accessTokenProvider: (_, _) async => accessToken,
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
    final store = SecurePeerStore();
    peer.identity = await store.identity();
    peer.identityPub = (await peer.identity!.extractPublicKey()).bytes;
    peer.peerPub = await store.pinOf(machineId);
    if (peer.peerPub == null) {
      throw StateError('MANUAL_PAIR_REQUIRED: no pinned Harness identity');
    }
    await connection.connect();
    await _connected.future.timeout(const Duration(seconds: 15));
    await sendHello(peer, connection.sendRaw, (_) {});
    await _e2eeReady.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _helloAfterReconnect() async {
    resetPeerSession(peer);
    await sendHello(peer, connection.sendRaw, (_) {});
  }

  Future<void> open() async {
    terminal ??= TerminalSession(
      machineId: machineId,
      agentId: agentId,
      agentName: 'second-controller',
      engineId: null,
      send: connection.sendTerminalFrame,
      sendBinary: (frame) async {
        final sealed = await wrapOutgoingTerminalBinary(peer, frame);
        return sealed != null && await connection.sendTerminalBinary(sealed);
      },
    );
    await terminal!.open(initialCols: 90, initialRows: 26);
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
    return clear is Map<String, dynamic>
        ? {'type': type, 'payload': clear}
        : null;
  }

  Future<void> closeTerminal() async {
    await terminal?.close();
    terminal?.dispose();
    terminal = null;
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
    await closeTerminal();
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
