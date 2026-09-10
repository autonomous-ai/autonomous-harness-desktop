import 'dart:async';

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
  _Profiles([
    Iterable<String> initialPaths = const [
      '/accounts/codex1',
      '/accounts/codex2',
    ],
  ]) : paths = {...initialPaths};

  final Set<String> paths;
  final extraPaths = <String>{};
  Completer<void>? pending;
  @override
  Future<List<LocalCodexProfile>> load({
    Set<String> observedPaths = const {},
  }) async {
    await pending?.future;
    return [
      for (final path in {...paths, ...observedPaths, ...extraPaths})
        LocalCodexProfile(path),
    ];
  }
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
  void replaceAgents(String machineId, List<Agent> agents) {
    machineStates[machineId]!.agents = agents;
    notifyListeners();
  }

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
    _Profiles? profiles,
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
                codexProfiles: profiles ?? _Profiles(),
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

  testWidgets('no profiles hides the picker and keeps a default launch', (
    tester,
  ) async {
    final notifier = await open(tester, profiles: _Profiles([]));
    expect(
      find.byKey(const Key('new-agent-codex-profile-field')),
      findsNothing,
    );
    expect(find.text('Codex profile'), findsNothing);
    expect(find.text('Link a profile folder…'), findsOneWidget);
    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
    await tester.pumpAndSettle();
    expect(notifier.calls.single['codexHome'], isNull);
  });

  testWidgets('one profile is used automatically without a picker', (
    tester,
  ) async {
    final notifier = await open(
      tester,
      profiles: _Profiles(['/custom/work-login']),
    );
    expect(
      find.byKey(const Key('new-agent-codex-profile-field')),
      findsNothing,
    );
    expect(find.text('Codex profile'), findsNothing);
    expect(find.text('/custom/work-login'), findsOneWidget);
    expect(find.text('Link a profile folder…'), findsOneWidget);
    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
    await tester.pumpAndSettle();
    expect(notifier.calls.single['codexHome'], '/custom/work-login');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picker appears at two profiles and hides again at one', (
    tester,
  ) async {
    final profiles = _Profiles(['/accounts/codex1']);
    await open(tester, profiles: profiles);
    expect(
      find.byKey(const Key('new-agent-codex-profile-field')),
      findsNothing,
    );
    profiles.paths.add('/accounts/codex2');
    await tester.tap(find.byTooltip('Refresh profiles'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('new-agent-codex-profile-field')),
      findsOneWidget,
    );
    expect(find.text('/accounts/codex1'), findsOneWidget);
    await selectSecond(tester);
    profiles.paths.remove('/accounts/codex1');
    await tester.tap(find.byTooltip('Refresh profiles'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('new-agent-codex-profile-field')),
      findsNothing,
    );
    expect(find.text('/accounts/codex2'), findsOneWidget);
  });

  testWidgets('creation waits for discovery to select the single account', (
    tester,
  ) async {
    final profiles = _Profiles(['/custom/work-login'])
      ..pending = Completer<void>();
    final notifier = await open(tester, profiles: profiles);
    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    final createButton = find.widgetWithText(FilledButton, 'Create agent');
    expect(tester.widget<FilledButton>(createButton).onPressed, isNull);
    expect(notifier.calls, isEmpty);
    profiles.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(createButton).onPressed, isNotNull);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(notifier.calls.single['codexHome'], '/custom/work-login');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing selection requires an explicit account change', (
    tester,
  ) async {
    final profiles = _Profiles();
    final notifier = await open(tester, profiles: profiles);
    await selectSecond(tester);
    profiles.paths.remove('/accounts/codex2');
    await tester.tap(find.byTooltip('Refresh profiles'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('new-agent-codex-profile-field')),
      findsNothing,
    );
    expect(find.text('/accounts/codex2'), findsOneWidget);
    await tester.tap(find.text('Use codex1'));
    await tester.pumpAndSettle();
    expect(find.text('/accounts/codex1'), findsOneWidget);
    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
    await tester.pumpAndSettle();
    expect(notifier.calls.single['codexHome'], '/accounts/codex1');
  });

  testWidgets('refresh preserves an explicitly chosen default launch', (
    tester,
  ) async {
    final profiles = _Profiles();
    final notifier = await open(tester, profiles: profiles);
    await selectSecond(tester);
    await tester.tap(find.byKey(const Key('new-agent-codex-profile-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default').last);
    await tester.pumpAndSettle();
    profiles.paths.remove('/accounts/codex2');
    await tester.tap(find.byTooltip('Refresh profiles'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('new-agent-codex-profile-field')),
      findsNothing,
    );
    expect(find.text('/accounts/codex1'), findsNothing);
    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
    await tester.pumpAndSettle();
    expect(notifier.calls.single['codexHome'], isNull);
  });

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

  testWidgets(
    'discovers newly observed local profiles while ignoring remote machine paths',
    (tester) async {
      final notifier = await open(tester);
      notifier.machineStates['remote'] =
          MachineState(
              const Machine(
                machineId: 'remote',
                authMode: MachineAuthMode.remote,
              ),
            )
            ..agents = [
              Agent.fromJson({
                'id': 'remote-agent',
                'engine': 'codex',
                'codexHome': '/remote/private-account',
              }),
            ];
      notifier.replaceAgents('machine', [
        Agent.fromJson({
          'id': 'local-agent',
          'engine': 'codex',
          'codexHome': '/unusual/location/work-login',
        }),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-agent-codex-profile-field')));
      await tester.pumpAndSettle();
      expect(find.text('work-login'), findsOneWidget);
      expect(find.text('private-account'), findsNothing);
      await tester.tap(find.text('work-login'));
      await tester.pumpAndSettle();
      expect(find.text('/unusual/location/work-login'), findsOneWidget);
    },
  );

  testWidgets(
    'refresh discovers an added profile and keeps the current selection',
    (tester) async {
      final profiles = _Profiles();
      await open(tester, profiles: profiles);
      await selectSecond(tester);
      profiles.extraPaths.add('/elsewhere/new-profile');
      await tester.tap(find.byTooltip('Refresh profiles'));
      await tester.pumpAndSettle();
      expect(find.text('/accounts/codex2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('new-agent-codex-profile-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('new-profile'));
      await tester.pumpAndSettle();
      expect(find.text('/elsewhere/new-profile'), findsOneWidget);
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
