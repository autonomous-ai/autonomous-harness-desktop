import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/codex_profiles.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/grid/grid_agent_override.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/new_agent_dialog.dart';

class _Profiles extends LocalCodexProfiles {
  @override
  Future<List<LocalCodexProfile>> load() async => const [
    LocalCodexProfile('/accounts/codex1'),
    LocalCodexProfile('/accounts/codex2'),
  ];
}

class _Folders extends FileSelectorPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => '/work';
}

class _Notifier extends AppNotifier {
  _Notifier()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );
  final calls = <Map<String, Object?>>[];
  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {}
  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    bool bypassPermission = false,
    GridAgentOverride? grid,
    String? codexHome,
  }) async {
    if (codexHome != null && !stateOf(machineId)!.isLocalMachine) {
      return super.createAgent(
        machineId,
        engine: engine,
        folder: folder,
        codexHome: codexHome,
      );
    }
    calls.add({'engine': engine, 'codexHome': codexHome, 'folder': folder});
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final priorSelection = gridSelectionStore.value;
  late FileSelectorPlatform priorFiles;
  setUp(() {
    gridSelectionStore.value = GridSelection.none;
    priorFiles = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _Folders();
  });
  tearDown(() {
    gridSelectionStore.value = priorSelection;
    FileSelectorPlatform.instance = priorFiles;
  });

  Future<_Notifier> open(
    WidgetTester tester, {
    bool local = true,
    bool supported = true,
  }) async {
    final notifier = _Notifier();
    addTearDown(notifier.dispose);
    notifier.machineStates['machine'] =
        MachineState(
            const Machine(
              machineId: 'machine',
              name: 'This Mac',
              authMode: MachineAuthMode.remote,
            ),
          )
          ..localOnly = local
          ..engines.replace([
            EngineAvailability(
              engine: 'codex',
              installed: true,
              supportsCodexHome: supported,
            ),
          ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showNewAgentDialog(
                context,
                notifier,
                'machine',
                source: 'machine_row',
                codexProfiles: _Profiles(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-agent-engine-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex').last);
    await tester.pumpAndSettle();
    return notifier;
  }

  Future<void> selectSecond(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('new-agent-codex-profile-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('codex2').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'creates with the selected account and shows its full path before the click',
    (tester) async {
      final notifier = await open(tester);
      await selectSecond(tester);
      expect(find.text('/accounts/codex2'), findsOneWidget);
      await tester.tap(find.text('Browse…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
      await tester.pumpAndSettle();
      expect(notifier.calls, [
        {'engine': 'codex', 'codexHome': '/accounts/codex2', 'folder': '/work'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing engines clears the selected account', (tester) async {
    final notifier = await open(tester);
    await selectSecond(tester);
    await tester.tap(find.byKey(const Key('new-agent-engine-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('new-agent-codex-profile-field')),
      findsNothing,
    );
    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
    await tester.pumpAndSettle();
    expect(notifier.calls.single['codexHome'], isNull);
    expect(notifier.calls.single['engine'], 'claude');
  });

  testWidgets(
    'a target becoming remote refuses the selected profile without a default launch',
    (tester) async {
      final notifier = await open(tester);
      await selectSecond(tester);
      await tester.tap(find.text('Browse…'));
      await tester.pumpAndSettle();
      notifier.stateOf('machine')!.localOnly = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
      await tester.pumpAndSettle();
      expect(notifier.calls, isEmpty);
      expect(
        find.text(
          'Choose a local Codex profile only for Codex on this computer’s own account',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an old CLI keeps the normal launch available and explains profile support',
    (tester) async {
      final notifier = await open(tester, supported: false);
      expect(
        find.byKey(const Key('new-agent-codex-profile-field')),
        findsNothing,
      );
      expect(
        find.text('Update Harness CLI to choose a local Codex profile.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Browse…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
      await tester.pumpAndSettle();
      expect(notifier.calls.single['codexHome'], isNull);
    },
  );

  testWidgets(
    'never offers this computer’s account folders for a remote machine',
    (tester) async {
      await open(tester, local: false);
      expect(
        find.byKey(const Key('new-agent-codex-profile-field')),
        findsNothing,
      );
      expect(find.text('Link a profile folder…'), findsNothing);
    },
  );
}
