// The theme tiles, tested where their callback is INJECTED.
//
// Never through `themeModeStore`: that singleton persists through the real
// `HarnessFileStore` — the developer's own `~/.harness/desktop-app/state.json` —
// which is why `settings_screen_test.dart` says at the top that it never calls a
// mutating method on it either.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/settings/appearance/theme_preview_tile.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: grid.buildAppTheme(brightness: brightness),
      themeAnimationDuration: Duration.zero,
      home: Builder(
        builder: (context) {
          // What `_GridTokenScope` does in the real app: publish the brightness
          // the tokens resolve against.
          grid.AppTheme.brightness.value = Theme.of(context).brightness;
          return grid.BrightnessScope(
            child: Scaffold(body: Center(child: child)),
          );
        },
      ),
    );

void main() {
  tearDown(() => grid.AppTheme.brightness.value = Brightness.light);

  testWidgets('a tile advertises the palette it names, not the one worn', (
    tester,
  ) async {
    // The whole reason `AppTheme.as` exists: while the app is LIGHT, the dark
    // tile still has to look dark. A tile that read tokens in its own `build`
    // would paint three identical light miniatures.
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThemePreviewTile(
              label: 'Light',
              selected: true,
              onTap: () {},
              swatches: ThemeSwatches.of(Brightness.light),
            ),
            ThemePreviewTile(
              label: 'Dark',
              selected: false,
              onTap: () {},
              swatches: ThemeSwatches.of(Brightness.dark),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final light = ThemeSwatches.of(Brightness.light);
    final dark = ThemeSwatches.of(Brightness.dark);
    expect(light.windowBg, isNot(dark.windowBg));
    expect(light.panelBg, isNot(dark.panelBg));
    // …and reading them did not leave the global anywhere but where it started.
    expect(grid.AppTheme.brightness.value, Brightness.light);
  });

  testWidgets('reading a palette does not disturb the one in use', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const SizedBox(), brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    expect(grid.AppTheme.brightness.value, Brightness.dark);

    // The swap is muted and restored in a `finally`, so a preview costs nothing
    // and leaves nothing behind.
    ThemeSwatches.of(Brightness.light);
    expect(grid.AppTheme.brightness.value, Brightness.dark);
  });

  testWidgets('System draws BOTH palettes, because that is what it means', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ThemePreviewTile(
          label: 'System',
          selected: true,
          onTap: () {},
          swatches: ThemeSwatches.of(Brightness.light),
          trailingSwatches: ThemeSwatches.of(Brightness.dark),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Two miniatures inside one tile; a single-palette tile has one.
    expect(
      find.descendant(
        of: find.byType(ThemePreviewTile),
        matching: find.byType(OverflowBox),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('tapping reports the choice', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        ThemePreviewTile(
          label: 'Dark',
          selected: false,
          onTap: () => taps++,
          swatches: ThemeSwatches.of(Brightness.dark),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ThemePreviewTile));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('the selection ring is drawn OUTSIDE the artwork', (
    tester,
  ) async {
    // A rim laid over the miniature would tint the very colours the tile exists
    // to show, so the box grows a thicker border and gives up padding instead —
    // which means the tile's outer size never moves between states.
    Size sizeOf(bool selected) => tester.getSize(find.byType(ThemePreviewTile));

    await tester.pumpWidget(
      _host(
        ThemePreviewTile(
          label: 'Dark',
          selected: false,
          onTap: () {},
          swatches: ThemeSwatches.of(Brightness.dark),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final resting = sizeOf(false);

    await tester.pumpWidget(
      _host(
        ThemePreviewTile(
          label: 'Dark',
          selected: true,
          onTap: () {},
          swatches: ThemeSwatches.of(Brightness.dark),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      sizeOf(true),
      resting,
      reason: 'selecting a tile must not resize it, or the row of three shifts',
    );
  });
}
