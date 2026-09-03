import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/theme_mode_store.dart';
import '../../shared/widgets/section_scaffold.dart';

/// Settings ▸ Appearance: the palette the app wears.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  static const _labels = <ThemeMode, String>{
    ThemeMode.system: 'System',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SectionScaffold(
      title: 'Appearance',
      subtitle:
          'How Harness looks on this Mac. System follows your macOS setting, '
          'and the native menus and title bar follow it too.',
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingLabel('Theme'),
              const SizedBox(height: 8),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeModeStore,
                builder: (context, mode, _) => SegmentedChoice<ThemeMode>(
                  segments: _labels,
                  value: mode,
                  onChanged: (next) => unawaited(themeModeStore.select(next)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "THEME" — the caption over one control in a settings pane.
///
/// The same uppercase, letter-spaced micro-type `shortcuts_list.dart` uses for
/// its group headers, so a labelled run of controls reads the same wherever it
/// appears.
class SettingLabel extends StatelessWidget {
  const SettingLabel(this.label, {super.key});

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

/// A small, app-themed stand-in for a native macOS segmented control — used for
/// Appearance, and shaped to be reused by any setting that picks one of a
/// handful of named options.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
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
              fontWeight: selected
                  ? grid.AppFont.semibold
                  : grid.AppFont.regular,
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
