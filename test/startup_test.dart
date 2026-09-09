import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/harness_file_store.dart';
import 'package:harness/core/startup.dart';
import 'package:harness/grid/grid_session.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/grid/model_picker_options.dart';
import 'package:harness/grid/model_recents_store.dart';
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
    // One instance for both edits, as the app has: a second store would not know about the family
    // the first one set, and would write the default back over it.
    final previousFont = TerminalFontStore(storage: previousRun);
    await previousFont.setFamily(TerminalFontChoice.menlo);
    await previousFont.setSize(17);
    await GridSelectionStore(storage: previousRun)
        .selectNetwork(networkId: 'grid-1', networkName: 'Office');
    await ModelRecentsStore(storage: previousRun).remember(
      const ModelChoice(
        networkId: 'grid-1',
        networkName: 'Office',
        model: 'GLM-4.7-Flash',
      ),
    );

    // The next launch: brand-new stores over the same directory, loaded the way main() loads them.
    final terminalFont = TerminalFontStore(
      storage: HarnessFileStore(directory: dir),
    );
    final gridSelection = GridSelectionStore(
      storage: HarnessFileStore(directory: dir),
    );
    final modelRecents = ModelRecentsStore(
      storage: HarnessFileStore(directory: dir),
    );
    await loadPersistedSettings(
      terminalFont: terminalFont,
      gridSelection: gridSelection,
      modelRecents: modelRecents,
    );

    expect(terminalFont.family, TerminalFontChoice.menlo);
    expect(terminalFont.size, 17.0);
    expect(gridSelection.value.networkId, 'grid-1');
    expect(gridSelection.value.label, 'Office');
    // The model picker's Recent section, which is drawn on the frame the panel
    // opens on — a load that landed later would push every provider's rows down
    // under a pointer already moving toward one.
    expect(modelRecents.value, const [
      ModelChoice(networkId: 'grid-1', model: 'GLM-4.7-Flash'),
    ]);
  });

  test('a first-ever launch lands on the defaults instead of throwing', () async {
    // Nothing written yet — the directory exists and holds no state file at all.
    final terminalFont = TerminalFontStore(
      storage: HarnessFileStore(directory: dir),
    );

    final gridSelection = GridSelectionStore(
      storage: HarnessFileStore(directory: dir),
    );
    // Pointed at the scratch dir like every other store here: the Grid session
    // lives in the CLI's own `~/.grid/credentials.toml`, and a test that took
    // the singleton would read the developer's real one.
    final gridSession = GridSessionStore(
      file: File('${dir.path}/credentials.toml'),
    );
    final modelRecents = ModelRecentsStore(
      storage: HarnessFileStore(directory: dir),
    );
    await loadPersistedSettings(
      terminalFont: terminalFont,
      gridSelection: gridSelection,
      gridSession: gridSession,
      modelRecents: modelRecents,
    );

    // Per platform since the Linux work — not a fixed face this repo picked.
    expect(terminalFont.family, TerminalFontChoice.defaultForPlatform);
    expect(gridSelection.value.hasGrid, isFalse);
    expect(gridSession.signedIn, isFalse);
    expect(modelRecents.value, isEmpty);
  });
}
