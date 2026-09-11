import 'package:flutter_test/flutter_test.dart';
import 'package:harness/e2ee/bytes.dart';
import 'package:harness/e2ee/envelope.dart';
import 'package:harness/e2ee/keys.dart';
import 'package:harness/e2ee/primitives.dart';

import 'vectors.dart';

/// The CLI sources lib/e2ee/ was last read against. A fixture regenerated after the CLI changed
/// one of them fails here: read that diff, port it, and only then move the hash.
const _portedFrom = {
  'core': 'e21ceb78f3cf8ca56d09bc52daf336f89a75d05dd84ee6882c7b736cfd5bb415',
  'passwordPake':
      'd453f003011aad8458108c8cc8375b246da5c4b7264acbec4630e0d6cfe25edb',
  'relayClient':
      '27036eed62d7c563dc9782895e872e099bc20ffe060ecdb1bb544032ddb38da2',
  'terminalBinary':
      'beda7a15f9ca6b95624fb141fc502b971af103a6ba4e7d92ce06bfdbec1f1379',
};

void main() {
  final session = section('session');
  final identities = section('identities');
  final envelopes = section('envelopes');

  group('fixture', () {
    test('comes from the CLI sources this port was checked against', () {
      expect(section('meta')['sha256'], _portedFrom);
      expect(section('meta')['cliDirty'], isFalse);
    });

    test("seals exactly the CLI's relay-bound down types", () {
      expect(
        encryptedDownTypes.toList()..sort(),
        e2eeVectors['encryptedDownTypes'],
      );
    });
  });

  group('primitives', () {
    test('lvCat length-prefixes every part', () {
      expect(
        hexOf(
          lvCat([
            'ab',
            [1, 2, 3],
          ]),
        ),
        e2eeVectors['lvCat'],
      );
    });

    test('counterNonce carries a counter past 2^32', () {
      final vector = section('counterNonce');
      expect(hexOf(counterNonce(vector['counter'] as int)), vector['nonce']);
    });
  });

  for (final who in ['adapter', 'client']) {
    test("the $who seed derives the CLI's key and fingerprint", () async {
      final identity = await vectorIdentity(who);
      expect(hexOf(identity.pub), identities[who]['pub']);
      expect(fingerprint(identity.pub), identities[who]['fingerprint']);
    });
  }

  group('session', () {
    test("hello is the CLI's, byte for byte", () async {
      final client = await vectorClient();
      expect(client.helloFrame(), {
        'type': 'e2e_hello',
        'payload': session['hello'],
      });
    });

    test('X25519 then HKDF give both ends the same keys', () async {
      final eph = await Ephemeral.generate(
        fixed(hexBytes(session['clientEph']['priv'] as String)),
      );
      final adapterPub = hexBytes(session['adapterEph']['pub'] as String);
      final keys = sessionKeys(
        eph,
        adapterPub,
        vectorMachineId,
        eph.pub,
        adapterPub,
      );
      expect(hexOf(eph.pub), session['clientEph']['pub']);
      expect(hexOf(keys.c2s), session['c2s']);
      expect(hexOf(keys.s2c), session['s2c']);
    });

    test("the machine's welcome makes the session usable", () async {
      final client = await welcomedVectorClient();
      expect(client.ready, isTrue);
      expect(client.terminalP2pVersion, 1);
    });

    test('a welcome from any identity but the pinned one is refused', () async {
      final impostor = await vectorClient(
        peerPub: hexBytes(identities['client']['pub'] as String),
      );
      expect(await impostor.handleWelcome(welcomePayload()), isFalse);
      expect(impostor.ready, isFalse);
    });
  });

  group('envelopes', () {
    Map<String, dynamic> frameOf(String name, {bool withSession = true}) {
      final vector = envelopes[name] as Map<String, dynamic>;
      return {
        'type': vector['type'],
        if (withSession && vector['dbSessionId'] != null)
          'dbSessionId': vector['dbSessionId'],
        'payload': vector['wrapped'],
      };
    }

    Object? payloadOf(String name) => envelopes[name]['payload'];

    test('a down frame is sealed exactly as the CLI seals it', () async {
      final client = await welcomedVectorClient();
      final down = envelopes['down'] as Map<String, dynamic>;
      final sent = client.wrapOutgoing({
        'type': down['type'],
        'payload': down['payload'],
      });
      expect(sent['payload'], down['wrapped']);
    });

    test('a frame the relay may read is sent as it is', () async {
      final client = await welcomedVectorClient();
      final frame = <String, dynamic>{
        'type': 'machine_select',
        'payload': {'machineId': vectorMachineId},
      };
      expect(client.wrapOutgoing(frame), same(frame));
    });

    test('a pairwise reply opens once, and its replay is dropped', () async {
      final client = await welcomedVectorClient();
      final frame = frameOf('upPairwise');
      expect(client.unwrapIncoming(frame)?['payload'], payloadOf('upPairwise'));
      expect(client.unwrapIncoming(frame), isNull);
    });

    test('a group event opens only under its own session id', () async {
      final client = await welcomedVectorClient();
      final frame = frameOf('upGroup');
      expect(client.unwrapIncoming({...frame, 'dbSessionId': 'other'}), isNull);
      expect(client.unwrapIncoming(frame)?['payload'], payloadOf('upGroup'));
    });

    test('a rekey moves the group to its new epoch', () async {
      final client = await welcomedVectorClient();
      expect(
        client.handleRekey(session['rekey'] as Map<String, dynamic>),
        isTrue,
      );
      expect(
        client.unwrapIncoming(frameOf('upGroupAfterRekey'))?['payload'],
        payloadOf('upGroupAfterRekey'),
      );
      expect(client.unwrapIncoming(frameOf('upGroup')), isNull);
    });

    test('a frame that was never sealed passes as it is', () async {
      final client = await welcomedVectorClient();
      final frame = <String, dynamic>{
        'type': 'node_status',
        'payload': {'online': true},
      };
      expect(client.unwrapIncoming(frame), same(frame));
    });
  });
}
