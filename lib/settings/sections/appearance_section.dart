import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart' as grid;
import '../../shared/theme/theme_mode_store.dart';
import '../../shared/widgets/section_heading.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../appearance/theme_preview_tile.dart';
import '../appearance/typography_section.dart';

/// Settings ▸ Appearance: how the app looks on this Mac.
///
/// ⚠️ The APP, not the terminal. Everything on this screen stops at the edge of
/// a terminal pane: the pane renders a grid a remote program is drawing into, so
/// it carries its own face and size in Settings ▸ Terminal, and the UI scale is
/// held out of it at five separate seams — see `terminal_panel.dart`,
/// `terminal_composer.dart`, `engine_identity.dart` and `terminal_section.dart`,
/// with `test/terminal_ui_scale_isolation_test.dart` standing guard.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return SectionScaffold(
      title: 'Appearance',
      subtitle:
          'How Harness looks on this Mac. System follows your macOS setting, '
          'and the native menus and title bar follow it too.',
      // ⚠️ A SingleChildScrollView, never a ListView. A lazy list keeps the
      // children it has already built across a rebuild, which is the exact
      // mechanism that strands a widget on the palette it first mounted with —
      // and this is the one screen where the user flips the palette on purpose.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _ThemeChoice(),
            SizedBox(height: 26),
            TypographySection(),
            // Room under the last card so a scrolled-to-bottom pane does not end
            // flush against the window edge.
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Light / Dark / System, offered as three miniatures of the app.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice();

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    // Resolved once here rather than inside each tile: `AppTheme.as` restores
    // the global brightness before the tiles build, so a tile that read tokens
    // in its own `build` would paint the palette the app is already wearing.
    final light = ThemeSwatches.of(Brightness.light);
    final dark = ThemeSwatches.of(Brightness.dark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Theme'),
        const SizedBox(height: 12),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeStore,
          builder: (context, mode, _) => Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              ThemePreviewTile(
                label: 'System',
                selected: mode == ThemeMode.system,
                onTap: () => unawaited(themeModeStore.select(ThemeMode.system)),
                swatches: light,
                // Both halves, cut down the middle — because that is precisely
                // what choosing System means.
                trailingSwatches: dark,
              ),
              ThemePreviewTile(
                label: 'Light',
                selected: mode == ThemeMode.light,
                onTap: () => unawaited(themeModeStore.select(ThemeMode.light)),
                swatches: light,
              ),
              ThemePreviewTile(
                label: 'Dark',
                selected: mode == ThemeMode.dark,
                onTap: () => unawaited(themeModeStore.select(ThemeMode.dark)),
                swatches: dark,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
