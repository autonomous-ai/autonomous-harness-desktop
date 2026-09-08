// The headline is the pane's answer to "where do my agents run right now".
//
// The rule this file exists to hold: picking a grid must not move anything.
// A first attempt at this design dropped the chosen grid out of the list below
// — which reflowed the whole pane on every pick, so the row you clicked jumped
// out from under the pointer. The list is now left alone, and these tests
// measure that rather than trusting it.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_mutations_controller.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/settings/sections/grid_hero.dart';
import 'package:harness/settings/sections/grid_network_table.dart';
import 'package:harness/settings/sections/grid_section.dart';
import 'package:harness/share/grid_cli.dart';
import 'package:harness/shared/theme/app_theme.dart';

import 'support/fake_grid_api.dart';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Cli extends GridCli {
  _Cli() : super(environment: const {'HOME': '/tmp/fake-home'});
  @override
  Future<String?> locate() async => '/usr/local/bin/grid';
  @override
  Future<GridCliResult> run(List<String> a) async =>
      const GridCliResult(exitCode: 0, stdout: '', stderr: '');
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GridSelectionStore selection;

  setUp(() => selection = GridSelectionStore(storage: _MemoryStore()));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeGridApi();
    final networks = GridNetworksController(client: api);
    final mutations = GridMutationsController(
      client: api,
      cli: _Cli(),
      networks: networks,
      selection: selection,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            AppTheme.brightness.value = Brightness.light;
            return BrightnessScope(
              child: Scaffold(
                body: GridSection(
                  controller: networks,
                  selection: selection,
                  mutations: mutations,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('nothing moves when you pick', () {
    // The failure this guards against is physical: the row you clicked slides
    // out from under the pointer, so the next click lands on a different grid.
    testWidgets('the table keeps its position and its rows', (tester) async {
      await pump(tester);
      final before = tester.getRect(find.byType(GridNetworkTable));
      final rowsBefore = tester.widgetList(find.text('hp-1-1')).length;

      await tester.tap(find.text('hp-1-1'));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(GridNetworkTable)),
        before,
        reason: 'picking a grid must not move or resize the list',
      );
      // Still in the list — it is highlighted there, not removed from it.
      expect(find.text('hp-1-1'), findsNWidgets(rowsBefore + 1));
    });

    // Grid names differ wildly in length, and the headline prints one at 23px.
    // If the block is not a fixed height, switching between a short name and a
    // long one reflows everything under it.
    // Owner and non-owner draw different actions — Share alone versus Share,
    // Rename and Delete — and the block above the list must not change height
    // between them either.
    testWidgets('owning the grid or not does not change its height', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('hp-1-1'));
      await tester.pumpAndSettle();
      final owned = tester.getRect(find.byType(GridHero));

      await tester.tap(find.text('Water Grid'));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(GridHero)).height,
        owned.height,
        reason: 'a grid you do not own must not shrink the headline',
      );
    });

    testWidgets('the headline is the same height whatever the name', (
      tester,
    ) async {
      await pump(tester);
      final empty = tester.getRect(find.byType(GridHero));

      await tester.tap(find.text('hp-1-1'));
      await tester.pumpAndSettle();
      final short = tester.getRect(find.byType(GridHero));

      await tester.tap(find.text('Water Grid'));
      await tester.pumpAndSettle();
      final other = tester.getRect(find.byType(GridHero));

      expect(
        short.height,
        other.height,
        reason: 'two grids must give the headline the same height',
      );
      expect(
        empty.height,
        short.height,
        reason: 'picking the first grid must not grow the headline either',
      );
    });
  });

  testWidgets('with no grid picked the headline says so and offers nothing', (
    tester,
  ) async {
    await pump(tester);

    // It says what the state MEANS, and does not repeat "No grid" — the list
    // below already carries a row by that name, marked as chosen, and the same
    // two words twice on one screen reads as two settings.
    expect(
      find.descendant(
        of: find.byType(GridHero),
        matching: find.text('Each engine\u2019s own account'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GridHero),
        matching: find.text(kNoGridTargetLabel),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('grid-hero-rename')), findsNothing);
    expect(find.byKey(const Key('grid-hero-delete')), findsNothing);
  });

  // The pane held "No grid" twice — once as the headline's title, once as the
  // list's first row — 200px apart, in the same words, both marked chosen.
  testWidgets('the pane names the no-grid state exactly once', (tester) async {
    await pump(tester);
    expect(find.text(kNoGridTargetLabel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GridNetworkTable),
        matching: find.text(kNoGridTargetLabel),
      ),
      findsOneWidget,
      reason: 'the one that survives is the row you click',
    );
  });

  group('the pane offers each action once', () {
    // The headline draws the chosen grid in full, actions included. The drawer
    // used to draw them again for the same grid — one irreversible Delete on
    // screen twice, 400px apart.
    testWidgets('the chosen grid has no second Rename in its drawer', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('hp-1-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Details for hp-1-1'));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
      expect(find.byKey(const Key('grid-hero-rename')), findsOneWidget);
      expect(find.text('Delete grid'), findsNothing);
    });

    // …but a grid you own and are NOT using still needs them, because the
    // headline only ever describes the one in use.
    testWidgets('another grid you own keeps them in its drawer', (
      tester,
    ) async {
      await pump(tester);
      // Use the grid somebody else owns, so the owned one is not the chosen.
      await tester.tap(find.text('Water Grid'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Details for hp-1-1'));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete grid'), findsOneWidget);
      // The headline offers neither: it is describing a grid you do not own.
      expect(find.byKey(const Key('grid-hero-rename')), findsNothing);
    });
  });

  testWidgets('a grid you own carries Rename and Delete', (tester) async {
    await pump(tester);
    await tester.tap(find.text('hp-1-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grid-hero-rename')), findsOneWidget);
    expect(find.byKey(const Key('grid-hero-delete')), findsOneWidget);
  });

  // The server refuses a non-owner anyway; the line naming the owner is what
  // stops the absence reading as a missing button.
  testWidgets('a grid somebody else owns carries neither', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Water Grid'));
    await tester.pumpAndSettle();

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
    await pump(tester);
    await tester.tap(find.text('hp-1-1'));
    await tester.pumpAndSettle();

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
