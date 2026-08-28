import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shortcuts/app_shortcuts.dart';

/// The ⌘/ sheet.
///
/// Rendered from [kAppShortcuts] rather than a hand-written list, so it cannot
/// drift from what the keys actually do.
Future<void> showShortcutsSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _ShortcutsSheet(),
  );
}

class _ShortcutsSheet extends StatelessWidget {
  const _ShortcutsSheet();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Dialog(
      backgroundColor: grid.AppGlass.surfaceFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: grid.AppGlass.hair),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 4),
              child: Text(
                'Keyboard shortcuts',
                style: TextStyle(
                  color: grid.AppPalette.textPrimary,
                  fontSize: 15,
                  fontWeight: grid.AppFont.semibold,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final group in ShortcutGroup.values) ...[
                      _GroupHeader(label: group.label),
                      for (final shortcut in kAppShortcuts.where(
                        (s) => s.group == group,
                      ))
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
                    _Note(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: grid.AppGlass.hair)),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
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
              // Tabular so the ⌘ column lines up down the sheet.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
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
