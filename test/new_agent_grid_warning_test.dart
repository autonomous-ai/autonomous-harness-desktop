// The New agent dialog is the last screen before a launch that the CLI may refuse,
// so it is where "this engine cannot use the grid you picked" has to be readable —
// and where the button has to stop, rather than send a frame that only ever comes
// back as an error the user was already shown.
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
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

/// Stands in for the CLI round trip `createAgent` normally makes, so a test can drive a real
/// Create click and inspect exactly what payload it built — the same shape
/// `ReloadTrackingNotifier` (machine_tree_widget_test.dart) uses for its own notifier calls.
/// `listRemoteFolder` is faked too, so the in-app folder browser this dialog opens for a remote
/// machine never reaches `fs_list_dir` for real.
class RecordingCreateAgentNotifier extends AppNotifier {
  RecordingCreateAgentNotifier()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );

  bool createAgentCalled = false;
  GridAgentOverride? lastGrid;

  @override
  Future<Map<String, dynamic>> listRemoteFolder(
    String machineId,
    String? path,
  ) async {
    return {'path': '/tmp/agent-folder', 'entries': <dynamic>[]};
  }

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    bool bypassPermission = false,
    GridAgentOverride? grid,
    String? codexHome,
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

  // The system panel cannot open in a widget test, so the platform is swapped
  // for one that answers with a fixed path — enough to exercise everything the
  // dialog does with the answer.
  const pickedFolder = '/Users/macbookpro/Desktop/A';
  setUp(() => FileSelectorPlatform.instance = _StubFileSelector(pickedFolder));

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
              onPressed: () => showNewAgentDialog(
                context,
                notifier,
                'machine-1',
                source: 'machine_row',
              ),
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
    await tester.tap(find.text(engine == 'codex' ? 'Codex' : 'Cursor').last);
    await tester.pumpAndSettle();
  }

  final warning = find.textContaining('cannot be pointed at a grid');
  Finder createButton() => find.widgetWithText(FilledButton, 'Create agent');

  /// A grid sitting in the store as this computer's default provider — the
  /// state every test below is checking the dialog now IGNORES.
  const defaultProvider = GridSelection(
    networkId: 'grid-3378218621364f16',
    networkName: 'autonomous.ai',
  );

  testWidgets('the summary names the engine\'s own login, whatever the '
      'default provider is', (tester) async {
    gridSelectionStore.value = defaultProvider;
    await openDialog(tester, engine: 'claude');
    // The same two lines the sidebar's provider pill and the agent's model menu
    // use for this state — not a third wording of its own.
    expect(find.text(kNoGridTargetLabel), findsOneWidget);
    expect(find.text(kNoGridTargetDetail), findsOneWidget);
    // And emphatically NOT the grid, which is what this line used to read.
    expect(find.textContaining('autonomous.ai'), findsNothing);
  });

  // The note beside an engine's name, which appeared for an engine the CLI
  // would refuse to point at the chosen grid. No launch from here goes to a
  // grid any more, so no engine can be refused for one.
  final gridNote = find.text('grid not supported');

  testWidgets('no engine is marked for a grid it cannot reach', (tester) async {
    // ⚠️ The grid IS chosen here. That is the point: the note used to depend on
    // this store, and now nothing on this screen does.
    gridSelectionStore.value = defaultProvider;
    await openDialog(tester, engine: 'cursor');
    expect(gridNote, findsNothing);
    expect(find.text('no grid'), findsNothing);
    expect(warning, findsNothing);
  });

  testWidgets('an engine the CLI would refuse a grid can still be launched', (
    tester,
  ) async {
    // Cursor is outside kGridCapableEngines, and with a grid chosen the Create
    // button used to be dead — the dialog knew the CLI would refuse. There is
    // no grid to refuse now, so the only thing standing between this engine and
    // a launch is the folder.
    gridSelectionStore.value = defaultProvider;
    // On this computer, so Browse… reaches the stubbed OS panel rather than the
    // in-app remote browser, which would want an `fs_list_dir` this notifier
    // does not fake.
    await openDialog(tester, engine: 'cursor', thisComputer: true);
    expect(tester.widget<FilledButton>(createButton()).onPressed, isNull);

    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(createButton()).onPressed,
      isNotNull,
      reason: 'a folder is the only thing this engine was ever missing',
    );
  });

  testWidgets('offers no model to pick', (tester) async {
    // The model is chosen per agent AFTER it is running, from the agent view's
    // header menu — which is also the only place a grid is chosen now. A
    // control here would be a second door onto the same setting, open at the
    // one moment there is no agent to apply it to.
    gridSelectionStore.value = defaultProvider;
    await openDialog(tester, engine: 'claude');
    expect(find.byKey(const Key('new-agent-model-field')), findsNothing);
    expect(find.text('Model'), findsNothing);
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
    expect(
      find.textContaining('--dangerously-skip-permissions'),
      findsOneWidget,
    );

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

  testWidgets('a chosen folder starts at the control\'s left edge', (
    tester,
  ) async {
    // The path used to be laid out RTL so it would ellipsize from its head, but
    // direction drives alignment too: the string was shoved to the trailing edge
    // and left a hole after the folder glyph, worst for the SHORT paths that
    // needed no truncation at all.
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'claude', thisComputer: true);
    await tester.tap(find.text('Choose a folder…'));
    await tester.pumpAndSettle();

    // Scoped to the control: the summary states the same path in its own column.
    final icon = find.byIcon(Icons.folder_outlined);
    final path = find.descendant(
      of: find.byKey(const Key('new-agent-folder-text')),
      matching: find.byType(Text),
    );
    expect(path, findsOneWidget);
    // Whole or trimmed from the head — never from the tail, which would drop the
    // only segment that identifies the folder. (Whether THIS path needs trimming
    // is a question about font metrics, and a widget test runs without SF Mono.)
    expect(tester.widget<Text>(path).data, endsWith('Desktop/A'));
    expect(tester.widget<Text>(path).textDirection, isNot(TextDirection.rtl));

    // Flush against the glyph beside it, not floating off to the right.
    expect(
      tester.getTopLeft(path).dx - tester.getBottomRight(icon).dx,
      lessThan(12),
    );
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

  testWidgets('creates the agent with no grid on the wire at all', (
    tester,
  ) async {
    // ⚠️ THE test for this whole change. A grid is the default provider, and
    // the frame that reaches the CLI must carry none: `grid: null` is the frame
    // this app sent before grids existed, and it is the frame every Create
    // sends now. The agent runs on whatever login the engine already has here.
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
                source: 'machine_row',
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

    await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
    await tester.pumpAndSettle();

    expect(notifier.createAgentCalled, isTrue);
    expect(
      notifier.lastGrid,
      isNull,
      reason: 'the default provider is not where a new agent launches',
    );
  });

  test('the grid-capable list matches what the CLI will accept', () {
    // Mirrors GRID_ENGINE_CONTRACTS in autonomous-harness/cli/src/lib/gridLaunch.ts, which has the
    // same assertion on its own side. This dialog no longer reads it — every launch from here is
    // the engine's own login — but `AgentModelMenu` does, and that is where an engine that cannot
    // be pointed at a grid is now refused.
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

/// Stands in for the OS folder panel, which a widget test cannot open.
class _StubFileSelector extends FileSelectorPlatform {
  _StubFileSelector(this.path);

  final String path;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => path;
}
