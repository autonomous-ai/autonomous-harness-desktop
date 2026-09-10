// [GridHero] is the headline card that used to sit above Settings ▸ Providers —
// "NEW AGENTS USE", the chosen grid's name, its three facts and its actions.
//
// ⚠️ **Nothing in the app builds it any more.** The pane is now a split
// (`settings/sections/provider_split_pane.dart`) whose detail panel IS the
// headline, so the card's own facts were being drawn twice. The widget is kept
// rather than deleted so the design can be brought back without being rewritten
// from the commit log, and these tests are what keep it from rotting silently:
// they build it directly, which is the only way left to reach it.
//
// What they no longer cover, because there is no pane holding it: that picking
// a grid does not move the list. That invariant moved to the split, where the
// rail is what must not reflow — see `grid_networks_test.dart`.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/settings/sections/grid_hero.dart';
import 'package:harness/shared/theme/app_theme.dart';

import 'support/fake_grid_api.dart';

/// Composite an ARGB overlay onto an opaque ground, the way the framework does.
Color _over(Color base, Color layer) {
  final a = layer.a;
  return Color.from(
    alpha: 1,
    red: layer.r * a + base.r * (1 - a),
    green: layer.g * a + base.g * (1 - a),
    blue: layer.b * a + base.b * (1 - a),
  );
}

