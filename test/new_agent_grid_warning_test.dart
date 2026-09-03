// The New agent dialog is the last screen before a launch that the CLI may refuse,
// so it is where "this engine cannot use the grid you picked" has to be readable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/grid/grid_agent_override.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/new_agent_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The dialog reads the app-wide singleton, so a test that leaves a grid behind
  // would change what every later test sees.
  final before = gridSelectionStore.value;
  tearDown(() => gridSelectionStore.value = before);

  Future<void> openDialog(WidgetTester tester, {required String engine}) async {
    final notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    addTearDown(notifier.dispose);
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
    await tester.tap(find.text('Cursor').last);
    await tester.pumpAndSettle();
  }

  final warning = find.textContaining('cannot be pointed at a grid');

  testWidgets('says nothing about grids when none is picked', (tester) async {
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'cursor');
    expect(find.textContaining("This engine's own login"), findsOneWidget);
    expect(warning, findsNothing);
  });

  testWidgets('names the grid for an engine that can reach it', (tester) async {
    gridSelectionStore.value = const GridSelection(
      networkId: 'grid-3378218621364f16',
      networkName: 'autonomous.ai',
      model: 'GLM-4.7-Flash',
    );
    await openDialog(tester, engine: 'claude');
    expect(find.text('autonomous.ai · GLM-4.7-Flash'), findsOneWidget);
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
    expect(find.textContaining('choose another engine'), findsOneWidget);
    expect(find.textContaining('clear the grid'), findsOneWidget);
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
