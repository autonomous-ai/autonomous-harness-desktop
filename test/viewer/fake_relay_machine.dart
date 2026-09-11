import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:harness/e2ee/bytes.dart';
import 'package:harness/e2ee/cpace.dart';
import 'package:harness/e2ee/envelope.dart';
import 'package:harness/e2ee/keys.dart';
import 'package:harness/e2ee/password_pake.dart';
import 'package:harness/e2ee/primitives.dart';
import 'package:harness/e2ee/terminal_cipher.dart';
import 'package:harness/terminal/terminal_binary.dart';

/// A relay with one Harness machine behind it, playing the machine's half of both exchanges a
/// viewer runs — the password link (manager.ts `onPwPairIntent`/`onPwPake`) and the session
/// (`e2e_hello` → `e2e_welcome`) — out of the same lib/e2ee primitives the app uses, so a test
/// drives the app's side end to end over a real socket.
class FakeRelayMachine {
  FakeRelayMachine._(
    this._server,
    this.machineId,
    this.identity, {
    required this.password,
    this.selectError,
    this.welcomeSigner,
    this.denyHello = false,
  });

  static Future<FakeRelayMachine> start({
    required String machineId,
    required E2eeIdentity identity,
    String password = 'correct horse',
    String? selectError,
    E2eeIdentity? welcomeSigner,
    bool denyHello = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final machine = FakeRelayMachine._(
      server,
      machineId,
      identity,
      password: password,
      selectError: selectError,
      welcomeSigner: welcomeSigner,
      denyHello: denyHello,
    );
    server.listen(machine._onRequest);
    return machine;
  }

  final HttpServer _server;
  final String machineId;
  final E2eeIdentity identity;
  final String password;

  /// Answer `machine_select` with this refusal instead of the ack.
  final String? selectError;

  /// Sign the welcome with this identity instead — an impostor.
  final E2eeIdentity? welcomeSigner;

  /// Answer every hello with `e2e_denied`, as a machine that unpaired this device does.
  final bool denyHello;

  /// The credential each socket offered, as the relay saw it.
  final List<String> protocols = [];

  /// Every JSON frame the app sent, as it crossed the relay.
  final List<Map<String, dynamic>> wire = [];

  /// What the app's sealed frames said, once the machine opened them.
  final List<Map<String, dynamic>> opened = [];

  final List<TerminalBinaryFrame> terminalIn = [];

  /// The identity the app handed over when it linked.
  Uint8List? linkedPub;

  String get wsBaseUrl => 'ws://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  Future<void> _onRequest(HttpRequest request) async {
    protocols.add(request.headers.value('sec-websocket-protocol') ?? '');
    final socket = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: (offered) => offered.isNotEmpty ? offered.first : null,
    );
    final connection = _MachineConnection(this, socket);
    socket.listen(connection.onData);
  }
}

/// One socket's worth of machine state: its half of the PAKE, then of the session.
class _MachineConnection {
  _MachineConnection(this.machine, this.socket);

  final FakeRelayMachine machine;
  final WebSocket socket;

  late final String _ci = pwContext(machine.machineId);
  Uint8List? _sid;
  CpaceStart? _ours;
  Uint8List? _isk;
  Uint8List? _transcript;

  SessionKeys? _keys;
  Uint8List? _terminalC2s;
  Uint8List? _terminalS2c;
  int _s2cCounter = 1;
  int _terminalCounter = 0;

  Future<void> onData(dynamic data) async {
    if (data is List<int>) return _onBinary(Uint8List.fromList(data));
    final frame = jsonDecode(data as String) as Map<String, dynamic>;
    machine.wire.add(frame);
    final payload = frame['payload'] as Map<String, dynamic>;
    switch (frame['type']) {
      case 'machine_select':
        return _onSelect();
      case 'e2e_pw_pair_intent':
        return _onIntent(payload);
      case 'e2e_pw_pake' when payload['round'] == 2:
        return _onShare(payload);
      case 'e2e_pw_pake' when payload['round'] == 4:
        return _onIdentity(payload);
      case 'e2e_hello':
        return _onHello(payload);
    }
    if (isWrapped(payload)) _onSealed(frame['type'] as String, payload);
  }

  void _send(String type, Map<String, Object?> payload) =>
      socket.add(jsonEncode({'type': type, 'payload': payload}));

  void _onSelect() {
    final error = machine.selectError;
    if (error != null) {
      _send('machine_select_error', {'machineId': machine.machineId, 'error': error});
      return;
    }
    _send('connected', {'userId': 'user-1'});
    _send('connected', {'machineId': machine.machineId});
  }

