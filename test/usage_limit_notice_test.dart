// The card is the only thing this app says without being asked, so what it
// takes to make it appear — and what it takes to make it shut up — is the
// feature.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/usage/usage_controller.dart';
import 'package:harness/usage/usage_nudge_store.dart';
import 'package:harness/usage/usage_source.dart';
import 'package:harness/usage/usage_window.dart';
import 'package:harness/widgets/usage_limit_notice.dart';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _StubUsageSource implements UsageSource {
  _StubUsageSource(this.reading);

  final ProviderUsage reading;

  @override
  UsageProvider get provider => reading.provider;

  @override
  Future<ProviderUsage> read() async => reading;
}

ProviderUsage _reading(UsageProvider provider, double percent) => ProviderUsage(
  provider: provider,
  status: UsageStatus.ok,
  windows: [
    UsageWindow(
      label: provider == UsageProvider.claude ? 'Session' : '5h',
      usedPercent: percent,
    ),
  ],
  fetchedAt: DateTime.now(),
);

/// A controller holding one Claude reading, already settled.
///
/// `autoStart: false` and one explicit refresh, for the reason the rail's own
/// tests give: a periodic timer is a `pumpAndSettle` that never settles.
Future<UsageController> _usageAt(double percent) async {
  final controller = UsageController(
    sources: [_StubUsageSource(_reading(UsageProvider.claude, percent))],
    autoStart: false,
  );
  await controller.refresh();
  return controller;
}

