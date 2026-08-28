import 'dart:typed_data';

const terminalLocalVersion = 1;
const terminalLocalHeaderBytes = 12;
const terminalLocalMaxPayloadBytes = 512 * 1024;

enum TerminalBinaryKind {
  input(1),
  output(2),
  keyframe(3),
  sync(4);

  final int code;
  const TerminalBinaryKind(this.code);

  static TerminalBinaryKind? fromCode(int code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

class TerminalBinaryFrame {
  final TerminalBinaryKind kind;
  final String streamId;
  final int seq;
  final Uint8List bytes;
  final bool compressed;
  final int? cols;
  final int? rows;

  const TerminalBinaryFrame({
    required this.kind,
    required this.streamId,
    required this.seq,
    required this.bytes,
    required this.compressed,
    this.cols,
    this.rows,
  });
}

final _localMagic = Uint8List.fromList(const [0x48, 0x54, 0x52, 0x4c]);
const _flagZlib = 1;

Uint8List? _uuidBytes(String id) {
  final hex = id.replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) return null;
  return Uint8List.fromList([
    for (var index = 0; index < 16; index++)
      int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
  ]);
}

String _uuidString(Uint8List bytes) {
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Uint8List? encodeTerminalPlain(TerminalBinaryFrame frame) {
  final id = _uuidBytes(frame.streamId);
  if (id == null || frame.seq < 0) return null;
  if ((frame.kind == TerminalBinaryKind.input ||
          frame.kind == TerminalBinaryKind.sync) &&
      frame.compressed) {
    return null;
  }
  if (frame.kind == TerminalBinaryKind.sync && frame.bytes.isNotEmpty) {
    return null;
  }
  final metaBytes = frame.kind == TerminalBinaryKind.keyframe ? 28 : 24;
  final output = Uint8List(metaBytes + frame.bytes.length)..setRange(0, 16, id);
  final view = ByteData.sublistView(output)
    ..setUint64(16, frame.seq, Endian.big);
  if (frame.kind == TerminalBinaryKind.keyframe) {
    final cols = frame.cols;
    final rows = frame.rows;
    if (cols == null ||
        rows == null ||
        cols < 1 ||
        cols > 0xffff ||
        rows < 1 ||
        rows > 0xffff) {
      return null;
    }
    view.setUint16(24, cols, Endian.big);
    view.setUint16(26, rows, Endian.big);
  }
  output.setRange(metaBytes, output.length, frame.bytes);
  return output;
}

TerminalBinaryFrame? decodeTerminalPlain(
  TerminalBinaryKind kind,
  int flags,
  Uint8List plaintext,
) {
  if ((flags & ~_flagZlib) != 0 ||
      ((kind == TerminalBinaryKind.input || kind == TerminalBinaryKind.sync) &&
          flags != 0)) {
    return null;
  }
  final metaBytes = kind == TerminalBinaryKind.keyframe ? 28 : 24;
  if (plaintext.length < metaBytes ||
      (kind == TerminalBinaryKind.sync && plaintext.length != metaBytes)) {
    return null;
  }
  final view = ByteData.sublistView(plaintext);
  return TerminalBinaryFrame(
    kind: kind,
    streamId: _uuidString(Uint8List.sublistView(plaintext, 0, 16)),
    seq: view.getUint64(16, Endian.big),
    bytes: Uint8List.fromList(plaintext.sublist(metaBytes)),
    compressed: (flags & _flagZlib) != 0,
    cols: kind == TerminalBinaryKind.keyframe
        ? view.getUint16(24, Endian.big)
        : null,
    rows: kind == TerminalBinaryKind.keyframe
        ? view.getUint16(26, Endian.big)
        : null,
  );
}

/// Plain terminal framing for the loopback CLI transport. The CLI now terminates E2EE itself for
/// every machine (own or relayed) — see the harness CLI's lib/remoteRelay.ts — so this is the only
/// wire format the app ever needs; there is no separate encrypted variant anymore.
Uint8List? encodeTerminalLocal(TerminalBinaryFrame frame) {
  final payload = encodeTerminalPlain(frame);
  if (payload == null || payload.length > terminalLocalMaxPayloadBytes) {
    return null;
  }
  final header = Uint8List(terminalLocalHeaderBytes)
    ..setRange(0, 4, _localMagic);
  header[4] = terminalLocalVersion;
  header[5] = frame.kind.code;
  header[6] = frame.compressed ? _flagZlib : 0;
  ByteData.sublistView(header).setUint32(8, payload.length, Endian.big);
  return Uint8List.fromList([...header, ...payload]);
}

TerminalBinaryFrame? decodeTerminalLocal(List<int> raw) {
  final bytes = Uint8List.fromList(raw);
  if (bytes.length < terminalLocalHeaderBytes) return null;
  for (var index = 0; index < _localMagic.length; index++) {
    if (bytes[index] != _localMagic[index]) return null;
  }
  final kind = TerminalBinaryKind.fromCode(bytes[5]);
  if (bytes[4] != terminalLocalVersion || kind == null || bytes[7] != 0) {
    return null;
  }
  final length = ByteData.sublistView(bytes).getUint32(8, Endian.big);
  if (length > terminalLocalMaxPayloadBytes ||
      bytes.length != terminalLocalHeaderBytes + length) {
    return null;
  }
  return decodeTerminalPlain(
    kind,
    bytes[6],
    Uint8List.fromList(bytes.sublist(terminalLocalHeaderBytes)),
  );
}