  Future<void> _onIntent(Map<String, dynamic> payload) async {
    final sid = _sid = b64d(payload['sid'] as String);
    final stretched = await stretchPassword(machine.password, machine.machineId);
    final ours = _ours = cpaceStart(pwCpaceGenerator(stretched, sid, _ci));
    _send('e2e_pw_pake', {'sid': b64e(sid), 'round': 1, 'ya': b64e(ours.share)});
  }

  Future<void> _onShare(Map<String, dynamic> payload) async {
    final sid = _sid!, ours = _ours!;
    final theirs = b64d(payload['yb'] as String);
    final isk = _isk = cpaceIsk(sid, cpaceShared(theirs, ours.scalar), ours.share, theirs);
    final transcript = _transcript = transcriptHash(sid, _ci, ours.share, theirs);
    final kc = kcKeys(isk, _ci);
    if (!macVerify(kc.web, transcript, b64d(payload['mac'] as String))) {
      _send('e2e_pw_pake', {'sid': b64e(sid), 'round': 3, 'error': 'WRONG_PASSWORD'});
      return;
    }
    final claim = jsonEncode({
      'id': b64e(machine.identity.pub),
      'sig': b64e(await pairBindSig(machine.identity, transcript)),
    });
    _send('e2e_pw_pake', {
      'sid': b64e(sid),
      'round': 3,
      'mac': b64e(macTag(kc.adapter, transcript)),
      'enc': b64e(aeadSeal(pairKey(isk, _ci), 3, utf8Bytes('e2e-id'), utf8Bytes(claim))),
    });
  }

  Future<void> _onIdentity(Map<String, dynamic> payload) async {
    final opened = aeadOpen(
      pairKey(_isk!, _ci),
      4,
      utf8Bytes('e2e-id'),
      b64d(payload['enc'] as String),
    );
    final claim = jsonObjectOf(opened!)!;
    final pub = b64d(claim['id'] as String);
    final bound = await pairBindVerify(pub, _transcript!, b64d(claim['sig'] as String));
    machine.linkedPub = bound ? pub : null;
    _send('e2e_pw_pake', {'sid': b64e(_sid!), 'round': 5, 'ok': bound});
  }

  Future<void> _onHello(Map<String, dynamic> payload) async {
    if (machine.denyHello) {
      _send('e2e_denied', {'reason': 'unpaired'});
      return;
    }
    final clientEph = b64d(payload['ephPub'] as String);
    final ours = await Ephemeral.generate();
    final keys = _keys = sessionKeys(ours, clientEph, machine.machineId, clientEph, ours.pub);
    _terminalC2s = deriveTerminalBinaryKey(keys.c2s);
    _terminalS2c = deriveTerminalBinaryKey(keys.s2c);
    final signer = machine.welcomeSigner ?? machine.identity;
    final initial = jsonEncode({
      'groupKey': b64e(secureRandomBytes(32)),
      'epoch': 'e1',
      'features': {'terminalP2p': 1},
    });
    _send('e2e_welcome', {
      'webEphPub': b64e(clientEph),
      'ephPub': b64e(ours.pub),
      'sig': b64e(
        await signer.sign(lvCat(['e2e-welcome-v1', machine.machineId, clientEph, ours.pub])),
      ),
      'enc': b64e(aeadSeal(keys.s2c, 0, utf8Bytes('e2e-welcome'), utf8Bytes(initial))),
    });
  }

  void _onSealed(String type, Map<String, dynamic> payload) {
    final keys = _keys!;
    final clear = unwrapPayload(keys.c2s, payload['__e2e'] as Map<String, dynamic>, type, null);
    if (clear == null) return;
    machine.opened.add({'type': type, 'payload': clear});
    if (type != 'agents_list') return;
    final reply = {
      'requestId': clear['requestId'],
      'agents': [
        {'id': 'agent-1', 'name': 'Remote agent'},
      ],
    };
    _send(
      'agents_list_result',
      wrapPayload(keys.s2c, 'p', _s2cCounter++, 'agents_list_result', null, reply),
    );
  }

  /// Opens what the app typed and answers it with a line of output, both as the relay carries them.
  void _onBinary(Uint8List raw) {
    final opened = openTerminalBinary(_terminalC2s!, raw);
    if (opened == null) return;
    machine.terminalIn.add(opened.frame);
    final echo = TerminalBinaryFrame(
      kind: TerminalBinaryKind.output,
      streamId: opened.frame.streamId,
      seq: 1,
      bytes: utf8Bytes('echo'),
      compressed: false,
    );
    socket.add(sealTerminalBinary(_terminalS2c!, _terminalCounter++, echo)!);
  }
}
