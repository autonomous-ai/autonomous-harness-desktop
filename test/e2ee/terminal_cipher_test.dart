import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/e2ee/bytes.dart';
import 'package:harness/e2ee/terminal_cipher.dart';
import 'package:harness/terminal/terminal_binary.dart';

import 'vectors.dart';

void main() {
  final session = section('session');
  final frames = (e2eeVectors['terminalFrames'] as List)
      .cast<Map<String, dynamic>>();

  Uint8List keyFor(Map<String, dynamic> vector) => hexBytes(
    session[vector['dir'] == 'c2s' ? 'terminalC2s' : 'terminalS2c'] as String,
  );

  TerminalBinaryFrame frameOf(Map<String, dynamic> vector) =>
      TerminalBinaryFrame(
        kind: TerminalBinaryKind.fromCode(vector['kind'] as int)!,
        streamId: vector['streamId'] as String,
        seq: vector['seq'] as int,
        bytes: hexBytes(vector['bytes'] as String),
        compressed: vector['compressed'] as bool,
        cols: vector['cols'] as int?,
        rows: vector['rows'] as int?,
      );

  test('binary keys derive from the session keys as the CLI derives them', () {
    expect(
      hexOf(deriveTerminalBinaryKey(hexBytes(session['c2s'] as String))),
      session['terminalC2s'],
    );
    expect(
      hexOf(deriveTerminalBinaryKey(hexBytes(session['s2c'] as String))),
      session['terminalS2c'],
    );
  });

  for (final vector in frames) {
    final label =
        'kind ${vector['kind']} (${vector['dir']}, counter ${vector['counter']})';

    test('$label seals byte-for-byte as the CLI does', () {
      final sealed = sealTerminalBinary(
        keyFor(vector),
        vector['counter'] as int,
        frameOf(vector),
      );
      expect(hexOf(sealed!), vector['sealed']);
    });

    test('$label opens to the frame the loopback transport carries', () {
      final opened = openTerminalBinary(
        keyFor(vector),
        hexBytes(vector['sealed'] as String),
      );
      expect(opened?.counter, vector['counter']);
      expect(hexOf(encodeTerminalLocal(opened!.frame)!), vector['local']);
    });
  }

  test('a flipped ciphertext byte does not open', () {
    final vector = frames.first;
    final tampered = hexBytes(vector['sealed'] as String);
    tampered[tampered.length - 1] ^= 1;
    expect(openTerminalBinary(keyFor(vector), tampered), isNull);
  });

  test('a session seals in counter order and drops a replayed frame', () async {
    final client = await welcomedVectorClient();
    for (final vector in frames.where((v) => v['dir'] == 'c2s')) {
      expect(hexOf(client.encryptTerminal(frameOf(vector))!), vector['sealed']);
    }
    final fromMachine = hexBytes(
      frames.firstWhere((v) => v['dir'] == 's2c')['sealed'] as String,
    );
    expect(client.decryptTerminal(fromMachine), isNotNull);
    expect(client.decryptTerminal(fromMachine), isNull);
  });
}
