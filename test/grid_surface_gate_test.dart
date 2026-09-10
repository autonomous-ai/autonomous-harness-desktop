// Grid is still being built, so a shipped build hides it: no Settings ▸ Grid, no Share
// Intelligence, no picker in the machine rail. The flag behind that is a compile-time const and a
// test run has it ON — which is the whole difficulty, since the shape worth guarding is the one no
// test build has. `settingsGroupsFor` takes both gates as arguments for exactly this.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:harness/grid/grid_session.dart';
import 'package:harness/grid/grid_surface.dart';
import 'package:harness/logging/debug_surface.dart';
import 'package:harness/settings/settings_section.dart';
import 'package:harness/shortcuts/app_shortcuts.dart';

void main() {
  List<SettingsSection> sectionsOf(List<SettingsGroup> groups) => [
    for (final group in groups) ...group.sections,
  ];

  test('a test build has Grid on, which is what every other test assumes', () {
    expect(kGridSurfaceEnabled, isTrue, reason: 'tests run in debug mode');
  });

  test('the shipped build lists neither Grid row', () {
    final shipped = settingsGroupsFor(debugSurface: false, gridSurface: false);
    expect(
      sectionsOf(shipped),
      isNot(
        anyOf(
          contains(SettingsSection.grid),
          contains(SettingsSection.shareIntelligence),
        ),
      ),
    );
    expect(
      shipped.map((group) => group.title),
      isNot(contains('Grid')),
      reason: 'an empty group would leave its caption over nothing',
    );
  });

  test('Settings opens on a row the rail actually shows', () {
    // The regression this closes: the default was `SettingsSection.grid` by name — the very row a
    // shipped build drops — so Settings would have opened on a pane with nothing lit beside it.
    expect(sectionsOf(settingsGroups), contains(kDefaultSettingsSection));
    final shipped = settingsGroupsFor(debugSurface: false, gridSurface: false);
    expect(shipped.first.sections.first, SettingsSection.appearance);
  });

  test('the two gates are independent', () {
    // Debug and Tracking are developer furniture; Grid is a feature in progress. A build may show
    // either set without the other, which is why they are two flags and not one.
    final gridOnly = sectionsOf(
      settingsGroupsFor(debugSurface: false, gridSurface: true),
    );
    expect(gridOnly, contains(SettingsSection.grid));
    expect(gridOnly, isNot(contains(SettingsSection.debug)));

    final debugOnly = sectionsOf(
      settingsGroupsFor(debugSurface: true, gridSurface: false),
    );
    expect(debugOnly, contains(SettingsSection.tracking));
    expect(debugOnly, isNot(contains(SettingsSection.shareIntelligence)));
    expect(kDebugSurfaceEnabled, isTrue, reason: 'tests run in debug mode');
  });

  test('everything outside the two gates is always listed', () {
    final shipped = sectionsOf(
      settingsGroupsFor(debugSurface: false, gridSurface: false),
    );
    expect(shipped, [
      SettingsSection.appearance,
      SettingsSection.terminal,
      // Usage carries no gate of its own: it reads only this machine's own
      // files, and it reads nothing at all until a provider is switched on, so
      // there is nothing here for a shipped build to hide.
      SettingsSection.usage,
      SettingsSection.devices,
      SettingsSection.shortcuts,
      SettingsSection.about,
    ]);
  });

  group('a shipped build has no door onto Grid', () {
    // Settings is the door everybody thinks of, and the tests above cover it.
    // These are the three that were open behind it.

    test('⇧⌘M is not bound where there is no picker to open', () {
      // The one door onto the model picker that is not a control the build
      // already hides. Bound unconditionally, it opened a panel listing every
      // provider on the account — and fetched them from the control plane to
      // do it — in a build whose own answer is that Grid is not finished.
      expect(
        kAppShortcuts.map((s) => s.action),
        isNot(contains(ShortcutAction.changeModel)),
        reason: 'it belongs to appShortcuts(), behind the gate',
      );
      expect(kChangeModelShortcut.action, ShortcutAction.changeModel);
      // A test build has Grid on, so the live list DOES carry it — which is
      // what the ⌘/ sheet and the bindings both read.
      expect(
        appShortcuts().map((s) => s.action),
        contains(ShortcutAction.changeModel),
      );
    });

    test('the ⌘/ sheet is drawn from the same gated list', () {
      // `shortcutRows()` derives from `appShortcuts()`, so moving the key
      // behind the gate takes its line out of the sheet with it — a build
      // cannot bind a key it does not document, or document one it cannot use.
      expect(
        shortcutRows().map((row) => row.label),
        contains(kChangeModelShortcut.label),
      );
    });

    test('a shipped build never mints a Grid session', () async {
      // ⚠️ `signIn` is called unprompted on every bootstrap, and each call that
      // gets through puts a fresh 365-day session on the person's Grid account
      // and revokes nothing. In a build with no Settings ▸ Grid that is a
      // credential its owner can neither see, explain, nor undo from inside
      // the app.
      final dir = await Directory.systemTemp.createTemp('grid-gate-');
      addTearDown(() => dir.delete(recursive: true));
      final store = GridSessionStore(
        file: File('${dir.path}/credentials.toml'),
        gridSurface: false,
      );

      // Refuses without reaching for the CLI at all — the runner here is the
      // real one, so anything else would shell out.
      expect(await store.signIn(), isNotNull);
      expect(store.signedIn, isFalse);
    });

    test('but reading one already on disk is left alone', () {
      // A session written by `grid login` in a terminal directs nothing on its
      // own, and nothing in a shipped build draws or spends it. Gating the read
      // as well would only make `grid logout` behave differently here.
      final store = GridSessionStore(
        file: File('/does/not/exist/credentials.toml'),
        gridSurface: false,
      );
      expect(store.loaded, isFalse);
      expect(() => store.load(), returnsNormally);
    });
  });
}
