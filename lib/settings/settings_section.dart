import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One screen in Settings — a row in its rail, and the pane that row opens.
///
/// Declared once, like [ShortcutAction] in `shortcuts/app_shortcuts.dart`: the
/// rail, the search filter and the pane all read this list, so a section cannot
/// be listed without a screen behind it or reachable without a row.
enum SettingsSection {
  grid(LucideIcons.zap300, 'Grid'),
  appearance(LucideIcons.sun300, 'Appearance'),
  terminal(LucideIcons.terminal300, 'Terminal'),
  shortcuts(LucideIcons.keyboard300, 'Keyboard shortcuts'),
  about(LucideIcons.info300, 'About');

  const SettingsSection(this.icon, this.label);

  /// The rail glyph — Lucide's 300 weight, the one the machine rail's rows use,
  /// so the app's two nav columns draw at the same line weight.
  final IconData icon;
  final String label;
}

/// One labelled run of rows in the settings rail.
///
/// The grouping is presentation only — [kSettingsGroups] flattens back to every
/// section — but it says something true: the first run is what you *change*,
/// the second is what you *consult*.
class SettingsGroup {
  const SettingsGroup(this.title, this.sections);

  /// The caption over the run. A caption, not a sentence.
  final String title;
  final List<SettingsSection> sections;
}

/// What Settings lists, in order.
const kSettingsGroups = [
  // Which grids this account can talk to. First, and its own group, because it
  // is the only screen here that is about something outside this Mac.
  SettingsGroup('Grid', [SettingsSection.grid]),
  SettingsGroup('Preferences', [
    SettingsSection.appearance,
    SettingsSection.terminal,
  ]),
  SettingsGroup('Help', [SettingsSection.shortcuts, SettingsSection.about]),
];

/// The section Settings opens on — the first row of the first group, so the
/// screen never opens on a pane its rail doesn't show as selected.
const kDefaultSettingsSection = SettingsSection.grid;
