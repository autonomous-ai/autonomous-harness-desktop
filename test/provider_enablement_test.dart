// `providers_config.json` — which providers this computer will offer.
//
// The rule the whole file turns on: **the set holds the DISABLED ids**, so an
// id it has never heard of is enabled. A fresh install with no file behaves
// like one where every switch was deliberately turned on, and a provider added
// on another machine does not arrive switched off.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:harness/grid/provider_enablement_store.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('providers_config_test');
    file = File('${dir.path}/providers_config.json');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  ProviderEnablementStore store() =>
      ProviderEnablementStore(file: file, gridSurface: true);

  test('with no file at all, every provider is enabled', () async {
    final s = store();
    await s.load();

    expect(file.existsSync(), isFalse, reason: 'reading writes nothing');
    expect(s.isEnabled('grid-anything'), isTrue);
    expect(s.disabledIds, isEmpty);
  });

  test('switching one off records only that one', () async {
    final s = store();
    await s.load();
    await s.setEnabled('grid-a', false);

    expect(s.isEnabled('grid-a'), isFalse);
    // The point of storing exceptions: a provider nobody has touched is on.
    expect(s.isEnabled('grid-b'), isTrue);

    final written = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(written['version'], ProviderEnablementStore.schemaVersion);
    expect(written['disabled'], ['grid-a']);
  });

  test('a saved set comes back on the next launch', () async {
    final first = store();
    await first.load();
    await first.setEnabled('grid-a', false);
    await first.setEnabled('grid-b', false);

    final second = store();
    await second.load();
    expect(second.disabledIds, {'grid-a', 'grid-b'});
    expect(second.isEnabled('grid-c'), isTrue);
  });

  test('switching one back on removes it rather than recording an On', () async {
    final s = store();
    await s.load();
    await s.setEnabled('grid-a', false);
    await s.setEnabled('grid-a', true);

    expect(s.disabledIds, isEmpty);
    expect(
      (jsonDecode(file.readAsStringSync()) as Map)['disabled'],
      isEmpty,
      reason: 'an enabled provider leaves no row behind',
    );
  });

  test('enableAll clears the file', () async {
    final s = store();
    await s.load();
    await s.setEnabled('grid-a', false);
    await s.setEnabled('grid-b', false);
    await s.enableAll();

    expect(s.disabledIds, isEmpty);
    expect(s.isEnabled('grid-a'), isTrue);
  });

  test('the notifier fires so a pane repaints on the click', () async {
    final s = store();
    await s.load();
    var fired = 0;
    s.addListener(() => fired++);

    await s.setEnabled('grid-a', false);
    expect(fired, 1);

    // A write that changes nothing is not a repaint.
    await s.setEnabled('grid-a', false);
    expect(fired, 1);
  });

  // An unreadable preferences file must not cost the user the providers they
  // can reach — the failure lands on "nothing disabled", the same as a fresh
  // install.
  test('a corrupt file reads as nothing disabled', () async {
    file.writeAsStringSync('{ this is not json');
    final s = store();
    await s.load();

    expect(s.disabledIds, isEmpty);
    expect(s.isEnabled('grid-a'), isTrue);
  });

  test('a file of the wrong shape reads the same way', () async {
    file.writeAsStringSync(jsonEncode({'version': 1, 'disabled': 'not a list'}));
    final s = store();
    await s.load();

    expect(s.disabledIds, isEmpty);
  });

  test('junk entries inside the list are dropped, not carried', () async {
    file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'disabled': ['grid-a', 42, '', null, 'grid-b'],
      }),
    );
    final s = store();
    await s.load();

    expect(s.disabledIds, {'grid-a', 'grid-b'});
  });

  // The same reason `GridSelectionStore.load` reads nothing with the surface
  // off: the file is shared with a debug build that CAN switch providers off,
  // and a release build would otherwise hide providers behind a screen it does
  // not draw.
  test('a build with the grid surface off reads nothing', () async {
    file.writeAsStringSync(
      jsonEncode({'version': 1, 'disabled': ['grid-a']}),
    );

    final s = ProviderEnablementStore(file: file, gridSurface: false);
    await s.load();

    expect(s.disabledIds, isEmpty);
    expect(s.isEnabled('grid-a'), isTrue);
    // And the other build's setting is left on disk, not cleared.
    expect(
      (jsonDecode(file.readAsStringSync()) as Map)['disabled'],
      ['grid-a'],
    );
  });
}
