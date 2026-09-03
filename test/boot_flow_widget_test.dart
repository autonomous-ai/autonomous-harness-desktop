import 'package:harness/auth/auth_session.dart';
import 'package:harness/auth/cli_login.dart';
import 'package:harness/bootstrap/environment_provisioner.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/main.dart';
import 'package:harness/settings/config_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/terminal_pane.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:harness/update/desktop_updater.dart';
import 'package:harness/update/manual_update_check.dart';
import 'package:harness/widgets/update_notice.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Builds an AppNotifier without touching persisted state or the network:
/// status is set directly, so bootstrap/login (which call platform
/// channels and the network) never run.
AppNotifier makeNotifier(AppStatus status) {
  final app = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
  );
  app.status = status;
  app.currentUser = const CurrentUserProfile(
    id: 'user-1',
    name: 'Diego',
    email: 'diego@autonomous.ai',
  );
  return app;
}

/// bootstrap() now asks the CLI (not AuthSession) whether this computer is signed in — this fake
/// avoids ever shelling out to a real `harness` binary from a unit test.
class _FakeCliLogin extends CliLogin {
  final bool loggedIn;
  _FakeCliLogin({this.loggedIn = false});

  @override
  Future<CliAuthStatus> checkStatus() async =>
      CliAuthStatus(loggedIn: loggedIn);
}

class _BrokenConfigStore extends ConfigStore {
  var resetCalls = 0;

  @override
  Future<AppConfig> load() async => throw StateError('state file unavailable');

  @override
  Future<void> reset() async {
    resetCalls++;
  }
}

class _ReadyEnvironmentProvisioner extends EnvironmentProvisioner {
  _ReadyEnvironmentProvisioner() : super(isMacOS: true);

