// The New agent dialog is the last screen before a launch that the CLI may refuse,
// so it is where "this engine cannot use the grid you picked" has to be readable —
// and where the button has to stop, rather than send a frame that only ever comes
// back as an error the user was already shown.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/grid_agent_override.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/shared/widgets/app_checkbox.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/new_agent_dialog.dart';

import 'support/fake_grid_api.dart';

/// Stands in for the CLI round trip `createAgent` normally makes, so a test can drive a real
/// Create click and inspect exactly what payload it built — the same shape
/// `ReloadTrackingNotifier` (machine_tree_widget_test.dart) uses for its own notifier calls.
/// `listRemoteFolder` is faked too, so the in-app folder browser this dialog opens for a remote
/// machine never reaches `fs_list_dir` for real.
class RecordingCreateAgentNotifier extends AppNotifier {
  RecordingCreateAgentNotifier()
    : super(config: AppConfig.dev, authSession: AuthSession(), configStore: null);

  bool createAgentCalled = false;
  GridAgentOverride? lastGrid;

  @override
  Future<Map<String, dynamic>> listRemoteFolder(String machineId, String? path) async {
    return {'path': '/tmp/agent-folder', 'entries': <dynamic>[]};
  }

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    bool bypassPermission = false,
    GridAgentOverride? grid,
  }) async {
    createAgentCalled = true;
    lastGrid = grid;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The dialog reads the app-wide singleton, so a test that leaves a grid behind
  // would change what every later test sees.
  final before = gridSelectionStore.value;
  tearDown(() => gridSelectionStore.value = before);

  const machine = Machine(
    machineId: 'machine-1',
    authMode: MachineAuthMode.remote,
    name: 'Mac mini M4',
  );

  /// Opens the dialog for a machine the app knows about.
  ///
  /// [thisComputer] is what decides which folder picker the dialog reaches for,
  /// so it is set the way `_refreshMachines` sets it — on the state, not passed
  /// to the widget.
  Future<void> openDialog(
    WidgetTester tester, {
    required String engine,
    bool thisComputer = false,
  }) async {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
    notifier.machineStates['machine-1'] = MachineState(machine)
      ..localOnly = thisComputer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showNewAgentDialog(context, notifier, 'machine-1'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (engine == 'claude') return;
    await tester.tap(find.byKey(const Key('new-agent-engine-field')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(engine == 'codex' ? 'Codex' : 'Cursor').last,
    );
    await tester.pumpAndSettle();
  }

  final warning = find.textContaining('cannot be pointed at a grid');
  Finder createButton() => find.widgetWithText(FilledButton, 'Create agent');

  testWidgets('says nothing about grids when none is picked', (tester) async {
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'cursor');
    // The summary still has to answer "on whose account", and with no grid the
    // honest answer is the engine's own login.
    expect(find.textContaining("Cursor's own login"), findsOneWidget);
    expect(warning, findsNothing);
  });

  testWidgets('names the grid for an engine that can reach it', (tester) async {
    // GridSelection.model is a leftover from the single global setting this
    // dialog's own MODEL field replaces (see new_agent_dialog.dart) — the
    // summary reads the dialog's state, never the store's, so the model the
    // summary names here is the dialog's own default: Auto.
    gridSelectionStore.value = const GridSelection(
      networkId: 'grid-3378218621364f16',
      networkName: 'autonomous.ai',
    );
    await openDialog(tester, engine: 'claude');
    expect(find.text('autonomous.ai · Auto'), findsOneWidget);
    expect(warning, findsNothing);
  });

  testWidgets('warns before the CLI refuses, and names the way out', (
    tester,
  ) async {
    gridSelectionStore.value = const GridSelection(
      networkId: 'grid-3378218621364f16',
      networkName: 'autonomous.ai',
    );
    await openDialog(tester, engine: 'cursor');
    expect(warning, findsOneWidget);
    // The warning is only useful if it says what to do instead. It no longer names one engine:
    // six can reach a grid now, and the picker right above it is the list.
    // Case-insensitive: the sentence has moved between the middle of a paragraph
    // and the start of one, and that is not what this test is about.
    expect(
      find.textContaining(RegExp('choose another engine', caseSensitive: false)),
      findsOneWidget,
    );
    expect(find.textContaining('clear the grid'), findsOneWidget);
  });

  testWidgets('a refused engine cannot be launched at all', (tester) async {
    // The whole point of warning early. Before this the button stayed live, so
    // the user got the warning AND the round trip to a CLI that refuses.
    gridSelectionStore.value = const GridSelection(
      networkId: 'grid-3378218621364f16',
      networkName: 'autonomous.ai',
    );
    await openDialog(tester, engine: 'cursor');
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);
  });

  testWidgets('the summary states which machine, and whether it is this one', (
    tester,
  ) async {
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'claude', thisComputer: true);
    expect(find.text('New agent on Mac mini M4'), findsOneWidget);
    // The name and its qualifier are two lines, not one string: a long hostname
    // filled the column and then wrapped mid-name.
    expect(find.text('Mac mini M4'), findsOneWidget);
    expect(find.text('this computer'), findsOneWidget);
  });

  // On this computer the OS panel is what everyone expects, so saying so is
  // noise. On another machine the in-app browser is the surprising half — that
  // is the half that has to speak, because a native panel there would hand back
  // a path that does not exist on the machine the agent actually runs on.
  final browsingNote = find.textContaining('is another computer');

  testWidgets('this computer says nothing about where it browses', (
    tester,
  ) async {
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'claude', thisComputer: true);
    expect(browsingNote, findsNothing);
    expect(find.text('remote'), findsNothing);
  });

  testWidgets('a remote machine says the folders are not this Mac\'s', (
    tester,
  ) async {
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'claude');
    expect(browsingNote, findsOneWidget);
    expect(find.text('remote'), findsOneWidget);
  });

  testWidgets('the ticked flag is what shows up in the command', (
    tester,
  ) async {
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'claude');
    // Unticked, the summary must not claim a flag that will not be passed.
    expect(find.textContaining('--dangerously-skip-permissions'), findsOneWidget);

    await tester.tap(find.text('Bypass permission prompts'));
    await tester.pumpAndSettle();
    // Now twice: the checkbox's own detail line, and the command it joins.
    expect(
      find.textContaining('--dangerously-skip-permissions'),
      findsNWidgets(2),
    );
  });

  testWidgets('no control in the dialog wears a rim', (tester) async {
    // §1: depth in this app comes from fill and shadow, and the one border it
    // allows belongs to the menu panel (see AppMenu's note). The summary card
    // had one, including in its refused state, where a 45%-opacity hairline
    // read in dark and looked unfinished in light.
    gridSelectionStore.value = const GridSelection(
      networkId: 'grid-3378218621364f16',
      networkName: 'autonomous.ai',
    );
    await openDialog(tester, engine: 'cursor');
    final dialog = find.byType(AlertDialog);
    final boxes = tester
        .widgetList<Container>(
          find.descendant(of: dialog, matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    // A Container may carry a top-edge rule (the refusal's divider); what is
    // banned is a box drawn all the way round.
    expect(boxes.where((d) => d.border?.isUniform == true), isEmpty);
  });

  testWidgets('hoverable rows warm up on the app\'s own timing', (
    tester,
  ) async {
    // Every hoverable surface in this app is a MouseRegion + AnimatedContainer
    // on AppMotion.hover — not an InkWell, whose ripple is a phone idiom and
    // whose hover is instant.
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'claude');

    // Asserted on the two rows this file owns rather than on the whole subtree:
    // Material's own buttons each build an InkWell, and so does AppMenu, and
    // neither is this dialog's to change.
    for (final label in const [
      'Choose a folder',
      'Bypass permission prompts',
    ]) {
      final row = find
          .ancestor(
            of: find.textContaining(label),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      expect(
        tester.widget<AnimatedContainer>(row).duration,
        AppMotion.hover,
        reason: '"$label" should warm up on the app\'s hover timing',
      );
      expect(
        find.ancestor(of: row, matching: find.byType(InkWell)),
        findsNothing,
        reason: '"$label" should not be built on an InkWell',
      );
    }
  });

  testWidgets('the summary never dresses itself up as a runnable command', (
    tester,
  ) async {
    // The flag sits on its own indented line, but WITHOUT a `\` continuation:
    // the CLI builds the real command — working directory, tmux session, grid
    // environment — none of which this string shows. A shell's continuation
    // mark would invite someone to copy a line that does not run.
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'claude');
    await tester.tap(find.text('Bypass permission prompts'));
    await tester.pumpAndSettle();

    // The command block, not the flag's own line under the checkbox — both are
    // mono, and only the command carries a shell prompt.
    final cmd = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .firstWhere((text) => text.startsWith('\$ '));
    // Claude's flag fits beside its engine, so it stays on one line — breaking
    // it to match Codex would leave most of the card's width empty.
    expect(cmd, '\$ claude --dangerously-skip-permissions');
    expect(cmd, isNot(contains('\\')));
  });

  testWidgets('a flag too long to sit beside its engine drops below it', (
    tester,
  ) async {
    // Codex is the only engine whose flag cannot fit on one line, so it is the
    // only one that should break — the branch has to be exercised by the engine
    // that actually takes it, not asserted in the abstract.
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'codex');
    await tester.tap(find.text('Bypass permission prompts'));
    await tester.pumpAndSettle();

    final cmd = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .firstWhere((text) => text.startsWith('\$ '));
    expect(cmd, '\$ codex\n  --dangerously-bypass-approvals-and-sandbox');
  });

  test('every flag fits the summary, on one line or on its own', () {
    // Asserted arithmetically, not by laying the strings out: a widget test runs
    // without SF Mono and its stand-in font is ~70% wider per character, so a
    // TextPainter here measures the test harness, not the app.
    const advance = 12 * 0.6;
    for (final entry in kEngineBypassPermissionFlag.entries) {
      final oneLine = '\$ ${entry.key} ${entry.value}';
      if (oneLine.length * advance <= summaryContentWidth) continue;
      // It did not fit beside its engine, so it drops to its own indented line —
      // and there it must fit, or it breaks mid-word inside the flag, which is
      // the one string here that has to be read whole before someone decides to
      // turn an engine's guardrails off.
      expect(
        ('  ${entry.value}'.length) * advance,
        lessThanOrEqualTo(summaryContentWidth),
        reason: '${entry.value} overruns even on its own line',
      );
    }
  });

  testWidgets('the tick box is the app\'s own, not raw Material', (
    tester,
  ) async {
    // Material's Checkbox lays a CIRCULAR ink overlay over its square box on
    // hover, focus and press — a round wash bleeding past the corners of the
    // thing it belongs to. Same reason AppIconButton exists.
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'claude');
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(AppCheckbox), findsOneWidget);
  });

  testWidgets('creates the agent with the model the user picked', (tester) async {
    // Auto is the default, and Auto means "no model on the wire" — the grid's own choice, which is
    // not the same as pinning a model named Auto.
    gridSelectionStore.value = const GridSelection(
      networkId: 'grid-abc',
      networkName: 'autonomous.ai',
    );
    final notifier = RecordingCreateAgentNotifier();
    addTearDown(notifier.dispose);
    notifier.machineStates['machine-1'] = MachineState(machine);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showNewAgentDialog(
                context,
                notifier,
                'machine-1',
                // A fake client, so the relay key this default (Auto) path still mints goes
                // nowhere near the network — see resolveGridAgentOverride and FakeGridApi.
                gridApiClient: FakeGridApi(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // This machine is not `thisComputer`, so Browse… opens the in-app remote picker rather than
    // reaching for a native panel this test harness has no plugin for.
    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Select this folder'));
    await tester.pumpAndSettle();

    // The model field defaults to Auto — nothing tapped here — so Create should carry that
    // straight through.
    await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
    await tester.pumpAndSettle();

    expect(notifier.createAgentCalled, isTrue);
    final grid = notifier.lastGrid;
    expect(grid, isNotNull);
    expect(grid!.model, isNull, reason: 'Auto pins no model');
    expect(
      grid.toJson().containsKey('model'),
      isFalse,
      reason: 'Auto means the key is left off the wire entirely, not sent as null',
    );
  });

  test('the grid-capable list matches what the CLI will accept', () {
    // Mirrors GRID_ENGINE_CONTRACTS in autonomous-harness/cli/src/lib/gridLaunch.ts, which has the
    // same assertion on its own side. Drifting apart costs a warning that never appears, or one
    // that appears for an engine that would have worked.
    expect(kGridCapableEngines, {
      'claude',
      'codex',
      'copilot',
      'grok',
      'hermes',
      'opencode',
      'pi',
    });
  });
}
