// What this control says IS what the user knows about where their tokens go, so the three states it
// can be in are the feature from where they sit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/shared/widgets/skeleton.dart';
import 'package:harness/shared/widgets/toolbar_pill.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/agent_model_menu.dart';
import 'package:harness/widgets/model_picker_dialog.dart';

const kRelay = 'https://grid.autonomous.ai/grid-abc/relay';
const kNetworkId = 'grid-live';

void main() {
  /// A machine with one claude agent pinned to a model, which is the fixture
  /// every test here needs and none of them is about.
  AppNotifier notifierOf(WidgetTester tester, {String engine = 'claude'}) {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
    notifier.machineStates['m1'] =
        MachineState(
            const Machine(
              machineId: 'm1',
              apiKey: '',
              authMode: MachineAuthMode.remote,
              name: 'm1',
              status: 'online',
            ),
          )
          ..agents = [
            Agent(
              id: 'a1',
              name: 'a1',
              engine: engine,
              status: 'active',
              terminalAvailable: true,
              grid: const AgentGrid(baseUrl: kRelay, model: 'Pinned-Model'),
            ),
          ];
    return notifier;
  }

  Future<void> pumpPill(
    WidgetTester tester,
    AppNotifier notifier, {
    String engine = 'claude',
    bool gridSurface = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AgentModelMenu(
              notifier: notifier,
              machineId: 'm1',
              agentId: 'a1',
              engine: engine,
              gridSurface: gridSurface,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('an agent with no grid says so', () {
    expect(agentModelLabel(null), kNoGridTargetLabel);
  });

  test('a grid with no model left the choice to the grid', () {
    expect(agentModelLabel(const AgentGrid(baseUrl: kRelay)), 'Auto');
  });

  test('a pinned model is named', () {
    expect(
      agentModelLabel(const AgentGrid(baseUrl: kRelay, model: 'GLM-4.7-Flash')),
      'GLM-4.7-Flash',
    );
  });

  testWidgets('the control is there even with no default provider', (
    tester,
  ) async {
    // It used to leave whenever the sidebar had picked no provider, which was
    // right while the menu could only offer that one grid's models. The picker
    // now lists every provider this computer offers — so hiding the door to it
    // made an agent's model unreadable and unchangeable for exactly the people
    // who had not found the sidebar's picker.
    final before = gridSelectionStore.value;
    addTearDown(() => gridSelectionStore.value = before);
    gridSelectionStore.value = GridSelection.none;

    await pumpPill(tester, notifierOf(tester));

    expect(find.byType(ToolbarPill), findsOneWidget);
    expect(find.text(kModelPillLabel), findsOneWidget);
  });

  testWidgets('a build with no providers in it draws nothing at all', (
    tester,
  ) async {
    // The one reason this control is ever absent. `kGridSurfaceEnabled` is a
    // const the test run has switched ON, so the shipped build's own behaviour
    // is only reachable through the seam.
    await pumpPill(tester, notifierOf(tester), gridSurface: false);

    expect(find.byType(ToolbarPill), findsNothing);
    expect(
      tester.getSize(find.byType(AgentModelMenu)),
      Size.zero,
      reason: 'nothing left behind for the header to space around',
    );
  });

  group('the picker it opens', () {
    // The dropdown this replaced could only ever list the models of the grid the
    // sidebar had picked — its rows were built here, from one network's cache.
    // The choices now live in a dialog that lists EVERY provider this computer
    // offers (`model_picker_dialog.dart`, tested there); what this file still
    // owes is that the pill opens it and stays lit under it.
    final beforeSelection = gridSelectionStore.value;

    setUp(() {
      gridSelectionStore.value = const GridSelection(
        networkId: kNetworkId,
        networkName: 'Live Grid',
      );
    });

    tearDown(() => gridSelectionStore.value = beforeSelection);

    testWidgets('opens on the pill, over the pane', (tester) async {
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      notifier.machineStates['m1'] =
          MachineState(
              const Machine(
                machineId: 'm1',
                apiKey: '',
                authMode: MachineAuthMode.remote,
                name: 'm1',
                status: 'online',
              ),
            )
            ..agents = [
              const Agent(
                id: 'a1',
                name: 'a1',
                engine: 'claude',
                status: 'active',
                terminalAvailable: true,
                grid: AgentGrid(baseUrl: kRelay, model: 'Pinned-Model'),
              ),
            ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentModelMenu(
              notifier: notifier,
              machineId: 'm1',
              agentId: 'a1',
              engine: 'claude',
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text(kModelPillLabel));
      await tester.pumpAndSettle();

      expect(find.byType(ModelPickerDialog), findsOneWidget);
      expect(find.text('Select model'), findsOneWidget);
    });
  });

  group('while a restart is in flight', () {
    // Picking a model restarts the agent, and the wait used to be a CircularProgressIndicator in a
    // bare SizedBox. Two bugs in one: ToolbarPill's box is a fixed 26px tall and hands its single
    // child a TIGHT height, so the SizedBox took 12x24 and the spinner drew as a squashed arc (a
    // Row escapes that with mainAxisSize.min; a SizedBox has no such out). And a spinner was the
    // wrong control anyway — the shape here is known, it is the same line of mono type about to
    // say a different model, which is exactly when `skeleton.dart` says to use a skeleton.
    final beforeSelection = gridSelectionStore.value;

    setUp(() {
      gridSelectionStore.value = const GridSelection(
        networkId: kNetworkId,
        networkName: 'Live Grid',
      );
    });

    tearDown(() {
      gridSelectionStore.value = beforeSelection;
    });

    /// Builds the control and hands back its State, so a test can put it in flight through the
    /// seam rather than by picking for real — a real pick calls out over HTTP.
    Future<AgentModelMenuState> pumpMenu(WidgetTester tester) async {
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      notifier.machineStates['m1'] =
          MachineState(
              const Machine(
                machineId: 'm1',
                apiKey: '',
                authMode: MachineAuthMode.remote,
                name: 'm1',
                status: 'online',
              ),
            )
            ..agents = [
              const Agent(
                id: 'a1',
                name: 'a1',
                engine: 'claude',
                status: 'active',
                terminalAvailable: true,
                grid: AgentGrid(baseUrl: kRelay, model: 'Pinned-Model'),
              ),
            ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AgentModelMenu(
                notifier: notifier,
                machineId: 'm1',
                agentId: 'a1',
                engine: 'claude',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.state<AgentModelMenuState>(find.byType(AgentModelMenu));
    }

    /// Puts the control in flight and settles the frame.
    Future<void> beginRestart(
      WidgetTester tester,
      AgentModelMenuState state,
    ) async {
      state.debugSetPending(true);
      await tester.pump();
    }

    testWidgets('the wait is a skeleton, not a spinner', (tester) async {
      final state = await pumpMenu(tester);
      await beginRestart(tester, state);

      expect(find.byType(SkeletonText), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'the shape is known, so the placeholder wears it',
      );

      // The skeleton breathes on a repeating animation, so the tree has to come down inside the
      // test — the binding asserts on a live ticker once the tree is gone.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the pill does not resize as the placeholder swaps in', (
      tester,
    ) async {
      final state = await pumpMenu(tester);
      final idle = tester.getRect(find.byType(ToolbarPill));

      await beginRestart(tester, state);

      expect(
        tester.getRect(find.byType(ToolbarPill)).width,
        moreOrLessEquals(idle.width, epsilon: 1),
        reason:
            'a placeholder that changes the box causes the very jump it exists '
            'to prevent',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the pill keeps its rim through the restart', (tester) async {
      // `enabled` goes false mid-flight so a second tap cannot land, but the control is momentarily
      // busy rather than inert — dropping the rim would blink the one box on the strip.
      final state = await pumpMenu(tester);
      await beginRestart(tester, state);

      final pill = tester.widget<ToolbarPill>(find.byType(ToolbarPill));
      expect(pill.rimmed, isTrue);
      expect(pill.onTap, isNull, reason: 'still not tappable while in flight');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the trigger reads as a control', () {
    // The label was a bare Text in AppPalette.textFaint — #6E6E68 on the header's #1E1E1E, ~2.6:1
    // and under the 4.5:1 floor — with no fill, rim or glyph. That is the app's FAINTEST ink on a
    // control that restarts the agent when you use it, and it sat beside an agent name drawn in
    // full-strength textPrimary, so the one pressable thing in the strip read as the least
    // pressable. These pin the affordance rather than the pixels: a ToolbarPill (the app's own
    // toolbar control, with its hover fill and hit box) carrying a chevron.
    final beforeSelection = gridSelectionStore.value;

    setUp(() {
      gridSelectionStore.value = const GridSelection(
        networkId: kNetworkId,
        networkName: 'Live Grid',
      );
    });

    tearDown(() {
      gridSelectionStore.value = beforeSelection;
    });

    Future<void> pumpMenu(WidgetTester tester, {required String engine}) async {
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      notifier.machineStates['m1'] =
          MachineState(
              const Machine(
                machineId: 'm1',
                apiKey: '',
                authMode: MachineAuthMode.remote,
                name: 'm1',
                status: 'online',
              ),
            )
            ..agents = [
              Agent(
                id: 'a1',
                name: 'a1',
                engine: engine,
                status: 'active',
                terminalAvailable: true,
                grid: const AgentGrid(baseUrl: kRelay, model: 'Pinned-Model'),
              ),
            ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentModelMenu(
              notifier: notifier,
              machineId: 'm1',
              agentId: 'a1',
              engine: engine,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a usable trigger is a pill with a chevron', (tester) async {
      await pumpMenu(tester, engine: 'claude');

      expect(find.byType(ToolbarPill), findsOneWidget);
      expect(
        find.byIcon(Icons.expand_more_rounded),
        findsOneWidget,
        reason: 'the glyph is what says this label opens something',
      );
      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).onTap,
        isNotNull,
        reason: 'a grid-capable engine on a selected grid can change model',
      );
    });

    testWidgets(
      'the label carries the pill\'s own ink, not the faintest token',
      (tester) async {
        await pumpMenu(tester, engine: 'claude');

        expect(
          tester.widget<Text>(find.text(kModelPillLabel)).style?.color,
          ToolbarPill.tint(tinted: false, enabled: true),
          reason: 'textFaint on the header ground is ~2.6:1 — under the 4.5:1 floor',
        );
      },
    );

    testWidgets('an engine with no grid loses the chevron, not the label', (
      tester,
    ) async {
      // 'gemini' is outside kGridCapableEngines: the control still has to say
      // where the agent's tokens go — which it now does on hover — but a chevron
      // there would promise a picker that never opens.
      await pumpMenu(tester, engine: 'gemini');

      expect(find.text(kModelPillLabel), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        startsWith('Pinned-Model'),
        reason: 'the model is the first thing a hover should answer',
      );
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).onTap,
        isNull,
      );
    });

    testWidgets('the trigger is legible as a control BEFORE it is hovered', (
      tester,
    ) async {
      // The point of the rim. ToolbarPill's default fill is transparent until hover, so without it
      // the control is invisible at rest — the affordance would only arrive for someone who had
      // already guessed the label was pressable and moved onto it.
      await pumpMenu(tester, engine: 'claude');

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).rimmed,
        isTrue,
        reason: 'alone among plain labels, the pill needs its rim at rest',
      );
    });

    testWidgets('a disabled trigger carries no rim', (tester) async {
      // A rim is the mark of something pressable; drawing one around an inert control is the same
      // false promise as the chevron.
      await pumpMenu(tester, engine: 'gemini');

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).rimmed,
        isFalse,
      );
    });

    testWidgets('the pill stays lit while its own picker is open', (
      tester,
    ) async {
      // Nothing tells the pill its dialog is showing, so the widget tracks it: without that the
      // pill drops its fill the moment the pointer leaves it for the panel it just opened.
      await pumpMenu(tester, engine: 'claude');

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).active,
        isFalse,
      );

      await tester.tap(find.text(kModelPillLabel));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).active,
        isTrue,
        reason: 'the trigger must not go quiet under its own open panel',
      );
    });
  });

  group('an agent that is mid-turn', () {
    // Before this, the control let the user pick during a turn and surfaced the CLI's refusal
    // afterwards as a SnackBar ("It is running a turn. Move it when the turn finishes.") — a
    // round trip to be told the click was never going to work. The app already knows which
    // agents are mid-turn, so the pill disables itself for exactly those and says why on hover.
    // The AGENT_BUSY path is untouched and still the backstop: only the CLI reads the pane, and a
    // turn can start between a build and a tap.
    final beforeSelection = gridSelectionStore.value;

    setUp(() {
      gridSelectionStore.value = const GridSelection(
        networkId: kNetworkId,
        networkName: 'Live Grid',
      );
    });

    tearDown(() {
      gridSelectionStore.value = beforeSelection;
    });

    /// Builds the control against a notifier the test can drive turns on.
    Future<AppNotifier> pumpBusyMenu(WidgetTester tester) async {
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      notifier.machineStates['m1'] =
          MachineState(
              const Machine(
                machineId: 'm1',
                apiKey: '',
                authMode: MachineAuthMode.remote,
                name: 'm1',
                status: 'online',
              ),
            )
            ..agents = [
              const Agent(
                id: 'a1',
                name: 'a1',
                engine: 'claude',
                status: 'active',
                terminalAvailable: true,
                grid: AgentGrid(baseUrl: kRelay, model: 'Pinned-Model'),
              ),
            ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AgentModelMenu(
                notifier: notifier,
                machineId: 'm1',
                agentId: 'a1',
                engine: 'claude',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return notifier;
    }

    /// A turn ending, as the daemon announces it.
    Future<void> endTurn(WidgetTester tester, AppNotifier notifier) async {
      await notifier.handleMachineEventForTest('m1', {
        'type': 'turn_ended',
        'agentId': 'a1',
      });
      await tester.pump();
    }

    /// A turn starting, as the daemon announces it.
    ///
    /// `turn_started` arms a watchdog that clears a stalled turn (`turnActivityTimeout`), and a
    /// pending timer fails the test binding on teardown. Every test here ends the turn for real
    /// rather than letting the clock be mocked out from under the thing being tested.
    Future<void> startTurn(WidgetTester tester, AppNotifier notifier) async {
      await notifier.handleMachineEventForTest('m1', {
        'type': 'turn_started',
        'agentId': 'a1',
      });
      await tester.pump();
    }

    testWidgets('cannot be picked for, and says so', (tester) async {
      final notifier = await pumpBusyMenu(tester);

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).onTap,
        isNotNull,
        reason: 'an idle agent must still be pickable',
      );

      await startTurn(tester, notifier);

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).onTap,
        isNull,
        reason: 'a mid-turn agent must not open a menu the CLI would refuse',
      );
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        allOf(startsWith('Pinned-Model'), contains('running a turn')),
        reason: 'the reason has to be readable without clicking first',
      );

      // Disarms the turn watchdog, which outlives the widget tree otherwise.
      await endTurn(tester, notifier);
    });

    testWidgets('shows no spinner mid-turn, and keeps its rim', (tester) async {
      final notifier = await pumpBusyMenu(tester);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await startTurn(tester, notifier);

      expect(
        find.byIcon(Icons.expand_more_rounded),
        findsNothing,
        reason: 'a chevron on a control that cannot open is a lie',
      );
      // The pill drew the rail's running-agent spinner here, and it was read as this control
      // loading — which is what the skeleton beside it actually means. The turn is on screen
      // twice already (the pane itself, and the rail's badge); the pill only owes the reader
      // why it will not open, and it says that in words.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'one control, one meaning: motion here is this pill working',
      );
      expect(
        find.text(kModelPillLabel),
        findsOneWidget,
        reason: 'the control still names itself while it is refusing',
      );
      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).rimmed,
        isTrue,
        reason:
            'dropping the rim mid-turn would blink the one box on the strip',
      );

      await endTurn(tester, notifier);
    });

    testWidgets('refuses the pointer rather than going inert', (tester) async {
      // A rimmed, captioned pill that answers with a plain arrow reads as a dead control. The
      // other disabled states drop the rim, so `basic` is already honest for them.
      final notifier = await pumpBusyMenu(tester);
      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).disabledCursor,
        isNull,
      );

      await startTurn(tester, notifier);

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).disabledCursor,
        SystemMouseCursors.forbidden,
      );

      await endTurn(tester, notifier);
    });

    testWidgets('unlocks itself when the turn ends', (tester) async {
      // The regression this guards: nothing in the pane header listens to the notifier, so a pill
      // built from turn state latches at whatever it was built with. Without a ListenableBuilder on
      // the notifier this control stays disabled for the rest of the session.
      final notifier = await pumpBusyMenu(tester);
      await startTurn(tester, notifier);
      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).onTap,
        isNull,
      );

      await endTurn(tester, notifier);

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).onTap,
        isNotNull,
        reason: 'the control must reopen on its own when the turn finishes',
      );
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    });

    testWidgets('a standing refusal outranks the turn', (tester) async {
      // An engine that can never use a grid says so whether or not it is mid-turn: an hourglass
      // there would promise a wait that never resolves.
      final notifier = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
      addTearDown(notifier.dispose);
      notifier.machineStates['m1'] =
          MachineState(
              const Machine(
                machineId: 'm1',
                apiKey: '',
                authMode: MachineAuthMode.remote,
                name: 'm1',
                status: 'online',
              ),
            )
            ..agents = [
              const Agent(
                id: 'a1',
                name: 'a1',
                engine: 'gemini',
                status: 'active',
              ),
            ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AgentModelMenu(
                notifier: notifier,
                machineId: 'm1',
                agentId: 'a1',
                engine: 'gemini',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await startTurn(tester, notifier);

      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        endsWith('gemini cannot use a grid'),
        reason: 'the condition the user can act on is the one worth naming',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).disabledCursor,
        isNull,
        reason:
            'forbidden promises a wait; this refusal does not end on its own',
      );

      await endTurn(tester, notifier);
    });
  });
}
