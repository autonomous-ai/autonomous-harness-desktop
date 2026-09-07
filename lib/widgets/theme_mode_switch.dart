import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/theme/theme_mode_store.dart';

/// System / Light / Dark, as one compact segmented control.
///
/// It sits on the sign-in screen because the theme is the one setting that
/// means anything before there is a session — see [ThemeModeStore], which is a
/// `ValueNotifier` living above every provider scope for exactly that reason.
/// Settings ▸ Appearance offers the same three choices as full miniatures of
/// the app; this is the same store, at the size a corner can carry.
///
/// **Built to §8.8 rather than from `SegmentedButton`.** Material's control
/// draws a bordered, stadium-cornered pill with a ripple — three separate
/// breaks with the house style in one widget. The geometry below is the one the
/// design system specifies:
///
/// ```
/// track:  AppSurface.recess,   radius 8, height 32 (AppControl.height)
/// chip:   AppGlass.surfaceFill + cardShadow, radius 6, height 32 - 4
/// ```
///
/// The chip is a *fill plus a shadow*, never a translucent tint: on the light
/// palette a washed chip lands about 1.037:1 against its own track, which is
/// invisible. The shadow is what makes the selection readable there.
class ThemeModeSwitch extends StatelessWidget {
  const ThemeModeSwitch({super.key});

  static const double _trackHeight = grid.AppControl.height;
  static const double _chipHeight = grid.AppControl.height - 4;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeStore,
      builder: (context, mode, _) => Container(
        height: _trackHeight,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: grid.AppSurface.recess,
          borderRadius: BorderRadius.circular(grid.AppControl.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in _options)
              _Segment(
                option: option,
                selected: mode == option.mode,
                onTap: () => themeModeStore.select(option.mode),
              ),
          ],
        ),
      ),
    );
  }

  /// System first, and that order is the argument: it is the default, and it is
  /// the only value that can be right without asking — the person already told
  /// their computer which they wanted.
  static const _options = <_Option>[
    _Option(ThemeMode.system, Icons.computer_outlined, 'Match macOS'),
    _Option(ThemeMode.light, Icons.light_mode_outlined, 'Light'),
    _Option(ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
  ];
}

class _Option {
  const _Option(this.mode, this.icon, this.label);
  final ThemeMode mode;
  final IconData icon;
  final String label;
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _Option option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final selected = widget.selected;
    // The climb IS the affordance, the same way `AppIconButton` spells it:
    // secondary at rest, primary once chosen or under the pointer.
    final ink = selected || _hovered
        ? grid.AppPalette.textPrimary
        : grid.AppPalette.textSecondary;

    return Tooltip(
      message: widget.option.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: grid.AppMotion.hover,
            curve: grid.AppMotion.curve,
            width: 34,
            height: ThemeModeSwitch._chipHeight,
            decoration: BoxDecoration(
              // Fill + shadow, never a tint — see the class note.
              color: selected ? grid.AppGlass.surfaceFill : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              boxShadow: selected ? grid.AppGlass.cardShadow : null,
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.option.icon,
              size: grid.AppControl.iconSizeChip,
              color: ink,
              // The label is already on the tooltip; the glyph alone would be a
              // guess for a screen reader.
              semanticLabel: widget.option.label,
            ),
          ),
        ),
      ),
    );
  }
}
