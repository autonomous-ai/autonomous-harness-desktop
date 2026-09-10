import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/e2ee/bytes.dart';
import 'package:harness/e2ee/cpace.dart';
import 'package:harness/e2ee/password_pake.dart';
import 'package:harness/e2ee/primitives.dart';
import 'package:harness/e2ee/ristretto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'vectors.dart';

void main() {
  final link = section('passwordLink');
  final sid = hexBytes(link['sid'] as String);
  final ci = link['ci'] as String;
  final stretched = hexBytes(link['stretched'] as String);

  test('the password folds to NFKC as the CLI folds it', () {
    expect(unorm.nfkc(link['password'] as String), link['passwordNfkc']);
  });

  test(
    "NFKC + scrypt stretch it to the CLI's key",
    () async {
      final key = await stretchPassword(
        link['password'] as String,
        vectorMachineId,
      );
      expect(hexOf(key), link['stretched']);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('the channel binding names the joiner a machine', () {
    expect(pwContext(vectorMachineId), ci);
  });

  group('CPace over the stretched password', () {
    late RistrettoPoint generator;
    late CpaceStart machine;
    late CpaceStart joiner;
    late Uint8List isk;
    late Uint8List transcript;

    setUpAll(() {
      generator = pwCpaceGenerator(stretched, sid, ci);
      machine = cpaceStart(generator, seeded(1));
      joiner = cpaceStart(generator, seeded(2));
      final shared = cpaceShared(machine.share, joiner.scalar);
      isk = cpaceIsk(sid, shared, machine.share, joiner.share);
      transcript = transcriptHash(sid, ci, machine.share, joiner.share);
    });

    test("hashes to the CLI's generator and shares", () {
      expect(hexOf(generator.toBytes()), link['generator']);
      expect(hexOf(machine.share), link['ya']);
      expect(hexOf(joiner.share), link['yb']);
    });

    test('both ends derive one secret, ISK and transcript', () {
      expect(hexOf(cpaceShared(machine.share, joiner.scalar)), link['shared']);
      expect(hexOf(cpaceShared(joiner.share, machine.scalar)), link['shared']);
      expect(hexOf(isk), link['isk']);
      expect(hexOf(transcript), link['transcript']);
    });

    test('both confirmation MACs match', () {
      final kc = kcKeys(isk, ci);
      expect(hexOf(macTag(kc.web, transcript)), link['round2Mac']);
      expect(
        macVerify(kc.adapter, transcript, hexBytes(link['round3Mac'] as String)),
        isTrue,
      );
    });

    test("the machine's identity opens, bound to this transcript", () async {
      final opened = aeadOpen(
        pairKey(isk, ci),
        3,
        utf8Bytes('e2e-id'),
        b64d(link['round3Enc'] as String),
      );
      final envelope = jsonDecode(utf8.decode(opened!)) as Map<String, dynamic>;
      final adapter = await vectorIdentity('adapter');
      expect(b64d(envelope['id'] as String), adapter.pub);
      expect(
        await pairBindVerify(
          adapter.pub,
          transcript,
          b64d(envelope['sig'] as String),
        ),
        isTrue,
      );
    });

    test("this app's identity is sealed as the CLI joiner seals it", () async {
      final client = await vectorIdentity('client');
      final sealed = aeadSeal(
        pairKey(isk, ci),
        4,
        utf8Bytes('e2e-id'),
        utf8Bytes(
          jsonEncode({
            'id': b64e(client.pub),
            'sig': b64e(await pairBindSig(client, transcript)),
          }),
        ),
      );
      expect(b64e(sealed), link['round4Enc']);
    });

    test('a wrong password fails the confirmation', () {
      final wrong = cpaceStart(
        pwCpaceGenerator(sha256(utf8Bytes('wrong')), sid, ci),
        seeded(2),
      );
      final th = transcriptHash(sid, ci, machine.share, wrong.share);
      final joinerIsk = cpaceIsk(
        sid,
        cpaceShared(machine.share, wrong.scalar),
        machine.share,
        wrong.share,
      );
      final machineIsk = cpaceIsk(
        sid,
        cpaceShared(wrong.share, machine.scalar),
        machine.share,
        wrong.share,
      );
      final joinerMac = macTag(kcKeys(joinerIsk, ci).web, th);
      expect(macVerify(kcKeys(machineIsk, ci).web, th, joinerMac), isFalse);
    });
  });

  test('the 6-character-code vector core.test.ts pins still holds', () {
    final code = section('cpaceCode');
    const dsi = 'e2e-cpace-ristretto255-v1';
    final codeSid = hexBytes(code['sid'] as String);
    final generator = hashToRistretto255(
      lvCat([dsi, code['code'] as String, codeSid, code['ci'] as String]),
      utf8Bytes(dsi),
    );
    final a = cpaceStart(generator, seeded(1));
    final b = cpaceStart(generator, seeded(2));
    expect(hexOf(generator.toBytes()), code['generator']);
    expect(a.scalar.toRadixString(16), code['yScalarA']);
    expect(
      hexOf(cpaceIsk(codeSid, cpaceShared(b.share, a.scalar), a.share, b.share)),
      code['isk'],
    );
    // The literal core.test.ts pins, so the two files cannot drift apart unnoticed.
    expect(code['isk'], startsWith('33fe6d15608411dec3174c7acba71622'));
  });
}