  @override
  Future<EnvironmentReadiness> ensureReady({
    required void Function(EnvironmentReadiness value) onProgress,
  }) async {
    final ready = EnvironmentReadiness(
      steps: {
        for (final step in EnvironmentStep.values)
          step: EnvironmentStepStatus.ready,
      },
    );
    onProgress(ready);
    return ready;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The Harness menu prints the running version. Without this the plugin
  // channel throws and the row renders a placeholder, which would make the
  // assertion below pass for the wrong reason.
  PackageInfo.setMockInitialValues(
    appName: 'Harness',
    packageName: 'ai.autonomous.harness',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  test('local manual fixture boots without SSO or persisted state', () async {
    final app = AppNotifier(
      config: const AppConfig(apiBaseUrl: 'http://127.0.0.1:12345'),
      authSession: AuthSession(),
      localManualFixture: const LocalManualFixture(
        apiBaseUrl: 'http://127.0.0.1:12345',
        apiKey:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        machineId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        machineName: 'local-manual',
        setupToken: 'ephemeral-setup-token',
      ),
    );

    await app.bootstrap();

    expect(app.status, AppStatus.authenticated);
    expect(app.config.apiBaseUrl, 'http://127.0.0.1:12345');
    expect(app.machines, hasLength(1));
    expect(app.machines.single.displayName, 'local-manual');
    expect(app.machines.single.authMode, MachineAuthMode.remote);
    expect(app.currentUser?.displayName, 'Local session');
  });

  test(
    'config-store failure falls back without resetting auth preferences',
    () async {
      final store = _BrokenConfigStore();
      final app = AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: store,
        cliLogin: _FakeCliLogin(loggedIn: false),
        environmentProvisioner: _ReadyEnvironmentProvisioner(),
      );

      await app.bootstrap();

      expect(app.status, AppStatus.unauthenticated);
      expect(app.config.apiBaseUrl, ConfigStore.defaultBaseUrl);
      expect(app.autonomousEnv, 'prod');
      expect(store.resetCalls, 0);
    },
  );

  testWidgets('boot -> unauthenticated shows LoginScreen', (tester) async {
    final app = makeNotifier(AppStatus.unauthenticated);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Harness'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byIcon(Icons.login), findsOneWidget);
  });

  testWidgets('bootstrapping shows full-screen spinner (pre-login)', (
    tester,
  ) async {
    final app = makeNotifier(AppStatus.bootstrapping);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pump();

    // RootShell renders a centered spinner while bootstrapping, not LoginScreen
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('environment setup exposes progress and a recoverable retry', (
    tester,
  ) async {
    final app = makeNotifier(AppStatus.preparingEnvironment);
    app.environmentReadiness = EnvironmentReadiness(
      steps: {
        EnvironmentStep.node: EnvironmentStepStatus.ready,
        EnvironmentStep.harness: EnvironmentStepStatus.ready,
        EnvironmentStep.tmux: EnvironmentStepStatus.needsTerminal,
      },
      message: 'Complete the macOS setup in Terminal, then click Retry.',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Preparing this Mac'), findsOneWidget);
    expect(find.text('Managed Node runtime'), findsOneWidget);
    expect(find.text('Retry after setup'), findsOneWidget);
  });

  testWidgets('RootShell rebuilds to LoginScreen when status flips after boot', (
    tester,
  ) async {
    // Regression: RootShell must listen to the AppNotifier, otherwise a status
    // change after the first build (e.g. bootstrap -> unauthenticated) never
    // rebuilds and the app sticks on the boot spinner.
    final app = makeNotifier(AppStatus.bootstrapping);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);

    app.status = AppStatus.unauthenticated;
    app.notifyListeners();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets(
    'authenticated with no machines shows terminal rail + empty terminal',
    (tester) async {
      final app = makeNotifier(AppStatus.authenticated);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWithValue(app)],
          child: const DesktopApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Select an agent, or drag one in from the left.'),
        findsOneWidget,
      );
      expect(find.text('diego@autonomous.ai'), findsOneWidget);
      expect(find.byKey(const Key('account-menu-button')), findsOneWidget);
      expect(find.byIcon(LucideIcons.logOut300), findsNothing);
      // The rail is present. Asserted on its primary action, not on the
      // filter field: that field lives behind the rail's search toggle, so its
      // absence says nothing about whether the rail rendered. The "Machines"
      // heading it used to check is gone — a machine is a caption over its own
      // agents now, so a caption over the captions would be two headings deep.
      //
      // This case is "no machines", and the button is drawn (disabled) even
      // then, on purpose: a rail that shows nothing at all cannot be told from
      // a rail that failed to build.
      expect(find.byKey(const Key('rail-new-agent-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('account-menu-button')));
      await tester.pumpAndSettle();

      expect(find.text('Diego'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.byIcon(LucideIcons.logOut300), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
      expect(find.text('Remote into another machine…'), findsOneWidget);

      final linkY = tester
          .getTopLeft(find.byKey(const Key('link-a-machine-menu-item')))
          .dy;
      final versionY = tester.getTopLeft(find.text('v1.0.0')).dy;
      final signOutY = tester
          .getTopLeft(find.byKey(const Key('sign-out-menu-item')))
          .dy;
      expect(linkY, lessThan(versionY));
      expect(versionY, lessThan(signOutY));
    },
  );

  testWidgets('Settings sits directly above Sign out in the account menu', (
    tester,
  ) async {
    final app = makeNotifier(AppStatus.authenticated);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('account-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);

    final linkY = tester
        .getTopLeft(find.byKey(const Key('link-a-machine-menu-item')))
        .dy;
    final settingsY = tester
        .getTopLeft(find.byKey(const Key('settings-menu-item')))
        .dy;
    final signOutY = tester
        .getTopLeft(find.byKey(const Key('sign-out-menu-item')))
        .dy;
    expect(linkY, lessThan(settingsY));
    expect(settingsY, lessThan(signOutY));
  });

  testWidgets('available update is shown above the login screen', (
    tester,
  ) async {
    final app = makeNotifier(AppStatus.unauthenticated);
    app.availableUpdate = const UpdateInfo(
      version: '1.2.3',
      url: 'https://example.test/Harness-macos.zip',
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      size: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Harness 1.2.3 is available'), findsOneWidget);
    expect(find.byKey(const Key('install-update-button')), findsOneWidget);
    expect(find.byKey(const Key('skip-update-button')), findsOneWidget);
  });

  testWidgets('manual update dialog can close without skipping the version', (
    tester,
  ) async {
    final app = makeNotifier(AppStatus.authenticated);
    await tester.pumpWidget(const MaterialApp(home: Placeholder()));

    final dialog = showUpdateCheckDialog(
      tester.element(find.byType(Placeholder)),
      app,
      const ManualUpdateCheck(
        update: UpdateInfo(
          version: '1.2.3',
          url: 'https://example.test/Harness-macos.zip',
          sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          size: 1,
        ),
        isSkipped: true,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('close-update-dialog-button')), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-update-dialog-button')));
    await tester.pumpAndSettle();
    await dialog;

    expect(find.byKey(const Key('close-update-dialog-button')), findsNothing);
    app.dispose();
  });

  testWidgets(
    'a forced (major/minor) update blocks the whole app, even over the login screen',
    (tester) async {
      final app = makeNotifier(AppStatus.unauthenticated);
      app.availableUpdate = const UpdateInfo(
        version: '2.0.0',
        url: 'https://example.test/Harness-macos.zip',
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        size: 1,
        forced: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWithValue(app)],
          child: const DesktopApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Harness 2.0.0 is required'), findsOneWidget);
      expect(
        find.byKey(const Key('forced-update-install-button')),
        findsOneWidget,
      );
      // No login screen underneath, and none of the optional-update escape hatches.
      expect(find.text('Sign in'), findsNothing);
      expect(find.byKey(const Key('skip-update-button')), findsNothing);
      expect(find.byKey(const Key('install-update-button')), findsNothing);
    },
  );

  testWidgets(
    'the manual update-check dialog never opens for a forced update — the blocking screen already covers it',
    (tester) async {
      final app = makeNotifier(AppStatus.authenticated);
      await tester.pumpWidget(const MaterialApp(home: Placeholder()));

      final dialog = showUpdateCheckDialog(
        tester.element(find.byType(Placeholder)),
        app,
        const ManualUpdateCheck(
          update: UpdateInfo(
            version: '2.0.0',
            url: 'https://example.test/Harness-macos.zip',
            sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            size: 1,
            forced: true,
          ),
        ),
      );
      await tester.pump();
      await dialog;

      expect(find.byType(Dialog), findsNothing);
      app.dispose();
    },
  );

  testWidgets('offline selected agent shows the Harness join guide', (
    tester,
  ) async {
    final app = makeNotifier(AppStatus.authenticated);
    const machine = Machine(
      machineId: 'offline-machine',
      apiKey: '',
      authMode: MachineAuthMode.remote,
      name: 'offline-mac',
      status: 'offline',
    );
    final state = MachineState(machine)
      ..localOnly = true
      ..nodeOnline = false
      ..activeAgentId = 'offline-agent'
      ..pendingOfflineAgentId = 'offline-agent'
      ..agentLoadStatus = AgentLoadStatus.loaded
      ..agents = [
        Agent.fromJson({
          'id': 'offline-agent',
          'name': 'claude-session',
          'engine': 'claude',
          'terminal': {
            'runtimes': [
              {'backend': 'tmux', 'paneId': '%1'},
            ],
          },
        }),
      ];
    app.machines = [machine];
    app.machineStates[machine.machineId] = state;
    app.expandedMachines.add(machine.machineId);
    app.selectedMachineId = machine.machineId;
    await app.selectAgent(machine.machineId, 'offline-agent');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Harness is offline'), findsOneWidget);
    expect(find.text('harness start'), findsOneWidget);
    app.dispose();
  });

  testWidgets('unlinked remote with a pending agent shows the link form', (
    tester,
  ) async {
    final app = makeNotifier(AppStatus.authenticated);
    const machine = Machine(
      machineId: 'unlinked-machine',
      apiKey: '',
      authMode: MachineAuthMode.remote,
      name: 'remote-mac',
      status: 'online',
    );
    final state = MachineState(machine)
      ..nodeOnline = false
      ..needsLink = true
      ..activeAgentId = 'previous-agent'
      ..pendingOfflineAgentId = 'previous-agent'
      ..agentLoadStatus = AgentLoadStatus.needsLink
      ..agents = [
        Agent.fromJson({
          'id': 'previous-agent',
          'name': 'previous-session',
          'engine': 'claude',
          'terminal': {
            'runtimes': [
              {'backend': 'tmux', 'paneId': '%1'},
            ],
          },
        }),
      ];
    app.machines = [machine];
    app.machineStates[machine.machineId] = state;
    app.expandedMachines.add(machine.machineId);
    app.selectedMachineId = machine.machineId;
    await app.selectAgent(machine.machineId, 'previous-agent');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    // The link screen now arrives as a popup (a post-frame callback pushes a showDialog route
    // with its own entrance transition), not a synchronous inline build — one pump() is no
    // longer enough to see it.
    await tester.pumpAndSettle();

    expect(find.text('Link this machine'), findsOneWidget);
    expect(
      find.text(
        "This computer isn't linked to remote-mac yet. Enter the remote password set "
        'on that machine to connect.',
      ),
      findsOneWidget,
    );
    expect(find.text('Harness is offline'), findsNothing);
    expect(find.text('harness start'), findsNothing);
    app.dispose();
  });

  testWidgets('clicking the link-required prompt opens the link screen', (
    tester,
  ) async {
    final app = makeNotifier(AppStatus.authenticated);
    const otherMachine = Machine(
      machineId: 'other-machine',
      apiKey: '',
      authMode: MachineAuthMode.remote,
      name: 'other-mac',
      status: 'online',
    );
    const machine = Machine(
      machineId: 'link-machine',
      apiKey: '',
      authMode: MachineAuthMode.remote,
      name: 'link-mac',
      status: 'online',
    );
    final state = MachineState(machine)
      ..nodeOnline = true
      ..needsLink = true
      ..agentLoadStatus = AgentLoadStatus.needsLink;
    final otherState = MachineState(otherMachine)
      ..nodeOnline = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
    app.machines = [otherMachine, machine];
    app.machineStates[otherMachine.machineId] = otherState;
    app.machineStates[machine.machineId] = state;
    app.expandedMachines.add(otherMachine.machineId);
    app.expandedMachines.add(machine.machineId);
    app.selectedMachineId = otherMachine.machineId;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Link this machine'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('link-required')));
    // Same popup-transition reasoning as above.
    await tester.pumpAndSettle();

    expect(find.text('Link this machine'), findsOneWidget);
    expect(
      find.text(
        "This computer isn't linked to link-mac yet. Enter the remote password set "
        'on that machine to connect.',
      ),
      findsOneWidget,
    );
    app.dispose();
  });

  testWidgets('clicking link-required while another terminal is focused opens '
      'the popup without opening a new pane', (tester) async {
    final app = makeNotifier(AppStatus.authenticated);
    const otherMachine = Machine(
      machineId: 'other-machine',
      apiKey: '',
      authMode: MachineAuthMode.remote,
      name: 'other-mac',
      status: 'online',
    );
    const machine = Machine(
      machineId: 'link-machine',
      apiKey: '',
      authMode: MachineAuthMode.remote,
      name: 'link-mac',
      status: 'online',
    );
    final otherState = MachineState(otherMachine)
      ..nodeOnline = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
    final state = MachineState(machine)
      ..nodeOnline = true
      ..needsLink = true
      ..agentLoadStatus = AgentLoadStatus.needsLink;
    app.machines = [otherMachine, machine];
    app.machineStates[otherMachine.machineId] = otherState;
    app.machineStates[machine.machineId] = state;
    app.expandedMachines.add(otherMachine.machineId);
    app.expandedMachines.add(machine.machineId);

    // A terminal already open and FOCUSED on the other machine — this is what made
    // activeMachineState (which prefers focusedPane's session) resolve to the wrong
    // machine and made showMachinePane open a second, redundant "not linked" pane.
    final otherPane =
        TerminalPane(
            id: 1,
            machineId: otherMachine.machineId,
            agentId: 'other-agent',
          )
          ..session = TerminalSession(
            machineId: otherMachine.machineId,
            agentId: 'other-agent',
            agentName: 'other-agent',
            engineId: null,
            send: (_, _) async => true,
            sendBinary: (_) async => true,
          );
    app.panes.add(otherPane);
    app.focusedPaneId = otherPane.id;
    app.selectedMachineId = otherMachine.machineId;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWithValue(app)],
        child: const DesktopApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Link this machine'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('link-required')));
    await tester.pumpAndSettle();

    expect(find.text('Link this machine'), findsOneWidget);
    // No second pane was opened for the popup — just the one terminal pane that was
    // already there.
    expect(app.panes, hasLength(1));
    expect(
      find.text('link-mac is not linked to this computer yet.'),
      findsNothing,
    );
    app.dispose();
  });
}
