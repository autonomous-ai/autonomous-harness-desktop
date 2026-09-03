import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/harness_file_store.dart';
import 'package:harness/core/startup.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/shared/theme/theme_mode_store.dart';
import 'package:harness/terminal/terminal_font_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('harness-startup-');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('a relaunch restores every preference the first frame depends on', () async {
    // A previous run, writing through the real store rather than a fake: this is the one test that
    // covers the on-disk FORMAT as well as the logic, so a change to how values are serialized
    // cannot pass here while breaking real launches.
    final previousRun = HarnessFileStore(directory: dir);
    await ThemeModeStore(storage: previousRun).select(ThemeMode.dark);
    // One instance for both edits, as the app has: a second store would not know about the family
    // the first one set, and would write the default back over it.
    final previousFont = TerminalFontStore(storage: previousRun);
    await previousFont.setFamily(TerminalFontChoice.menlo);
    await previousFont.setSize(17);
    await GridSelectionStore(storage: previousRun)
        .selectNetwork(networkId: 'grid-1', networkName: 'Office');

    // The next launch: brand-new stores over the same directory, loaded the way main() loads them.
    final themeMode = ThemeModeStore(storage: HarnessFileStore(directory: dir));
    final terminalFont = TerminalFontStore(storage: HarnessFileStore(directory: dir));
    final gridSelection =
        GridSelectionStore(storage: HarnessFileStore(directory: dir));
    await loadPersistedSettings(
      themeMode: themeMode,
      terminalFont: terminalFont,
      gridSelection: gridSelection,
    );

    expect(themeMode.value, ThemeMode.dark);
    expect(terminalFont.family, TerminalFontChoice.menlo);
    expect(terminalFont.size, 17.0);
    expect(gridSelection.value.networkId, 'grid-1');
    expect(gridSelection.value.label, 'Office');
  });

  test('a first-ever launch lands on the defaults instead of throwing', () async {
    // Nothing written yet — the directory exists and holds no state file at all.
    final themeMode = ThemeModeStore(storage: HarnessFileStore(directory: dir));
    final terminalFont = TerminalFontStore(storage: HarnessFileStore(directory: dir));

    final gridSelection =
        GridSelectionStore(storage: HarnessFileStore(directory: dir));
    await loadPersistedSettings(
      themeMode: themeMode,
      terminalFont: terminalFont,
      gridSelection: gridSelection,
    );

    expect(themeMode.value, ThemeMode.system);
    expect(terminalFont.family, TerminalFontChoice.sfMono);
    expect(gridSelection.value.hasGrid, isFalse);
  });
}
