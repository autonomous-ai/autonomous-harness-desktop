// What this control says IS what the user knows about where their tokens go, so the three states it
// can be in are the feature from where they sit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/grid/grid_models_controller.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/shared/widgets/skeleton.dart';
import 'package:harness/shared/widgets/toolbar_pill.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/agent_model_menu.dart';

const kRelay = 'https://grid.autonomous.ai/grid-abc/relay';
const kNetworkId = 'grid-live';

void main() {
  test('an agent with no grid is on its own login', () {
    expect(agentModelLabel(null), 'Own login');
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

  group('an already-open menu', () {
    // Fix-round regression: a PopupMenuButton's itemBuilder is a one-shot snapshot handed to
    // showMenu() before the tap that triggers a load even finishes — so a menu opened on an
    // unloaded network showed only "Own login"/"Auto" until closed and reopened, and could show a
    // PREVIOUSLY-selected grid's models under the new grid's name. AgentModelMenu is now built on
    // MenuAnchor + a ListenableBuilder on gridModelsController specifically so the OPEN panel
    // updates live as the controller moves Loading -> Ready — this test drives that same
    // transition with GridModelsController.debugSetState (a test-only seam) rather than a real,
    // non-deterministic network round trip, and would fail against the old PopupMenuButton
    // implementation: nothing there re-invoked itemBuilder once the route was already showing.
    final beforeSelection = gridSelectionStore.value;

    setUp(() {
      gridSelectionStore.value = const GridSelection(
        networkId: kNetworkId,
        networkName: 'Live Grid',
      );
      gridModelsController.debugSetState(kNetworkId, const GridModelsLoading());
    });

    tearDown(() {
      gridSelectionStore.value = beforeSelection;
      gridModelsController.debugSetState(kNetworkId, const GridModelsIdle());
    });

    testWidgets(
      'picks up the grid\'s models as they load, with no close/reopen',
      (tester) async {
        final notifier = AppNotifier(
          config: AppConfig.dev,
          authSession: AuthSession(),
          configStore: null,
        );
        addTearDown(notifier.dispose);
        // A model pinned so the trigger's own label ("Pinned-Model") cannot collide with either
        // menu row this test looks for.
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

        await tester.tap(find.text('Pinned-Model'));
        await tester.pumpAndSettle();

        // Opened while gridModelsController is still Loading for this network.
        expect(find.text('Loading models…'), findsOneWidget);
        expect(find.text('GLM-4.7-Flash'), findsNothing);

        // The load finishes — WITHOUT closing the menu.
        gridModelsController.debugSetState(
          kNetworkId,
          const GridModelsReady(['GLM-4.7-Flash']),
        );
        await tester.pump();

        expect(
          find.text('Loading models…'),
          findsNothing,
          reason: 'the open panel must drop the loading row once models arrive',
        );
        expect(
          find.text('GLM-4.7-Flash'),
          findsOneWidget,
          reason: 'the open panel must show the newly-loaded model without a reopen',
        );
      },
    );
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
      gridModelsController.debugSetState(
        kNetworkId,
        const GridModelsReady(['GLM-4.7-Flash']),
      );
    });

    tearDown(() {
      gridSelectionStore.value = beforeSelection;
      gridModelsController.debugSetState(kNetworkId, const GridModelsIdle());
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
      gridModelsController.debugSetState(
        kNetworkId,
        const GridModelsReady(['GLM-4.7-Flash']),
      );
    });

    tearDown(() {
      gridSelectionStore.value = beforeSelection;
      gridModelsController.debugSetState(kNetworkId, const GridModelsIdle());
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
          tester.widget<Text>(find.text('Pinned-Model')).style?.color,
          ToolbarPill.tint(tinted: false, enabled: true),
          reason: 'textFaint on the header ground is ~2.6:1 — under the 4.5:1 floor',
        );
      },
    );

    testWidgets(
      'an engine with no grid loses the chevron, not the model name',
      (tester) async {
        // 'gemini' is outside kGridCapableEngines: the control still has to REPORT the model, but a
        // chevron there would promise a menu that never opens.
        await pumpMenu(tester, engine: 'gemini');

        expect(find.text('Pinned-Model'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
        expect(
          tester.widget<ToolbarPill>(find.byType(ToolbarPill)).onTap,
          isNull,
        );
      },
    );

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

    testWidgets('the pill stays lit while its own menu is open', (
      tester,
    ) async {
      // MenuAnchor exposes no state for this, so the widget tracks it: without it the pill drops
      // its fill as soon as the pointer leaves the button for the list it just opened.
      await pumpMenu(tester, engine: 'claude');

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).active,
        isFalse,
      );

      await tester.tap(find.text('Pinned-Model'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ToolbarPill>(find.byType(ToolbarPill)).active,
        isTrue,
        reason: 'the trigger must not go quiet under its own open panel',
      );
    });
  });
}