void main() {
  /// One machine with [agents] on it.
  AppNotifier notifierWith(List<Agent> agents) {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
    notifier.machineStates['m1'] = MachineState(
      const Machine(
        machineId: 'm1',
        apiKey: '',
        authMode: MachineAuthMode.remote,
        name: 'm1',
        status: 'online',
      ),
    )..agents = agents;
    return notifier;
  }

  Agent claudeAgent({String id = 'a1', AgentGrid? grid}) => Agent(
    id: id,
    name: id,
    engine: 'claude',
    status: 'active',
    terminalAvailable: true,
    grid: grid,
  );

  Agent codexAgent({String id = 'a2'}) =>
      Agent(id: id, name: id, engine: 'codex', status: 'active');

  Future<UsageNudgeStore> pumpNotice(
    WidgetTester tester, {
    required AppNotifier notifier,
    required UsageController usage,
    String? providerName,
    bool gridSurface = true,
    UsageNudgeStore? nudges,
  }) async {
    final selection = GridSelectionStore(storage: _MemoryStore());
    if (providerName != null) {
      await selection.selectNetwork(
        networkId: 'grid-1',
        networkName: providerName,
      );
    }
    final store = nudges ?? UsageNudgeStore(storage: _MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageLimitNotice(
            notifier: notifier,
            usage: usage,
            nudges: store,
            selection: selection,
            gridSurface: gridSurface,
          ),
        ),
      ),
    );
    await tester.pump();
    return store;
  }

  testWidgets('a window under the threshold says nothing', (tester) async {
    final usage = await _usageAt(83);
    addTearDown(usage.dispose);
    await pumpNotice(
      tester,
      notifier: notifierWith([claudeAgent()]),
      usage: usage,
      providerName: 'Water Grid',
    );
    expect(find.textContaining('through its'), findsNothing);
  });

  testWidgets('a spent window with a provider offers the move', (tester) async {
    final usage = await _usageAt(92);
    addTearDown(usage.dispose);
    await pumpNotice(
      tester,
      notifier: notifierWith([claudeAgent()]),
      usage: usage,
      providerName: 'Water Grid',
    );
    expect(
      find.text('Claude is 92% through its Session limit'),
      findsOneWidget,
    );
    expect(find.text('Move 1 agent'), findsOneWidget);
    expect(find.textContaining('Water Grid'), findsOneWidget);
  });

  testWidgets('with no provider it offers the picker instead', (tester) async {
    final usage = await _usageAt(92);
    addTearDown(usage.dispose);
    await pumpNotice(
      tester,
      notifier: notifierWith([claudeAgent()]),
      usage: usage,
    );
    expect(find.text('Choose a provider'), findsOneWidget);
  });

  testWidgets('with a default set, an agent already on it is not a reason', (
    tester,
  ) async {
    // It is not spending the subscription that is running out, and new agents
    // already launch on the provider — so there is nothing left to offer.
    final usage = await _usageAt(92);
    addTearDown(usage.dispose);
    await pumpNotice(
      tester,
      notifier: notifierWith([
        claudeAgent(grid: const AgentGrid(baseUrl: 'https://relay/x')),
      ]),
      usage: usage,
      providerName: 'Water Grid',
    );
    expect(find.textContaining('through its'), findsNothing);
  });

  testWidgets('agents parked on a provider still earn the picker', (
    tester,
  ) async {
    // The case that caught this: every agent of the engine had been moved onto
    // a provider by hand, so nothing was on the subscription — but no DEFAULT
    // was picked either, which means the next `New agent` lands right back on
    // the account that is running out.
    final usage = await _usageAt(97);
    addTearDown(usage.dispose);
    await pumpNotice(
      tester,
      notifier: notifierWith([
        claudeAgent(grid: const AgentGrid(baseUrl: 'https://relay/x')),
      ]),
      usage: usage,
    );
    expect(find.text('Choose a provider'), findsOneWidget);
  });

  testWidgets('a build with no providers draws nothing at all', (tester) async {
    final usage = await _usageAt(97);
    addTearDown(usage.dispose);
    await pumpNotice(
      tester,
      notifier: notifierWith([claudeAgent()]),
      usage: usage,
      providerName: 'Water Grid',
      gridSurface: false,
    );
    expect(find.textContaining('through its'), findsNothing);
  });

  testWidgets('taking the move closes it — the question is answered', (
    tester,
  ) async {
    final usage = await _usageAt(92);
    addTearDown(usage.dispose);
    final store = await pumpNotice(
      tester,
      notifier: notifierWith([claudeAgent()]),
      usage: usage,
      providerName: 'Water Grid',
    );

    await tester.tap(find.text('Move 1 agent'));
    await tester.pumpAndSettle();
    // The move itself fails here — there is no daemon behind this notifier —
    // but the card's own contract does not depend on that: it asked, it was
    // answered, and it does not ask again this cycle.
    expect(store.isDismissed('claude|Session'), isTrue);
    expect(find.textContaining('through its'), findsNothing);
  });

  testWidgets('closing one does not hand the next a click you did not make', (
    tester,
  ) async {
    // Both accounts are over the threshold. Closing the first used to put the
    // second on screen in the same place, under the pointer that had just
    // clicked — so the second click landed on a card nobody had read.
    final usage = UsageController(
      sources: [
        _StubUsageSource(_reading(UsageProvider.claude, 92)),
        _StubUsageSource(_reading(UsageProvider.codex, 97)),
      ],
      autoStart: false,
    );
    addTearDown(usage.dispose);
    await usage.refresh();
    await pumpNotice(
      tester,
      notifier: notifierWith([claudeAgent(), codexAgent()]),
      usage: usage,
    );
    // Codex is the tighter window, so it is the one on screen.
    expect(find.textContaining('Codex is 97%'), findsOneWidget);

    await tester.tap(find.byTooltip('Not now — until this limit resets'));
    await tester.pumpAndSettle();
    expect(find.textContaining('through its'), findsNothing);
  });

  testWidgets('closing it silences that window, poll after poll', (
    tester,
  ) async {
    final usage = await _usageAt(92);
    addTearDown(usage.dispose);
    final store = await pumpNotice(
      tester,
      notifier: notifierWith([claudeAgent()]),
      usage: usage,
      providerName: 'Water Grid',
    );

    await tester.tap(find.byTooltip('Not now — until this limit resets'));
    await tester.pumpAndSettle();
    expect(find.textContaining('through its'), findsNothing);

    // The poll behind this runs once a minute. Without the dismissal the card
    // would be back on the next answer, which is how people learn to close a
    // warning unread.
    await usage.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('through its'), findsNothing);
    expect(store.isDismissed('claude|Session'), isTrue);
  });
}
