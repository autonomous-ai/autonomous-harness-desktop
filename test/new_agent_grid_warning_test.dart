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
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex').last);
    await tester.pumpAndSettle();
  }

  final warning = find.textContaining('cannot be pointed at a grid');

  testWidgets('says nothing about grids when none is picked', (tester) async {
    gridSelectionStore.value = GridSelection.none;
    await openDialog(tester, engine: 'codex');
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
    await openDialog(tester, engine: 'codex');
    expect(warning, findsOneWidget);
    // The warning is only useful if it says what to do instead.
    expect(find.textContaining('Claude Code'), findsWidgets);
  });

  test('the grid-capable list matches what the CLI will accept', () {
    // Mirrors GRID_ENGINE_ENV in autonomous-harness/cli/src/lib/gridLaunch.ts.
    expect(kGridCapableEngines, {'claude'});
  });
}