/// WCAG relative luminance, and the contrast ratio built from it.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// The two grids the shared fixture describes: one this account owns, one it
/// does not. Read from the fixture rather than hand-built, so a change to the
/// wire shape reaches this file too.
GridNetwork _network(int index) =>
    GridMe.fromJson(kGridMePayload).networks[index];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester, {
    required GridSelection chosen,
    GridNetwork? network,
    bool owned = false,
    VoidCallback? onShare,
    VoidCallback? onRename,
    VoidCallback? onDelete,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            AppTheme.brightness.value = Brightness.light;
            return BrightnessScope(
              child: Scaffold(
                body: GridHero(
                  chosen: chosen,
                  network: network,
                  owned: owned,
                  onShare: onShare,
                  onRename: onRename,
                  onDelete: onDelete,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Grid names differ wildly in length, and the headline prints one at 23px. If
  // the block is not a fixed height, switching between a short name and a long
  // one reflows everything under it — which is the whole reason the card
  // reserves a minimum height rather than hugging its contents.
  group('nothing moves when the name changes', () {
    testWidgets('the headline is the same height whatever the name', (
      tester,
    ) async {
      await pump(
        tester,
        chosen: const GridSelection(networkId: 'a', networkName: 'x'),
        network: _network(0),
        owned: true,
      );
      final short = tester.getRect(find.byType(GridHero)).height;

      await pump(
        tester,
        chosen: const GridSelection(
          networkId: 'b',
          networkName: 'a considerably longer grid name than the other one',
        ),
        network: _network(1),
      );
      expect(
        tester.getRect(find.byType(GridHero)).height,
        short,
        reason: 'the block reserves its height rather than hugging the name',
      );
    });

    testWidgets('owning the grid or not does not change its height', (
      tester,
    ) async {
      await pump(
        tester,
        chosen: const GridSelection(networkId: 'a', networkName: 'hp-1-1'),
        network: _network(0),
        owned: true,
        onRename: () {},
        onDelete: () {},
      );
      final owned = tester.getRect(find.byType(GridHero)).height;

      await pump(
        tester,
        chosen: const GridSelection(networkId: 'b', networkName: 'Water Grid'),
        network: _network(1),
      );
      expect(
        tester.getRect(find.byType(GridHero)).height,
        owned,
        reason: 'the actions row must not be what sets the height',
      );
    });

    // The empty state is the third shape the same box has to hold.
    testWidgets('and it is the same height with nothing picked', (
      tester,
    ) async {
      await pump(
        tester,
        chosen: const GridSelection(networkId: 'a', networkName: 'hp-1-1'),
        network: _network(0),
        owned: true,
      );
      final chosen = tester.getRect(find.byType(GridHero)).height;

      await pump(tester, chosen: GridSelection.none);
      expect(tester.getRect(find.byType(GridHero)).height, chosen);
    });
  });

  testWidgets('with no grid picked the headline says so and offers nothing', (
    tester,
  ) async {
    await pump(tester, chosen: GridSelection.none);

    expect(find.text('Each engine’s own account'), findsOneWidget);
    expect(find.byKey(const Key('grid-hero-rename')), findsNothing);
    expect(find.byKey(const Key('grid-hero-delete')), findsNothing);
    // The card does NOT repeat the words the picker uses for this state: the
    // same two words twice on one screen is how a reader comes to wonder
    // whether they are two settings.
    expect(find.text(kNoGridTargetLabel), findsNothing);
  });

  testWidgets('a grid you own carries Rename and Delete', (tester) async {
    await pump(
      tester,
      chosen: const GridSelection(networkId: 'a', networkName: 'hp-1-1'),
      network: _network(0),
      owned: true,
      onRename: () {},
      onDelete: () {},
    );

    expect(find.byKey(const Key('grid-hero-rename')), findsOneWidget);
    expect(find.byKey(const Key('grid-hero-delete')), findsOneWidget);
  });

  // The server refuses a non-owner anyway; the line naming the owner is what
  // stops the absence reading as a missing button.
  testWidgets('a grid somebody else owns carries neither', (tester) async {
    await pump(
      tester,
      chosen: const GridSelection(networkId: 'b', networkName: 'Water Grid'),
      network: _network(1),
    );

    expect(find.byKey(const Key('grid-hero-rename')), findsNothing);
    expect(find.byKey(const Key('grid-hero-delete')), findsNothing);
    // Nothing is said about it either. The OWNED BY pill names whose grid this
    // is, which is the fact; a line spelling out the consequence tells somebody
    // they may not do a thing they had not asked to do.
    expect(find.textContaining('Only the owner'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(GridHero),
        matching: find.text('someone@else.com'),
      ),
      findsOneWidget,
      reason: 'the owner is named once, on the pill',
    );
  });

  testWidgets('the headline names the access rule and the router', (
    tester,
  ) async {
    await pump(
      tester,
      chosen: const GridSelection(networkId: 'a', networkName: 'hp-1-1'),
      network: _network(0),
      owned: true,
    );

    expect(
      find.descendant(of: find.byType(GridHero), matching: find.text('JOIN')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GridHero),
        matching: find.text('Invite only'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GridHero),
        matching: find.text('On · 1 model'),
      ),
      findsOneWidget,
    );
  });

  // The no-grid headline wears a slate wash rather than grey, because grey in
  // this app means the absence of a state and this one is a state. A wash is
  // only worth having if what sits on it can be read.
  group('the slate headline is legible in both themes', () {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      test('on ${brightness.name}', () {
        AppTheme.brightness.value = brightness;
        addTearDown(() => AppTheme.brightness.value = Brightness.light);
        final page = brightness == Brightness.dark
            ? const Color(0xFF191919)
            : const Color(0xFFFAFAF9);
        final slate = _over(page, AppSurface.neutralWash);

        expect(
          _contrast(slate, AppPalette.textPrimary),
          greaterThan(4.5),
          reason: 'the headline itself',
        );
        expect(
          _contrast(slate, AppPalette.textSecondary),
          greaterThan(4.5),
          reason: 'the sentence explaining the state',
        );
        // The block has to be findable against the page it lies on, which is
        // the failure grey had: at 1.01:1 you cannot see where it starts.
        expect(
          _contrast(slate, page),
          greaterThan(_contrast(_over(page, AppSurface.accentWash), page) * 0.9),
          reason: 'as separated from the page as the accent state is',
        );
      });
    }
  });
}
