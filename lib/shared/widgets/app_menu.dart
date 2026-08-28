import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The floating-menu surface.
///
/// Lifted clear of BOTH grounds a menu can open over: the window and a raised
/// block (`AppGlass.surfaceFill`). The themed menu fill sits within 1.02:1 of
/// that block, which leaves the panel with no edge at all.
Color appMenuFill() => AppTheme.pick(Colors.white, const Color(0xFF2A2A2A));

/// A [MenuAnchor] surface that reads as *floating over* the page.
///
/// Three things together say "this is a layer above": a fill lifted clear of
/// both grounds, the hairline the app uses on other raised chrome, and a
/// deepened shadow. Pass it as `MenuAnchor.style`.
MenuStyle appMenuStyle() {
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(appMenuFill()),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(12),
    // Vertical breathing room only. Rows carry their own horizontal gutter so
    // their hover highlight reads as an inset pill; side padding here would
    // double it.
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 5)),
    maximumSize: const WidgetStatePropertyAll(
      Size.fromHeight(AppControl.menuMaxHeight),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppGlass.hair),
      ),
    ),
  );
}

/// One row in an [appMenuStyle] menu.
///
/// Hand-rolled rather than a [MenuItemButton] because the app has no
/// `menuButtonTheme`, so a bare one takes Material's M3 defaults and lands
/// wrong on four counts at once: radius 0, 14pt text, a grey 8% hover, and a
/// ripple every other menu here has turned off.
///
/// Stateful for its own hover: the glyph has to climb to [AppPalette.textPrimary]
/// under the pointer. An icon that stays dim while the cursor sits on it reads
/// as decoration, and nothing above this row tracks hover per-row to do it.
class AppMenuItem extends StatefulWidget {
  const AppMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Tints the row red and gives it a red hover wash — for the row that
  /// destroys something.
  final bool danger;

  @override
  State<AppMenuItem> createState() => _AppMenuItemState();
}

class _AppMenuItemState extends State<AppMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Lives in the MenuAnchor's overlay, so it watches for itself.
    AppTheme.watch(context);
    final error = Theme.of(context).colorScheme.error;
    // A danger row is already red at rest, so it deepens rather than climbs.
    final tint = widget.danger
        ? error
        : (_hovered ? AppPalette.textPrimary : AppPalette.textSecondary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (hovered) => setState(() => _hovered = hovered),
          borderRadius: BorderRadius.circular(8),
          hoverColor: widget.danger
              ? error.withValues(alpha: 0.09)
              : AppSurface.hoverFill,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Row(
              children: [
                // Fixed slot: these icons differ in width, and without it every
                // label would start at a slightly different column.
                SizedBox(
                  width: 16,
                  child: Icon(widget.icon, size: 16, color: tint),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.danger ? error : AppPalette.textPrimary,
                      fontFamily: AppFont.sans,
                      fontFamilyFallback: AppFont.sansFallback,
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: AppFont.medium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The rule that sets a destructive row apart from the ordinary ones.
class AppMenuDivider extends StatelessWidget {
  const AppMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Divider(height: 1, thickness: 1, color: AppPalette.divider),
    );
  }
}
