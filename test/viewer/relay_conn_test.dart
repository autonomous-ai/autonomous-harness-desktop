import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/e2ee/bytes.dart';
import 'package:harness/e2ee/keys.dart';
import 'package:harness/e2ee/relay_session_crypto.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/viewer/e2ee_relay_codec.dart';
import 'package:harness/ws/relay_codec.dart';
import 'package:harness/ws/ws_conn.dart';

import 'fake_relay_machine.dart';

const _machineId = 'machine-1';
const _streamId = '0f8fad5b-d9cb-469f-a165-70867728950e';
const _wait = Duration(seconds: 10);

/// A viewer's relay connection, observed.
class _Dial {
  _Dial(FakeRelayMachine machine, RelayCodecFactory codecs) {
    conn = WsConn(
      wsBaseUrl: machine.wsBaseUrl,
      autonomousEnv: 'prod',
      machineId: _machineId,
      accessTokenProvider: (_, _) async => 'tok',
      onAuthFailure: (_) {},
      onLocalFailure: (code, reason) => refused.complete((code, reason)),
      onEvent: (_) {},
      onStatus: (status) {
        if (status == ConnectionStatus.connected && !connected.isCompleted) {
          connected.complete();
        }
      },
      relayCodecs: codecs,
    )..onBinaryFrame = (frame) async => binaryIn.add(frame);
    unawaited(conn.connect());
  }

  late final WsConn conn;
  final connected = Completer<void>();
  final refused = Completer<(int, String)>();
  final binaryIn = StreamController<Uint8List>();
}

void main() {
  late E2eeIdentity machineIdentity;
  late E2eeIdentity deviceIdentity;
  final machines = <FakeRelayMachine>[];
  final dials = <_Dial>[];

  setUpAll(() async {
    machineIdentity = await E2eeIdentity.generate();
    deviceIdentity = await E2eeIdentity.generate();
  });

  tearDown(() async {
    for (final dial in dials) {
      await dial.conn.close();
    }
    for (final machine in machines) {
      await machine.close();
    }
    dials.clear();
    machines.clear();
  });

  /// Sessions pinned to [pinned], or none — a machine this device never linked.
  RelayCodecFactory codecs(List<int>? pinned) => (machineId) async => pinned == null
      ? null
      : E2eeRelayCodec(
          await RelaySessionCrypto.start(
            machineId: machineId,
            identity: deviceIdentity,
            peerPub: pinned,
          ),
        );

  Future<(FakeRelayMachine, _Dial)> openDial({
    bool linked = true,
    E2eeIdentity? welcomeSigner,
    bool denyHello = false,
  }) async {
    final machine = await FakeRelayMachine.start(
      machineId: _machineId,
      identity: machineIdentity,
      welcomeSigner: welcomeSigner,
      denyHello: denyHello,
    );
    machines.add(machine);
    final dial = _Dial(machine, codecs(linked ? machineIdentity.pub : null));
    dials.add(dial);
    return (machine, dial);
  }

  test('is connected only once the welcome proves the pinned identity', () async {
    final (machine, dial) = await openDial();
    await dial.connected.future.timeout(_wait);
    expect(machine.protocols, ['tok']);
    expect(machine.wire.map((frame) => frame['type']), ['machine_select', 'e2e_hello']);
  });

  test('an RPC crosses the relay sealed, and its reply comes back opened', () async {
    final (machine, dial) = await openDial();
    final reply = await dial.conn.request('agents_list').timeout(_wait);
    expect(reply['agents'], [
      {'id': 'agent-1', 'name': 'Remote agent'},
    ]);
    final sent = machine.wire.firstWhere((frame) => frame['type'] == 'agents_list');
    expect((sent['payload'] as Map).keys, ['__e2e']);
    expect(machine.opened.single['payload'], contains('requestId'));
  });

  test('terminal bytes leave as HTRM and come back as HTRL', () async {
    final (machine, dial) = await openDial();
    await dial.connected.future.timeout(_wait);
    final typed = encodeTerminalLocal(
      TerminalBinaryFrame(
        kind: TerminalBinaryKind.input,
        streamId: _streamId,
        seq: 0,
        bytes: utf8Bytes('ls\r'),
        compressed: false,
      ),
    )!;
    expect(await dial.conn.sendTerminalBinary(typed), isTrue);
    final answered = await dial.binaryIn.stream.first.timeout(_wait);
    expect(machine.terminalIn.single.bytes, utf8Bytes('ls\r'));
    final echo = decodeTerminalLocal(answered)!;
    expect(echo.kind, TerminalBinaryKind.output);
    expect(echo.bytes, utf8Bytes('echo'));
  });

  test('a machine this device never linked is not dialed at all', () async {
    final (machine, dial) = await openDial(linked: false);
    expect(await dial.refused.future.timeout(_wait), (4404, 'NO_PEER_LINK'));
    expect(machine.protocols, isEmpty);
  });

  test('a machine that no longer trusts this device stops the connection', () async {
    final (_, dial) = await openDial(denyHello: true);
    expect(await dial.refused.future.timeout(_wait), (4404, 'E2E_DENIED'));
  });

  test('a welcome signed by any other identity stops the connection', () async {
    final (_, dial) = await openDial(welcomeSigner: await E2eeIdentity.generate());
    expect(await dial.refused.future.timeout(_wait), (4404, 'E2EE_WELCOME_INVALID'));
    expect(dial.connected.isCompleted, isFalse);
  });
}
