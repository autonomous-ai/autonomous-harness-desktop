// Settings ▸ Usage. What matters here is the pane's job as a *reader*: an
// off provider must not look like an empty one, a cost that is short must say
// so, and the switches have to be reachable from the state the pane rests in.
// A screen that renders "nothing switched on" and "nothing spent" the same is
// the screen that sends somebody looking for a bug in the scanners.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/settings/sections/usage_detail_panels.dart';
import 'package:harness/settings/sections/usage_panels.dart';
import 'package:harness/settings/sections/usage_provider_pane.dart';
import 'package:harness/settings/sections/usage_section.dart';
import 'package:harness/stats/harness_stats.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/shared/widgets/app_menu.dart';
import 'package:harness/usage/ledger/ledger_scanner.dart';
import 'package:harness/core/snapshot_store.dart';
import 'package:harness/usage/ledger/ledger_types.dart';
import 'package:harness/usage/ledger/usage_ledger_controller.dart';
import 'package:harness/usage/ledger/usage_ledger_store.dart';

class _MemorySettings implements LocalKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FixedScanner implements LedgerScanner {
  _FixedScanner(this.provider, this.result);

  @override
  final LedgerProvider provider;
  final LedgerScanResult result;

  @override
  Future<LedgerScanResult> scan(Map<String, ScannedSource> previous) async =>
      result;
}

LedgerEntry _entry({
  required LedgerProvider provider,
  String sessionId = 's1',
  String? model = 'claude-opus-5',
  UsageTotals totals = const UsageTotals(
    freshInput: 1000,
    output: 500,
    cacheRead: 8000,
  ),
  double? costUsd,
}) => LedgerEntry(
  provider: provider,
  sessionId: sessionId,
  timestamp: DateTime.now().subtract(const Duration(hours: 2)),
  totals: totals,
  model: model,
  costUsd: costUsd,
  dedupeKey: '$provider-$sessionId-$model',
);

/// The lens picker. Found by type rather than by its text, because the closed
/// field and the overview's own provider rows print the same words — and the
/// repo's `app_select_field_test` drives it exactly this way.
final _lensField = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == 'AppSelectField<LedgerProvider?>',
);

