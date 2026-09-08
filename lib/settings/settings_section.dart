import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../logging/debug_surface.dart';

/// One screen in Settings — a row in its rail, and the pane that row opens.
///
/// Declared once, like [ShortcutAction] in `shortcuts/app_shortcuts.dart`: the
/// rail, the search filter and the pane all read this list, so a section cannot
/// be listed without a screen behind it or reachable without a row.
enum SettingsSection {
  grid(LucideIcons.zap300, 'Grid'),
  shareIntelligence(LucideIcons.share2300, 'Share Intelligence'),
  appearance(LucideIcons.sun300, 'Appearance'),
  terminal(LucideIcons.terminal300, 'Terminal'),
  shortcuts(LucideIcons.keyboard300, 'Keyboard shortcuts'),
  debug(LucideIcons.bug300, 'Debug'),
  about(LucideIcons.info300, 'About');

  const SettingsSection(this.icon, this.label);

  /// The rail glyph — Lucide's 300 weight, the one the machine rail's rows use,
  /// so the app's two nav columns draw at the same line weight.
  final IconData icon;
  final String label;
}

/// One labelled run of rows in the settings rail.
///
/// The grouping is presentation only — [settingsGroups] flattens back to every
/// section — but it says something true: the first run is what you *change*,
/// the second is what you *consult*.
class SettingsGroup {
  const SettingsGroup(this.title, this.sections);

  /// The caption over the run. A caption, not a sentence.
  final String title;
  final List<SettingsSection> sections;
}

/// What Settings lists, in order.
///
/// A getter rather than a `const`, for the one row that is not always there:
/// [SettingsSection.debug] is developer furniture and ships only where
/// [kDebugSurfaceEnabled] says so. Everything that draws or searches the rail
/// reads this, so a hidden section cannot be reached by a stale copy of the
/// list — while the enum value itself always exists, so the screen behind it
/// needs no gate of its own.
List<SettingsGroup> get settingsGroups => [
  for (final group in _kSettingsGroups)
    if (group.sections.any(_isVisible))
      SettingsGroup(group.title, [
        for (final section in group.sections)
          if (_isVisible(section)) section,
      ]),
];

bool _isVisible(SettingsSection section) =>
    section != SettingsSection.debug || kDebugSurfaceEnabled;

const _kSettingsGroups = [
  // The two directions of the same relationship, and the only run here about
  // something outside this Mac: which grids this account can talk to, and what
  // this computer gives back to the one that is picked.
  SettingsGroup('Grid', [
    SettingsSection.grid,
    SettingsSection.shareIntelligence,
  ]),
  SettingsGroup('Preferences', [
    SettingsSection.appearance,
    SettingsSection.terminal,
  ]),
  // Debug sits between the two things it is most often reached from: the keys
  // that open it, and the version a report has to name.
  SettingsGroup('Help', [
    SettingsSection.shortcuts,
    SettingsSection.debug,
    SettingsSection.about,
  ]),
];

/// The section Settings opens on — the first row of the first group, so the
/// screen never opens on a pane its rail doesn't show as selected.
const kDefaultSettingsSection = SettingsSection.grid;
