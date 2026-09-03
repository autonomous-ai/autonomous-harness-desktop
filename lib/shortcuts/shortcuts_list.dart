import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import 'app_shortcuts.dart';

/// Every shortcut, grouped and printed — the body the ⌘/ sheet and the Settings
/// screen both draw.
///
/// One widget rather than a copy in each: the two would drift, and a shortcut
/// sheet that disagrees with the settings screen about what a key does is worse
/// than having only one of them. Rendered from [kAppShortcuts], so neither can
/// drift from what the keys actually do either.
class ShortcutsList extends StatelessWidget {
  const ShortcutsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in ShortcutGroup.values) ...[
          _GroupHeader(label: group.label),
          for (final shortcut in kAppShortcuts.where((s) => s.group == group))
            _Row(
              label: shortcut.label,
              keys: describeShortcut(shortcut.activator),
            ),
          if (group == ShortcutGroup.navigate)
            const _Row(
              label: 'Jump to the 1st–9th agent',
              keys: '⌘1 – ⌘$kAgentDigitCount',
            ),
        ],
        const SizedBox(height: 14),
        // The one thing users will otherwise file a bug about.
        const ShortcutsNote(),
      ],
    );
  }
}

/// Why the app takes so few keys — the sentence that turns "these shortcuts are
/// missing" into "those keys belong to the agent".
class ShortcutsNote extends StatelessWidget {
  const ShortcutsNote({super.key});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: grid.AppSurface.accentWash,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        'Everything else belongs to the agent. Ctrl keys, Esc, Tab and ⌥⏎ go '
        'straight to the terminal, so the engine and tmux keep the keys they '
        'already use.',
        style: TextStyle(
          color: grid.AppPalette.textSecondary,
          fontSize: 11.5,
          height: 1.5,
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: grid.AppPalette.textFaint,
          fontSize: 10.5,
          letterSpacing: 0.08 * 10.5,
          fontWeight: grid.AppFont.medium,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.keys});

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            keys,
            style: TextStyle(
              color: grid.AppPalette.textPrimary,
              fontSize: 12.5,
              // Tabular so the ⌘ column lines up down the list.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