/// Open the lens picker and choose [label].
Future<void> _pickLens(WidgetTester tester, String label) async {
  await tester.tap(_lensField);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(AppMenuItem), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  /// A controller over fake scanners and in-memory storage — never a real
  /// `~/.claude` or a real `~/.harness`, and never real disk.
  UsageLedgerController controllerWith(
    Map<LedgerProvider, LedgerScanResult> results,
  ) {
    final settings = _MemorySettings();
    return UsageLedgerController(
      stores: [
        for (final provider in LedgerProvider.values)
          UsageLedgerStore(
            scanner: _FixedScanner(
              provider,
              results[provider] ?? const LedgerScanResult(),
            ),
            settings: settings,
            snapshots: MemorySnapshotStore(),
          ),
      ],
    );
  }

  Future<void> pumpUsage(
    WidgetTester tester,
    UsageLedgerController controller, {
    HarnessStats? stats,
  }) async {
    tester.view.physicalSize = const Size(1000 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            AppTheme.brightness.value = Brightness.light;
            return BrightnessScope(
              child: Scaffold(
                body: UsageSection(
                  controller: controller,
                  // Injected always: the singleton is shared across the whole
                  // run, so a test that used it would see whatever the previous
                  // one counted.
                  stats: stats ?? HarnessStats(store: MemorySnapshotStore()),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('rests with nothing switched on, and offers the switches', (
    tester,
  ) async {
    final controller = controllerWith(const {});
    await controller.load();
    await pumpUsage(tester, controller);

    expect(find.byType(UsageEmptyState), findsOneWidget);
    expect(find.text('Nothing is being read yet.'), findsOneWidget);
    for (final provider in LedgerProvider.values) {
      expect(find.text('Enable ${provider.label}'), findsOneWidget);
    }
    // The ledger figures are absent, not zeroed: a "0 tokens" card here would
    // be a claim about a machine nothing has been read from.
    expect(find.text('Total tokens'), findsNothing);
  });

  group('stats', () {
    testWidgets('an app that has done nothing says so, rather than three zeroes', (
      tester,
    ) async {
      final controller = controllerWith(const {});
      await controller.load();
      await pumpUsage(tester, controller);

      expect(
        find.text('Start your first agent to begin tracking.'),
        findsOneWidget,
      );
      expect(find.text('Agents spawned'), findsNothing);
    });

    testWidgets('draws the three counters and the date they run from', (
      tester,
    ) async {
      final stats = HarnessStats(store: MemorySnapshotStore());
      addTearDown(stats.dispose);
      final at = DateTime(2026, 9, 1, 9);
      stats.onAgentSpawned(at: at);
      stats.onAgentSpawned(at: at);
      stats.onTurnStarted('k', at: at);
      stats.onTurnEnded('k', at: at.add(const Duration(hours: 2, minutes: 30)));

      final controller = controllerWith(const {});
      await controller.load();
      await pumpUsage(tester, controller, stats: stats);

      expect(find.text('Agents spawned'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('2h 30m'), findsOneWidget);
      expect(find.text('Tracking since Sep 1, 2026'), findsOneWidget);
    });

    testWidgets('the counters move while the screen is open', (tester) async {
      final stats = HarnessStats(store: MemorySnapshotStore());
      addTearDown(stats.dispose);
      final controller = controllerWith(const {});
      await controller.load();
      await pumpUsage(tester, controller, stats: stats);

      expect(find.text('Agents spawned'), findsNothing);

      stats.onAgentSpawned();
      await tester.pumpAndSettle();

      expect(find.text('Agents spawned'), findsOneWidget);
    });
  });

  group('overview panels', () {
    testWidgets('the heatmap names its best day and carries a scale', (
      tester,
    ) async {
      final controller = controllerWith({
        LedgerProvider.claude: LedgerScanResult(
          sources: [
            ScannedSource(
              path: 'a.jsonl',
              mtimeMs: 1,
              size: 1,
              entries: [_entry(provider: LedgerProvider.claude)],
            ),
          ],
        ),
      });
      await controller.load();
      await controller.storeFor(LedgerProvider.claude).setEnabled(true);
      await pumpUsage(tester, controller);

      expect(find.text('Daily intensity'), findsOneWidget);
      expect(find.textContaining('Best: '), findsOneWidget);
      expect(find.text('Less'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('the mix is three slices, with reasoning as a badge', (
      tester,
    ) async {
      final controller = controllerWith({
        LedgerProvider.claude: LedgerScanResult(
          sources: [
            ScannedSource(
              path: 'a.jsonl',
              mtimeMs: 1,
              size: 1,
              entries: [
                _entry(
                  provider: LedgerProvider.claude,
                  totals: const UsageTotals(
                    freshInput: 1000,
                    output: 4000,
                    cacheRead: 5000,
                    reasoning: 3500,
                  ),
                ),
              ],
            ),
          ],
        ),
      });
      await controller.load();
      await controller.storeFor(LedgerProvider.claude).setEnabled(true);
      await pumpUsage(tester, controller);

      expect(find.text('Token mix'), findsOneWidget);
      expect(find.text('New input: 1.0k'), findsOneWidget);
      expect(find.text('Output: 4.0k'), findsOneWidget);
      // Cache read and cache write are one slice on the overview.
      expect(find.text('Cache: 5.0k'), findsOneWidget);
      // Reasoning is a SUBSET of output, so it is a badge and not a fourth
      // slice — 10k total, not 13.5k.
      expect(find.text('3.5k reasoning'), findsOneWidget);
      expect(find.text('10.0k'), findsOneWidget);
    });
  });

  group('provider lens', () {
    testWidgets('opens on the overview, not on a provider', (tester) async {
      final controller = controllerWith(const {});
      await controller.load();
      await pumpUsage(tester, controller);

      expect(find.text('Usage analytics'), findsOneWidget);
      expect(find.byType(UsageProviderPane), findsNothing);
      expect(find.byType(UsageEmptyState), findsOneWidget);
    });

    testWidgets('picking a provider swaps in its detail pane', (tester) async {
      final controller = controllerWith({
        LedgerProvider.claude: LedgerScanResult(
          sources: [
            ScannedSource(
              path: 'a.jsonl',
              mtimeMs: 1,
              size: 1,
              entries: [_entry(provider: LedgerProvider.claude)],
            ),
          ],
        ),
      });
      await controller.load();
      await controller.storeFor(LedgerProvider.claude).setEnabled(true);
      await pumpUsage(tester, controller);

      await _pickLens(tester, 'Claude');

      expect(find.byType(UsageProviderPane), findsOneWidget);
      // The eight figures, the range it is showing, and the panels under them.
      expect(find.text('Cache reuse rate'), findsOneWidget);
      expect(find.text('Sessions / turns'), findsOneWidget);
      expect(find.text('All local Claude usage · Last 30 days'), findsOneWidget);
      expect(find.byType(UsageDailyChart), findsOneWidget);
      expect(find.text('By model'), findsOneWidget);
      expect(find.text('By project'), findsOneWidget);
      expect(find.byType(UsageSessionsTable), findsOneWidget);
    });

    testWidgets('a provider that is off offers its own switch', (tester) async {
      final controller = controllerWith(const {});
      await controller.load();
      await pumpUsage(tester, controller);

      await _pickLens(tester, 'Codex');

      expect(find.byType(UsageProviderPane), findsOneWidget);
      expect(find.text('Enable Codex'), findsOneWidget);
      expect(find.text('Cache reuse rate'), findsNothing);
    });
  });

  testWidgets('enabling a provider from the empty state draws its figures', (
    tester,
  ) async {
    final controller = controllerWith({
      LedgerProvider.claude: LedgerScanResult(
        sources: [
          ScannedSource(
            path: 'a.jsonl',
            mtimeMs: 1,
            size: 1,
            entries: [_entry(provider: LedgerProvider.claude)],
          ),
        ],
      ),
    });
    await controller.load();
    await pumpUsage(tester, controller);

    await tester.tap(find.text('Enable Claude'));
    await tester.pumpAndSettle();

    expect(find.byType(UsageEmptyState), findsNothing);
    expect(find.byType(UsageStatCard), findsNWidgets(4));
    expect(find.text('Total tokens'), findsOneWidget);
    // 1000 + 500 + 8000
    expect(find.text('9.5k'), findsOneWidget);
    expect(find.text('1 enabled · 1 with data'), findsOneWidget);
  });

  testWidgets('an unpriced model makes the cost a floor rather than a total', (
    tester,
  ) async {
    final controller = controllerWith({
      LedgerProvider.claude: LedgerScanResult(
        sources: [
          ScannedSource(
            path: 'a.jsonl',
            mtimeMs: 1,
            size: 1,
            entries: [
              _entry(provider: LedgerProvider.claude),
              _entry(
                provider: LedgerProvider.claude,
                sessionId: 's2',
                model: 'a-grid-model-nobody-prices',
              ),
            ],
          ),
        ],
      ),
    });
    await controller.load();
    await controller.storeFor(LedgerProvider.claude).setEnabled(true);
    await pumpUsage(tester, controller);

    expect(find.text('at least — some models unpriced'), findsOneWidget);
    expect(
      find.textContaining('some model prices are unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('an absent CLI reads as not found, never as nothing spent', (
    tester,
  ) async {
    final controller = controllerWith({
      LedgerProvider.opencode: const LedgerScanResult.unavailable(
        'No OpenCode database on this computer',
      ),
    });
    await controller.load();
    await controller.storeFor(LedgerProvider.opencode).setEnabled(true);
    await pumpUsage(tester, controller);

    expect(find.text('Not found'), findsOneWidget);
    expect(
      find.text('No OpenCode database on this computer'),
      findsOneWidget,
      reason: "the scanner's own sentence, not a re-worded one",
    );
  });

  testWidgets('a provider that is off says so rather than showing a zero', (
    tester,
  ) async {
    final controller = controllerWith(const {});
    await controller.load();
    await pumpUsage(tester, controller);

    expect(
      find.text('Off — nothing on this machine is read.'),
      findsNWidgets(LedgerProvider.values.length),
    );
  });

  testWidgets('every provider keeps a row whether it is on or not', (
    tester,
  ) async {
    final controller = controllerWith(const {});
    await controller.load();
    await pumpUsage(tester, controller);

    expect(
      find.byType(ProviderUsageRow),
      findsNWidgets(LedgerProvider.values.length),
    );
    for (final provider in LedgerProvider.values) {
      expect(find.text(provider.label), findsOneWidget);
    }
  });
}
