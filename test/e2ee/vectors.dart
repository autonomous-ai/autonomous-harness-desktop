import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/e2ee/bytes.dart';
import 'package:harness/e2ee/keys.dart';
import 'package:harness/e2ee/relay_session_crypto.dart';

/// test/fixtures/e2ee_vectors.json, written by scripts/e2ee_vectors/gen.mts out of the harness
/// CLI's own crypto — so every expectation in test/e2ee/ is what a machine really computes.
final Map<String, dynamic> e2eeVectors =
    jsonDecode(File('test/fixtures/e2ee_vectors.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> section(String name) =>
    e2eeVectors[name] as Map<String, dynamic>;

String get vectorMachineId => e2eeVectors['machineId'] as String;

Uint8List hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// core.test.ts's `seeded` LCG, so a CPace scalar drawn here is the one the CLI drew.
Rng seeded(int seed) {
  var state = seed & 0xffffffff;
  return (length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      out[i] = state & 0xff;
    }
    return out;
  };
}

/// An [Rng] that returns exactly [bytes] — for a key the fixture already states.
Rng fixed(List<int> bytes) => (_) => Uint8List.fromList(bytes);

/// 'adapter' is the remote machine, 'client' this app.
Future<E2eeIdentity> vectorIdentity(String who) => E2eeIdentity.fromSeed(
  hexBytes(section('identities')[who]['seed'] as String),
);

Map<String, dynamic> welcomePayload() =>
    section('session')['welcome'] as Map<String, dynamic>;

/// This app's end of the fixture session before the welcome, pinned to the machine's identity
/// unless [peerPub] names another.
Future<RelaySessionCrypto> vectorClient({List<int>? peerPub}) async {
  final session = section('session');
  return RelaySessionCrypto.start(
    machineId: vectorMachineId,
    identity: await vectorIdentity('client'),
    peerPub:
        peerPub ??
        hexBytes(section('identities')['adapter']['pub'] as String),
    ephemeral: await Ephemeral.generate(
      fixed(hexBytes(session['clientEph']['priv'] as String)),
    ),
  );
}

/// [vectorClient] once the machine's welcome has landed.
Future<RelaySessionCrypto> welcomedVectorClient() async {
  final client = await vectorClient();
  expect(await client.handleWelcome(welcomePayload()), isTrue);
  return client;
}
