import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/theme/theme_mode_store.dart';
import '../terminal/terminal_font_store.dart';

/// The app's general Settings surface — a stack of independent sections, each owning one feature
/// area's controls. Font was the first thing this dialog held; Appearance moved in from its own
/// account-menu submenu as the second. Adding another setting later means adding another section,
/// not restructuring this dialog.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return AlertDialog(
      title: const Text('Settings'),
      content: const SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Appearance'),
            SizedBox(height: 8),
            _AppearanceSection(),
            SizedBox(height: 18),
            Divider(height: 1),
            SizedBox(height: 14),
            _SectionHeader('Terminal font'),
            SizedBox(height: 8),
            _TerminalFontSection(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(fontSize: 13.5)),
        ),
      ],
    );
  }
}

/// "APPEARANCE" — the same uppercase, letter-spaced treatment `shortcuts_sheet.dart`'s
/// `_GroupHeader` already established for "a labelled group of related controls" in this app.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: grid.AppPalette.textFaint,
        fontSize: 10.5,
        letterSpacing: 0.08 * 10.5,
        fontWeight: grid.AppFont.medium,
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  static const _labels = <ThemeMode, String>{
    ThemeMode.system: 'System',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeStore,
      builder: (context, mode, _) => _SegmentedControl<ThemeMode>(
        segments: _labels,
        value: mode,
        onChanged: (next) => unawaited(themeModeStore.select(next)),
      ),
    );
  }
}

class _TerminalFontSection extends StatelessWidget {
  const _TerminalFontSection();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<TerminalStyle>(
      valueListenable: terminalFontStore,
      builder: (context, style, _) {
        final family = terminalFontStore.family;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 44,
                  child: Text('Font', style: TextStyle(fontSize: 13.5)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<TerminalFontChoice>(
                    key: const Key('terminal-font-family-dropdown'),
                    isExpanded: true,
                    value: family,
                    items: [
                      for (final choice in TerminalFontChoice.values)
                        DropdownMenuItem(
                          value: choice,
                          child: Text(
                            choice.label,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                    ],
                    onChanged: (choice) {
                      if (choice != null) {
                        unawaited(terminalFontStore.setFamily(choice));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 44,
                  child: Text('Size', style: TextStyle(fontSize: 13.5)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('terminal-font-size-decrease'),
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: () => unawaited(terminalFontStore.decreaseSize()),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${style.fontSize.round()}pt',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                IconButton(
                  key: const Key('terminal-font-size-increase'),
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => unawaited(terminalFontStore.increaseSize()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // A live sample rendered with the exact style about to go into the terminal — if a
            // pick were ever going to misalign, it would show right here before it reaches any
            // remote TUI.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: grid.AppPalette.windowBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: grid.AppGlass.hair),
              ),
              child: Text(
                '┌─ mmmmmmmmmm ─┐\nagent@harness ❯ _',
                style: style.toTextStyle(color: grid.AppPalette.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('terminal-settings-reset-button'),
                onPressed: () => unawaited(terminalFontStore.reset()),
                child: const Text(
                  'Reset to default',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A small, app-themed stand-in for a native macOS segmented control — used here for Appearance,
/// and shaped to be reused by any future setting that picks one of a handful of named options.
class _SegmentedControl<T> extends StatelessWidget {
  const _SegmentedControl({
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: grid.AppPalette.windowBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: grid.AppGlass.hair),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [
            for (final entry in segments.entries)
              Expanded(
                child: _Segment(
                  label: entry.value,
                  selected: entry.key == value,
                  onTap: () => onChanged(entry.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Material(
      color: selected ? grid.AppPalette.accentOnSurface : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? grid.AppFont.semibold : grid.AppFont.regular,
              color: selected
                  ? grid.AppPalette.windowBg
                  : grid.AppPalette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
