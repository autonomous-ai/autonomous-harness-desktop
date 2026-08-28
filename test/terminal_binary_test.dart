import 'dart:convert';
import 'dart:typed_data';

import 'package:harness/terminal/terminal_binary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const streamId = '00112233-4455-6677-8899-aabbccddeeff';

  test('accepts only empty uncompressed sync frames', () {
    expect(
      encodeTerminalPlain(
        TerminalBinaryFrame(
          kind: TerminalBinaryKind.sync,
          streamId: streamId,
          seq: 10,
          bytes: Uint8List.fromList(const [1]),
          compressed: false,
        ),
      ),
      isNull,
    );
  });

  test('local HTRL framing matches the Harness CLI golden frame', () {
    final encoded = encodeTerminalLocal(
      TerminalBinaryFrame(
        kind: TerminalBinaryKind.input,
        streamId: streamId,
        seq: 3,
        bytes: Uint8List.fromList(utf8.encode('xin chào\r')),
        compressed: false,
      ),
    )!;
    expect(
      encoded.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      '4854524c0101000000000022'
      '00112233445566778899aabbccddeeff'
      '0000000000000003'
      '78696e206368c3a06f0d',
    );
    final decoded = decodeTerminalLocal(encoded);
    expect(decoded?.streamId, streamId);
    expect(decoded?.seq, 3);
    expect(utf8.decode(decoded!.bytes), 'xin chào\r');
  });

  test('local HTRL framing rejects truncation and reserved bytes', () {
    final encoded = encodeTerminalLocal(
      TerminalBinaryFrame(
        kind: TerminalBinaryKind.sync,
        streamId: streamId,
        seq: 4,
        bytes: Uint8List(0),
        compressed: false,
      ),
    )!;
    expect(decodeTerminalLocal(encoded.sublist(0, encoded.length - 1)), isNull);
    final invalid = Uint8List.fromList(encoded)..[7] = 1;
    expect(decodeTerminalLocal(invalid), isNull);
  });
}
