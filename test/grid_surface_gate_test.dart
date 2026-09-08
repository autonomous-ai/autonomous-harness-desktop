// Grid is still being built, so a shipped build hides it: no Settings ▸ Grid, no Share
// Intelligence, no picker in the machine rail. The flag behind that is a compile-time const and a
// test run has it ON — which is the whole difficulty, since the shape worth guarding is the one no
// test build has. `settingsGroupsFor` takes both gates as arguments for exactly this.
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/grid/grid_surface.dart';
import 'package:harness/logging/debug_surface.dart';
import 'package:harness/settings/settings_section.dart';

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
}
