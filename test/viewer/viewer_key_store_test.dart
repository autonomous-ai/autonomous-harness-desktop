import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/viewer/viewer_key_store.dart';

import 'memory_key_value_store.dart';

void main() {
  test('mints the identity once, and every later store reads the same one', () async {
    final storage = MemoryKeyValueStore();
    final first = await ViewerKeyStore(storage: storage).identity();
    final again = await ViewerKeyStore(storage: storage).identity();
    expect(again.pub, first.pub);
  });

  test('pins, lists newest first, replaces a re-link, and unlinks', () async {
    final keys = ViewerKeyStore(storage: MemoryKeyValueStore());
    await keys.pin('machine-a', [1, 2, 3]);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await keys.pin('machine-b', [4, 5, 6]);
    expect((await keys.peers()).map((peer) => peer.machineId), ['machine-b', 'machine-a']);

    await keys.pin('machine-a', [7, 8, 9]);
    expect((await keys.peer('machine-a'))?.pub, [7, 8, 9]);
    expect(await keys.peers(), hasLength(2));

    expect(await keys.unlink('machine-a'), isTrue);
    expect(await keys.unlink('machine-a'), isFalse);
    expect(await keys.peer('machine-a'), isNull);
  });

  test('a damaged row loses that link, not every link', () async {
    final storage = MemoryKeyValueStore()
      ..values['viewer_e2ee_machine_peers'] = jsonEncode([
        {'machineId': 'broken'},
        {'machineId': 'machine-a', 'pub': 'AQID', 'label': '', 'linkedAt': 1},
      ]);
    final peers = await ViewerKeyStore(storage: storage).peers();
    expect(peers.map((peer) => peer.machineId), ['machine-a']);
  });

  test('an unreadable file reads as no links rather than failing', () async {
    final storage = MemoryKeyValueStore()..values['viewer_e2ee_machine_peers'] = '{not json';
    expect(await ViewerKeyStore(storage: storage).peers(), isEmpty);
  });
}
