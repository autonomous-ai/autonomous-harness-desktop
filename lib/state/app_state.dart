import 'dart:async';
import 'dart:io' show exit, pid;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../auth/auth_session.dart';
import '../auth/cli_link.dart';
import '../auth/cli_login.dart';
import '../bootstrap/environment_provisioner.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../grid/grid_agent_override.dart';
import '../settings/config_store.dart';
import '../terminal/terminal_session.dart';
import 'pane_layout_store.dart';
import 'terminal_pane.dart';
import '../terminal/terminal_binary.dart';
import '../update/desktop_updater.dart';
import '../update/manual_update_check.dart';
import '../ws/ws_conn.dart';
import '../ws/local_cli_discovery.dart';
import '../ws/ws_pool.dart';

enum AppStatus {
  bootstrapping,
  preparingEnvironment,
  unauthenticated,
  authenticated,
}

enum AgentLoadStatus { idle, needsLink, loading, loaded, error }

enum MachineTransportMode { cloudE2ee, localPlaintext, localOffline }

/// Result of [AppNotifier.restartAgent]. [error] null means the RPC succeeded; [resumed] then says
/// whether the daemon reattached the agent's prior session or fell back to a fresh one (e.g. the
/// engine's resume flag wasn't recognized) — worth telling the user about, since it's not a failure
/// but the conversation may not have continued the way "Restart" implies.
class RestartAgentResult {
  final String? error;
  final bool resumed;

  const RestartAgentResult({this.error, this.resumed = true});
}

String? _normalizeComputerId(String? raw) {
  if (raw == null) return null;
  final value = raw.trim().toLowerCase().replaceAll('-', '');
  return RegExp(r'^[a-f0-9]{16,64}$').hasMatch(value) ? value : null;
}

/// Explicit, compile-time guarded fixture used only by `main_local_manual.dart`.
///
/// It lets a normal Flutter window exercise the local Backend -> Harness CLI ->
/// tmux path without depending on SSO. The API key and setup token are random,
/// disposable values produced by the local launcher and are never persisted.
class LocalManualFixture {
  final String apiBaseUrl;
  final String apiKey;
  final String machineId;
  final String machineName;
  final String setupToken;

  const LocalManualFixture({
    required this.apiBaseUrl,
    required this.apiKey,
    required this.machineId,
    required this.machineName,
    required this.setupToken,
  });
}

@visibleForTesting
Map<String, dynamic> eventWithClearPayload(
  Map<String, dynamic> frame,
  String type,
  Map<String, dynamic> payload,
) => {...frame, 'type': type, 'payload': payload};

class MachineState {
  Machine machine;
  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;
  MachineTransportMode transportMode = MachineTransportMode.cloudE2ee;

  /// Set when this machine is bound to the local CLI's stable computer id. A
  /// local machine never falls back to cloud E2EE while that identity exists.
  bool localOnly = false;
  LocalCliEndpoint? localEndpoint;
  // Set when the local CLI's relay reports NO_PEER_LINK for this (non-local) machine — it needs
  // `harness link connect <machineId>` (the other machine's remote password) before it can
  // connect. The CLI owns E2EE entirely now; this is just "is trust established yet", not a
  // crypto/pairing state the app has any data for.
  bool needsLink = false;
  List<Agent> agents = [];
  AgentLoadStatus agentLoadStatus = AgentLoadStatus.idle;
  bool agentsRefreshing = false;
  String? agentsLoadError;
  Future<void>? agentsLoadInFlight;
  String? activeAgentId;
  bool terminalCapabilityLoaded = false;
  bool terminalCapabilityAvailable = false;
  String? terminalCapabilityError;
  // Adapter/manager presence for this machine, from `node_status` pushes —
  // distinct from `connectionStatus`, which only reflects OUR websocket to
  // the backend. null = not seen yet (initial connect).
  bool? nodeOnline;
  // The agent the user selected while the Harness adapter was offline. Keep
  // this separate from activeAgentId so the UI can show a join guide without
  // opening a terminal stream against an unavailable node.
  String? pendingOfflineAgentId;
  final Set<String> processingAgentIds = {};
  final Map<String, String> sessionAgentIds = {};
  // Turn events can arrive while the initial agents_list RPC is still in
  // flight. Retain session correlation until that snapshot binds the row.
  final Set<String> pendingProcessingSessions = {};

  MachineState(this.machine);

  bool get isRemote => machine.authMode == MachineAuthMode.remote;
  bool get isLocalMachine => localOnly || localEndpoint != null;
  bool get usesLocalTransport => localEndpoint != null;

  Agent? get activeAgent {
    for (final agent in agents) {
      if (agent.id == activeAgentId) return agent;
    }
    return null;
  }
}

/// Auth, Remote-machine discovery, E2EE and one explicit terminal attachment.
/// Structured chat intentionally does not exist in the Desktop MVP state.
class AppNotifier extends ChangeNotifier {
  final AuthSession session;
  AppConfig config;
  late ApiClient api;
  final CliLogin cliLogin;
  final CliLink cliLink;
  final ConfigStore? _store;
  final LocalManualFixture? localManualFixture;
  final Duration turnActivityTimeout;
  final LocalCliDiscovery? localCliDiscovery;
  final EnvironmentProvisioner? environmentProvisioner;
  final DesktopUpdater? desktopUpdater;
  final Map<String, Timer> _turnActivityWatchdogs = {};
  final Map<String, Timer> _offlineRetryTimers = {};
  // Periodic retry for a machine the relay reported NO_PEER_LINK for — a `harness link connect` run
  // in a terminal (or another app instance) has no way to notify this one, so this is what makes the
  // app pick up a fresh link within a few seconds instead of only on the next manual click/restart.
  final Map<String, Timer> _linkRetryTimers = {};
  // Safety-net reconciliation for a connected machine's agent list, on top of the push events
  // (agent_synced/agent_created/agent_renamed/agent_deleted) that normally keep it live — catches the
  // rare case a push event was dropped. Runs silently: see _syncAgentsIfChanged.
  final Map<String, Timer> _agentSyncTimers = {};
  // Keeps the local `harness` daemon alive for the whole app run — started once after the first
  // successful bootstrap (see `_ensureCliDaemon`), cancelled on dispose. Cancelling only stops this
  // Dart-side loop; the daemon itself self-daemonizes and must keep running after the app quits.
  Timer? _daemonSupervisionTimer;
  // Update checks do not depend on the daemon or SSO. A signed-out user should
  // still be able to replace a broken desktop build from the login screen.
  Timer? _updateCheckTimer;
  String? _skippedDesktopUpdateVersion;
  UpdateInfo? availableUpdate;
  bool isCheckingForUpdate = false;
  bool isInstallingUpdate = false;
  String? updateError;
  final Set<String> _offlinePollsInFlight = {};
  final Set<String> _offlineRecoveryInFlight = {};
  bool _disposed = false;

  WsPool? _pool;
  late String _autonomousEnv;
  String? _lastError;
  EnvironmentReadiness environmentReadiness = EnvironmentReadiness.initial();
  bool _environmentSetupInFlight = false;
  // The daemon's own advertised local-ws endpoint — the dial target for EVERY machine's data plane
  // now, not just this computer's own one (see src/lib/remoteRelay.ts in the harness CLI repo: a
  // foreign machineId is relayed to backend transparently, so the app never dials backend directly).
  LocalCliEndpoint? _cliEndpoint;

  AppStatus status = AppStatus.bootstrapping;
  CurrentUserProfile? currentUser;
  List<Machine> machines = [];
  final Map<String, MachineState> machineStates = {};
  final Set<String> expandedMachines = {};
  String? selectedMachineId;

  /// The grid, in reading order. At most [maxPanes].
  final List<TerminalPane> panes = [];

  /// Which tile the keyboard, the dial and the rail's highlight all mean.
  ///
  /// Typing itself does NOT go through this on macOS — the renderer is a
  /// WebView, so a click makes that pane's WKWebView the first responder and
  /// AppKit routes keys there without asking. This is for everything that has
  /// no pointer behind it: the dial's scroll and focus frames, and which agent
  /// the rail draws as current.
  int? focusedPaneId;

  int _nextPaneId = 1;

  static const maxPanes = PaneLayoutStore.maxPanes;
  // Set only while `harness login --json` is waiting for the user to finish SSO in their system
  // browser — RootShell renders a lightweight waiting screen and clears this automatically once
  // login() resolves.
  String? pendingAuthorizeUrl;

  AppNotifier({
    required AppConfig config,
    required AuthSession authSession,
    ConfigStore? configStore,
    this.localManualFixture,
    this.localCliDiscovery,
    this.environmentProvisioner,
    this.desktopUpdater,
    CliLogin? cliLogin,
    CliLink? cliLink,
    PaneLayoutStore? paneLayoutStore,
    this.turnActivityTimeout = const Duration(seconds: 12),
  }) : _paneLayout = paneLayoutStore,
       session = authSession,
       _store = configStore,
       cliLogin = cliLogin ?? CliLogin(),
       cliLink = cliLink ?? CliLink(),
       config = configStore?.config ?? config {
    _autonomousEnv = this.config.autonomousEnv;
    api = ApiClient(config: this.config, session: session);
  }

  String? get lastError => _lastError;
  String get autonomousEnv => _autonomousEnv;
  bool get hasAvailableUpdate => availableUpdate != null;
  bool get hasForcedUpdate => availableUpdate?.forced ?? false;

  static const offlineRetryInterval = Duration(seconds: 5);
  static const agentSyncInterval = Duration(seconds: 60);

  MachineState? stateOf(String machineId) => machineStates[machineId];

  // ── the grid ────────────────────────────────────────────────────────────────────────────────────

  /// Null means "remember nothing", which is what a test gets by default.
  ///
  /// Deliberately NOT `?? PaneLayoutStore()` like the stores above it. Those
  /// only read, and only when asked; this one WRITES on every pane change, and
  /// a widget test that opens an agent would otherwise rewrite the layout in
  /// the developer's own ~/.harness state file. Production passes one; see
  /// [appStateProvider].
  final PaneLayoutStore? _paneLayout;

  TerminalPane? get focusedPane {
    final id = focusedPaneId;
    if (id == null) return null;
    for (final pane in panes) {
      if (pane.id == id) return pane;
    }
    return null;
  }

  /// The one tile everything single-terminal still means.
  ///
  /// Kept as a getter rather than deleted because the alternative — teaching
  /// every caller about tiles — would have spread the grid across code that has
  /// no business knowing there is one (a rename arriving, an agent being
  /// deleted, the window closing). The handful of callers that must reach EVERY
  /// tile of a machine, rather than only the focused one, call [panesFor]
  /// instead; those are the transport-wide events, and they are marked.
  TerminalSession? get activeTerminal => focusedPane?.session;

  bool get canAddPane => panes.length < maxPanes;

  Iterable<TerminalPane> panesFor(String machineId) =>
      panes.where((pane) => pane.machineId == machineId);

  TerminalPane? paneOfAgent(String machineId, String agentId) {
    for (final pane in panes) {
      if (pane.machineId == machineId && pane.agentId == agentId) return pane;
    }
    return null;
  }

  bool isAgentInPane(String machineId, String agentId) =>
      paneOfAgent(machineId, agentId) != null;

  bool isPaneFocused(int paneId) => focusedPaneId == paneId;

  /// Show or hide one tile's composer textbox, and remember the choice.
  void toggleComposer(int paneId) {
    for (final pane in panes) {
      if (pane.id != paneId) continue;
      pane.composerVisible = !pane.composerVisible;
      _persistLayout();
      notifyListeners();
      return;
    }
  }

  void focusPane(int paneId) {
    if (!panes.any((pane) => pane.id == paneId)) return;
    final moved = focusedPaneId != paneId;
    focusedPaneId = paneId;
    // Announced even when this tile was ALREADY focused.
    //
    // The dial can be turned by hand, and then the two disagree with nobody
    // knowing. Choosing this agent — from the rail or by clicking its tile — is
    // how someone says "no, look at THIS one", so it has to be able to say it.
    //
    // The old guard here made that impossible in exactly the case that needed
    // it. An agent that is NOT open yet gets a fresh stream, and the daemon
    // follows `terminal_open` as a side effect; one that IS open opens nothing,
    // so `app_focus` is the only thing that can move the dial — and this
    // returned before sending it. That is why a single pane always worked
    // (every switch re-attached) and a second pane broke it.
    //
    // Re-sending the same agent is safe: the daemon drops it against the dial's
    // real position (`agentId === this.dialFocus` in cableSession), which is the
    // only side that can judge, because only it knows where the dial is.
    _announceFocusToDial();
    // Only a real move is worth a rebuild.
    if (moved) notifyListeners();
  }

  /// Tell the local daemon which agent this window is looking at, so the dial follows it.
  ///
  /// Said outright rather than left to be inferred. The daemon used to work this out from
  /// `terminal_open`, which was equivalent while a window could only show one terminal: every move
  /// opened a stream, so opening one meant it had moved.
  ///
  /// A pane grid breaks that equivalence. Clicking a tile that already holds a live session opens
  /// nothing at all, so the dial stayed on whichever agent the last rail click had opened — which is
  /// why the rail appeared to work and the panes did not.
  ///
  /// Fire-and-forget, and only for a tile that has an agent: a machine tile is not somewhere the
  /// dial can go.
  void _announceFocusToDial() {
    final pane = focusedPane;
    final agentId = pane?.agentId;
    if (pane == null || agentId == null) return;
    // The EXISTING connection, never `_conn`, which builds one. Opening a socket as a side effect of
    // moving a focus ring is the wrong trade in both directions: it dials a machine nobody asked to
    // reach, and `_conn` throws outright before the pool exists — which took focusPane down with it,
    // so clicking a tile did nothing at all rather than merely failing to reach the dial.
    //
    // Nothing here is worth failing a click for: no dial attached, no daemon yet, a socket mid
    // reconnect — the tile still focuses and the window still works.
    final connection = _pool?[pane.machineId];
    if (connection == null) return;
    unawaited(
      connection
          .sendTerminalFrame('app_focus', {'agentId': agentId})
          .catchError((_) => false),
    );
  }

  /// Machines whose link prompt the user has waved away.
  ///
  /// Dismissing cannot mean "deselect": [activeMachineState] falls back to the
  /// first expanded machine, so clearing the selection would often re-arrive at
  /// the very machine that was just closed. And it must not mean "linked" —
  /// nothing changed about the machine, which still cannot be read and still
  /// says so in the rail. It means only that the pane stops insisting.
  ///
  /// Held in memory, not on disk, and cleared the moment the machine is chosen
  /// again: someone who clicks that row is asking to see it.
  final Set<String> _dismissedLinkPrompts = {};

  bool isLinkPromptDismissed(String machineId) =>
      _dismissedLinkPrompts.contains(machineId);

  void dismissLinkPrompt(String machineId) {
    if (_dismissedLinkPrompts.add(machineId)) notifyListeners();
  }

  MachineState? get activeMachineState {
    final terminal = activeTerminal;
    if (terminal != null) return machineStates[terminal.machineId];
    final selected = selectedMachineId;
    if (selected != null) return machineStates[selected];
    return expandedMachines.isEmpty
        ? null
        : machineStates[expandedMachines.first];
  }

  bool? _nodeOnlineFromStatus(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'running':
      case 'online':
      case 'connected':
      case 'ready':
        return true;
      case 'offline':
      case 'stopped':
      case 'disconnected':
      case 'unreachable':
      case 'error':
      case 'failed':
        return false;
      default:
        return null;
    }
  }

  Future<void> selectAutonomousEnv(String value) async {
    if (value != 'prod' && value != 'stag') return;
    _autonomousEnv = value;
    config = AppConfig(
      apiBaseUrl: config.apiBaseUrl,
      autonomousEnv: value,
      localCliBaseUrl: config.localCliBaseUrl,
    );
    _lastError = null;
    notifyListeners();
    await _store?.saveEnvironment(value);
  }

  Future<void> bootstrap() async {
    final localFixture = localManualFixture;
    if (localFixture != null) {
      _bootstrapLocalManual(localFixture);
      return;
    }
    try {
      if (_store != null) {
        try {
          config = await _store.load().timeout(const Duration(seconds: 5));
        } catch (error) {
          // Connection settings are optional local preferences. An unavailable
          // state file must not invalidate an otherwise recoverable SSO flow;
          // use the store's safe cached/default production config.
          debugPrint(
            'bootstrap: config store unavailable, using defaults: $error',
          );
          config = _store.config;
        }
        // Forced, not read from persisted config: staging is a dev-only
        // escape hatch with no UI to reach it anymore (see login_screen.dart
        // history) — a stale `stag` value saved before that removal must
        // never silently resurrect it.
        _autonomousEnv = 'prod';
        api = ApiClient(config: config, session: session);
        _skippedDesktopUpdateVersion = _store.skippedDesktopUpdateVersion;
      }
      _startUpdateChecking();
      final environmentReady = await _prepareEnvironment();
      if (!environmentReady) return;
      // Auth now lives entirely with the local `harness` CLI — it owns the SSO session on disk and
      // refreshes it itself. This app never reads, stores, or refreshes a token of its own; it just
      // asks the CLI whether this computer is currently signed in.
      final authStatus = await cliLogin.checkStatus();
      if (!authStatus.loggedIn) {
        currentUser = null;
        status = AppStatus.unauthenticated;
        notifyListeners();
        return;
      }
      await _finishBootstrapSignedIn();
    } catch (error, stack) {
      debugPrint('bootstrap: fallback to login after error: $error\n$stack');
      currentUser = null;
      status = AppStatus.unauthenticated;
      notifyListeners();
    }
  }

  /// Runs before we invoke a single Harness subcommand. A fresh mac used to
  /// fail here with a generic Sign in error because `harness` and its Node
  /// runtime were absent; provisioning now makes that a visible, recoverable
  /// first-run phase instead.
  Future<bool> _prepareEnvironment() async {
    if (_environmentSetupInFlight) return false;
    _environmentSetupInFlight = true;
    status = AppStatus.preparingEnvironment;
    environmentReadiness = EnvironmentReadiness.initial();
    notifyListeners();
    try {
      final provisioner = environmentProvisioner ?? EnvironmentProvisioner();
      final result = await provisioner.ensureReady(
        onProgress: (value) {
          environmentReadiness = value;
          notifyListeners();
        },
      );
      environmentReadiness = result;
      if (!result.isReady) {
        status = AppStatus.preparingEnvironment;
        notifyListeners();
        return false;
      }
      return true;
    } finally {
      _environmentSetupInFlight = false;
    }
  }

  /// Used after macOS finishes the visible Homebrew / Command Line Tools path.
  /// The first-run flow is deliberately re-run end to end: Node and Harness
  /// checks are idempotent and this prevents a stale partial install from being
  /// mistaken for a ready machine.
  Future<void> retryEnvironmentSetup() => bootstrap();

  void _bootstrapLocalManual(LocalManualFixture fixture) {
    _autonomousEnv = 'prod';
    config = AppConfig(apiBaseUrl: fixture.apiBaseUrl);
    api = ApiClient(config: config, session: session);
    currentUser = const CurrentUserProfile.local();
    final machine = Machine(
      machineId: fixture.machineId,
      apiKey: fixture.apiKey,
      authMode: MachineAuthMode.remote,
      name: fixture.machineName,
      status: 'online',
    );
    machines = [machine];
    machineStates
      ..clear()
      ..[machine.machineId] = MachineState(machine);
    machineStates[machine.machineId]!.nodeOnline = true;
    expandedMachines.clear();
    selectedMachineId = null;
    status = AppStatus.authenticated;
    _lastError = null;
    _ensurePool();
    _autoConnectAndLoadMachines();
    notifyListeners();
  }

  /// Both `bootstrap()` (already signed in) and `login()` (just finished signing in) land here once
  /// the CLI confirms a session exists — ensure the local daemon is actually up first (it does not
  /// start on its own, and every call below is a local-CLI-proxied request that needs it), then fetch
  /// the profile and load the machine list over it.
  Future<void> _finishBootstrapSignedIn() async {
    status = AppStatus.authenticated;
    // Before the machines, deliberately: the tiles are intent, they render as
    // "waiting for that machine" on their own, and each attaches as its machine
    // answers. Waiting for the machine list first would leave the window empty
    // for as long as the slowest one takes, and would hand the first-run
    // auto-pick a window in which the grid still looks empty.
    await _restorePaneLayout();
    _ensurePool();
    try {
      await _ensureCliDaemon();
    } catch (error) {
      _lastError = '$error';
      notifyListeners();
      return;
    }
    try {
      final me = await api.me();
      if (me != null) currentUser = CurrentUserProfile.fromMe(me);
    } catch (error) {
      debugPrint('bootstrap: profile unavailable: $error');
    }
    try {
      await refreshMachines();
    } catch (error) {
      _lastError = 'Could not load machines: $error';
    }
    notifyListeners();
  }

  /// The local daemon (`harness start`) must be up before any local REST/WS call can work — unlike
  /// `harness login`, it does not start on its own. Sets [_cliEndpoint], the dial target every
  /// machine's WsConn now uses.
  Future<void> _ensureCliDaemon() async {
    final discovery = localCliDiscovery ?? LocalCliDiscovery(config: config);
    final endpoint = await discovery.ensureRunning();
    if (endpoint == null) {
      // Before blaming the environment, check whether the daemon is missing because it signed itself
      // out. "Try running `harness start` yourself" is advice that cannot work in that case — the
      // session file is gone, so every start exits again — and it is the advice this branch used to
      // give unconditionally.
      if (!(await cliLogin.checkStatus()).loggedIn) {
        _signedOutAtRuntime(_signedOutMessage);
        return;
      }
      throw StateError(
        'The local Harness daemon did not start. Try running `harness start` yourself, then reopen the app.',
      );
    }
    _cliEndpoint = endpoint;
    // Only start supervising AFTER the first bootstrap attempt already succeeded above — starting it
    // earlier risks a concurrent `harness start` spawn from both places at once (the daemon's control
    // port is fixed, so a second spawn while the first is still binding fails loudly).
    _daemonSupervisionTimer ??= discovery.startSupervising(
      stillSignedIn: () async => (await cliLogin.checkStatus()).loggedIn,
      onSignedOut: () => _signedOutAtRuntime(_signedOutMessage),
    );
  }

  /// Deliberately says nothing about WHY. The daemon clears its session identically whether the
  /// machine was deleted from another machine or the SSO token simply expired, and guessing between
  /// them in the copy would sometimes be wrong. Signing in again is the answer to both.
  static const _signedOutMessage =
      'You were signed out on this computer. Sign in again to reconnect.';

  /// The session went away while the app was already running — send the user to [LoginScreen] with a
  /// reason, and stop the background work that can only fail from here.
  ///
  /// Cold start already handles this: [bootstrap] asks the CLI whether it is signed in. The hole this
  /// fills is the app that was ALREADY authenticated when the session disappeared underneath it,
  /// where nothing re-checked and the daemon supervisor simply respawned `harness start` forever.
  void _signedOutAtRuntime(String message) {
    if (status == AppStatus.unauthenticated)
      return; // idempotent: several sources can race here
    _daemonSupervisionTimer?.cancel();
    _daemonSupervisionTimer = null;
    _cliEndpoint = null;
    unawaited(_pool?.closeAll());
    _pool = null;
    _lastError = message;
    status = AppStatus.unauthenticated;
    notifyListeners();
  }

  void _startUpdateChecking() {
    _updateCheckTimer ??= (desktopUpdater ?? DesktopUpdater()).startChecking(
      onUpdateAvailable: _handleBackgroundUpdate,
    );
  }

  void _handleBackgroundUpdate(UpdateInfo info) {
    if (_disposed) return;
    if (!info.forced && _skippedDesktopUpdateVersion == info.version) return;
    if (availableUpdate?.version == info.version) return;
    availableUpdate = info;
    updateError = null;
    notifyListeners();
  }

  /// A manual check deliberately returns a skipped version too, so the user
  /// can choose to install it from the account menu after changing their mind.
  Future<ManualUpdateCheck> checkForUpdates() async {
    if (isCheckingForUpdate) {
      return ManualUpdateCheck(update: availableUpdate);
    }
    isCheckingForUpdate = true;
    updateError = null;
    notifyListeners();
    try {
      final info = await (desktopUpdater ?? DesktopUpdater()).checkOnce();
      if (info == null) return const ManualUpdateCheck();
      final skipped = _skippedDesktopUpdateVersion == info.version;
      availableUpdate = info;
      return ManualUpdateCheck(update: info, isSkipped: skipped);
    } finally {
      isCheckingForUpdate = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Clears a failed install without burying the offer.
  ///
  /// Skipping is permanent — it records the version so the background check
  /// stops raising it. A failure is not a decision about the version, so the
  /// way out of one has to leave the update on the table.
  void dismissUpdateError() {
    if (updateError == null) return;
    updateError = null;
    notifyListeners();
  }

  Future<void> skipAvailableUpdate() async {
    final info = availableUpdate;
    if (info == null || info.forced) return;
    _skippedDesktopUpdateVersion = info.version;
    await _store?.saveSkippedDesktopUpdateVersion(info.version);
    availableUpdate = null;
    updateError = null;
    notifyListeners();
  }

  /// Downloads, verifies, and installs only after an explicit user action.
  /// A failed operation leaves the running app untouched and retryable.
  Future<bool> installAvailableUpdate() async {
    final info = availableUpdate;
    if (info == null || isInstallingUpdate) return false;
    isInstallingUpdate = true;
    updateError = null;
    notifyListeners();
    try {
      final updater = desktopUpdater ?? DesktopUpdater();
      final staged = await updater.downloadAndStage(info);
      if (staged == null) {
        updateError = 'Could not download and verify Harness ${info.version}.';
        return false;
      }
      final applied = await updater.applyStaged(staged, selfPid: pid);
      if (!applied) {
        updateError =
            'This copy of Harness cannot install updates automatically.';
        return false;
      }
      exit(0);
    } catch (error) {
      updateError = 'Could not install Harness ${info.version}: $error';
      return false;
    } finally {
      isInstallingUpdate = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> login() async {
    _lastError = null;
    status = AppStatus.bootstrapping;
    pendingAuthorizeUrl = null;
    notifyListeners();
    try {
      await cliLogin.login(
        onAuthorizeUrl: (url) {
          pendingAuthorizeUrl = url;
          notifyListeners();
          // Must be the system browser, not an embedded webview: this SSO page's Google button uses
          // Google's popup-based Identity Services flow (a real popup window posts the result back to
          // its opener), which only a real browser can satisfy.
          unawaited(
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          );
        },
      );
      await _finishBootstrapSignedIn();
    } catch (error) {
      status = AppStatus.unauthenticated;
      _lastError = error.toString();
    } finally {
      pendingAuthorizeUrl = null;
    }
    notifyListeners();
  }

  /// Aborts an in-flight [login] — the embedded sign-in webview's close button calls this.
  void cancelLogin() => cliLogin.cancel();

  Future<void> logout() async {
    // Best-effort and fire-and-forget: local state is cleared below regardless of whether the CLI
    // process could be reached, but a real `harness logout` clears its saved session so the NEXT
    // launch doesn't silently sign back in without ever showing the login screen.
    unawaited(cliLogin.logout());
    _stopAllOfflineRetries();
    _stopAllLinkRetries();
    _stopAllAgentSyncTimers();
    // Tiles go, the saved layout stays: signing out and back in is the same
    // person at the same desk, and the file is only read once machines exist.
    await _closeAllPanes(persist: false);
    await _pool?.closeAll();
    _pool = null;
    _cliEndpoint = null;
    _clearAllTurnActivity();
    currentUser = null;
    machines = [];
    machineStates.clear();
    expandedMachines.clear();
    selectedMachineId = null;
    status = AppStatus.unauthenticated;
    notifyListeners();
  }

  void _ensurePool() {
    if (_pool != null) return;
    _pool = WsPool(
      wsBaseUrl: config.wsBaseUrl,
      autonomousEnv: _autonomousEnv,
      // Every real WsConn now dials the local CLI's loopback WS (transportKind.localPlaintext, see
      // _conn()), which never calls this — only the compile-time-only local-manual dev fixture (see
      // LocalManualFixture) still dials a backend directly with a token.
      accessTokenProvider: (_, _) async {
        final fixture = localManualFixture;
        if (fixture != null) return fixture.apiKey;
        throw StateError(
          'unreachable: only the local-manual dev fixture uses a token-bearing WS transport',
        );
      },
      onAuthFailure: _signedOutAtRuntime,
      onLocalFailure: (machineId, code, reason) {
        final machine = machineStates[machineId];
        if (machine == null || code != 4404) return;
        // The local CLI's relay found no linked trust for this machine — it now owns E2EE entirely.
        // A `harness link connect` run in a terminal (or another app instance) has no way to notify
        // this one directly, so poll every few seconds until it's picked up instead of waiting for
        // the user to click back into this machine.
        machine.needsLink = true;
        machine.agentLoadStatus = AgentLoadStatus.needsLink;
        notifyListeners();
        _startLinkRetry(machineId);
      },
      onEvent: _handleEvent,
      onStatus: (machineId, nextStatus) {
        final machine = machineStates[machineId];
        if (machine == null) return;
        machine.connectionStatus = nextStatus;
        if (nextStatus == ConnectionStatus.connected) {
          machine.needsLink = false;
          _stopLinkRetry(machineId);
          // The local CLI never hands back `connected` until it has terminated E2EE (or confirmed
          // none is needed, for its own machine) — every machine's data is ready to load right away,
          // with no separate app-side readiness gate to wait on anymore.
          if (machine.isLocalMachine) {
            machine.transportMode = MachineTransportMode.localPlaintext;
          } else {
            machine.transportMode = MachineTransportMode.cloudE2ee;
          }
          // Route through _applyNodeStatus (not just `machine.nodeOnline = true`) for every machine,
          // not only the local one — a successful select IS the machine being reachable again, and
          // this is what lets a pending agent (captured below on disconnect) reattach automatically
          // instead of leaving the user stuck on the empty "select a machine" placeholder.
          unawaited(_applyNodeStatus(machine, true));
          unawaited(_loadMachineData(machine, force: true));
          _startAgentSyncTimer(machineId);
        } else if (nextStatus == ConnectionStatus.reconnecting ||
            nextStatus == ConnectionStatus.disconnected) {
          _stopAgentSyncTimer(machineId);
          _clearMachineActivity(machine);
          if (machine.isLocalMachine) {
            machine.transportMode = MachineTransportMode.localOffline;
          }
          // Same reasoning as above, mirrored: capture pendingOfflineAgentId from the currently-open
          // terminal (if any) so the connected branch above can reattach it, for every machine — this
          // used to be local-only, which is why a remote machine's terminal never came back on its own
          // after `harness start` on that machine, even though the guide screen promised it would.
          unawaited(_applyNodeStatus(machine, false));
        }
        notifyListeners();
      },
    );
  }

  /// The machine list is being fetched and there is nothing to show meanwhile.
  ///
  /// Only the FIRST fetch sets it: a refresh over a list already on screen
  /// keeps that list up (the rows are still true, just not from a moment ago)
  /// and reports nothing. The rail reads this to tell "loading" from "no
  /// machines", which an empty list alone cannot say.
  bool machinesLoading = false;

  Future<void> refreshMachines() async {
    if (localManualFixture != null) {
      notifyListeners();
      return;
    }
    if (machines.isEmpty && !machinesLoading) {
      machinesLoading = true;
      notifyListeners();
    }
    try {
      await _refreshMachines();
    } finally {
      // Said out loud: the list's own notify fires before this, so a flag
      // dropped silently here would leave the rail on its placeholders.
      if (machinesLoading) {
        machinesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshMachines() async {
    final discovery = localCliDiscovery ?? LocalCliDiscovery(config: config);
    // The CLI computer id is the local identity source of truth. The loopback
    // status endpoint is trusted only when it advertises that same identity.
    final localComputerId = await discovery.computerId();
    final localFuture = discovery.discover(expectedComputerId: localComputerId);
    final list = await _fetchMachines();
    final localEndpoint = await localFuture;
    machines = list
        .where((machine) => machine.authMode == MachineAuthMode.remote)
        .toList();
    final visible = machines.map((machine) => machine.machineId).toSet();
    for (final entry in machineStates.entries) {
      if (!visible.contains(entry.key)) {
        _clearMachineActivity(entry.value);
        _stopOfflineRetry(entry.key);
        _stopLinkRetry(entry.key);
        _stopAgentSyncTimer(entry.key);
      }
    }
    machineStates.removeWhere((id, _) => !visible.contains(id));
    for (final machine in machines) {
      final state = machineStates.update(
        machine.machineId,
        (state) => state..machine = machine,
        ifAbsent: () => MachineState(machine),
      );
      state.localOnly =
          localComputerId != null &&
          _normalizeComputerId(machine.computerId) == localComputerId;
      if (state.localOnly && localEndpoint?.computerId == localComputerId) {
        state.localEndpoint = localEndpoint;
        if (state.connectionStatus == ConnectionStatus.connected) {
          state.transportMode = MachineTransportMode.localPlaintext;
        } else {
          state.transportMode = MachineTransportMode.localOffline;
        }
      } else if (state.localOnly) {
        // The token still identifies this as local, but the CLI is offline or
        // failed its identity/capability check. Never fall back to cloud E2EE.
        state.localEndpoint = null;
        state.transportMode = MachineTransportMode.localOffline;
        state.nodeOnline = false;
        _startOfflineRetry(state);
      } else {
        state.localEndpoint = null;
        state.transportMode = MachineTransportMode.cloudE2ee;
      }
      final reportedOnline = _nodeOnlineFromStatus(machine.status);
      if (!state.isLocalMachine &&
          reportedOnline != null &&
          (state.nodeOnline == null || state.nodeOnline != reportedOnline)) {
        unawaited(_applyNodeStatus(state, reportedOnline));
      }
    }
    _autoConnectAndLoadMachines();
    notifyListeners();
  }

  Future<List<Machine>> _fetchMachines() => api.machines();

  void _startOfflineRetry(MachineState machine) {
    final machineId = machine.machine.machineId;
    if (machine.nodeOnline != false ||
        (!machine.isLocalMachine && machine.pendingOfflineAgentId == null)) {
      _stopOfflineRetry(machineId);
      return;
    }
    if (_offlineRetryTimers.containsKey(machineId)) return;
    _offlineRetryTimers[machineId] = Timer.periodic(
      offlineRetryInterval,
      (_) => unawaited(_pollOfflineMachine(machineId)),
    );
  }

  void _stopOfflineRetry(String machineId) {
    _offlineRetryTimers.remove(machineId)?.cancel();
  }

  void _startLinkRetry(String machineId) {
    if (_linkRetryTimers.containsKey(machineId)) return;
    _linkRetryTimers[machineId] = Timer.periodic(offlineRetryInterval, (_) {
      final state = machineStates[machineId];
      if (state == null || !state.needsLink) {
        _stopLinkRetry(machineId);
        return;
      }
      unawaited(_pool?.closeMachine(machineId));
      _connectMachine(state);
    });
  }

  void _stopLinkRetry(String machineId) {
    _linkRetryTimers.remove(machineId)?.cancel();
  }

  void _stopAllLinkRetries() {
    for (final timer in _linkRetryTimers.values) {
      timer.cancel();
    }
    _linkRetryTimers.clear();
  }

  void _stopAllOfflineRetries() {
    for (final timer in _offlineRetryTimers.values) {
      timer.cancel();
    }
    _offlineRetryTimers.clear();
    _offlinePollsInFlight.clear();
  }

  void _startAgentSyncTimer(String machineId) {
    if (_agentSyncTimers.containsKey(machineId)) return;
    _agentSyncTimers[machineId] = Timer.periodic(agentSyncInterval, (_) {
      final machine = machineStates[machineId];
      if (machine == null) {
        _stopAgentSyncTimer(machineId);
        return;
      }
      unawaited(_syncAgentsIfChanged(machine));
    });
  }

  void _stopAgentSyncTimer(String machineId) {
    _agentSyncTimers.remove(machineId)?.cancel();
  }

  void _stopAllAgentSyncTimers() {
    for (final timer in _agentSyncTimers.values) {
      timer.cancel();
    }
    _agentSyncTimers.clear();
  }

  /// Silent safety-net reconciliation, ticked every [agentSyncInterval] while a machine is connected.
  /// Only writes/notifies if the fetched list actually differs from what's already shown — a steady
  /// state where push events (agent_synced et al.) have kept everything in sync produces zero visible
  /// effect. Deliberately does not touch agentLoadStatus/agentsLoadError/notifyListeners on failure:
  /// a real connectivity problem is already surfaced by the push path and the existing offline
  /// detection in _performMachineDataLoad, and a quiet background tick should not fight either.
  Future<void> _syncAgentsIfChanged(MachineState machine) async {
    if (machine.connectionStatus != ConnectionStatus.connected) return;
    if (machine.agentsLoadInFlight != null) {
      return; // a real (foreground) load already owns this tick
    }
    final connection = _conn(machine.machine.machineId);
    try {
      final response = await connection.request(
        'agents_list',
        timeout: const Duration(seconds: 10),
      );
      final agents = (response['agents'] as List<dynamic>? ?? [])
          .map((item) => Agent.fromJson(item as Map<String, dynamic>))
          .toList();
      if (agentsEqual(machine.agents, agents)) return;
      _replaceAgents(machine, agents);
      notifyListeners();
    } catch (_) {
      // Silent by design — see doc comment above.
    }
  }

  /// Order-insensitive value equality for [Agent] lists — [Agent] has no operator== override, and a
  /// backend that returns the same agents in a different order must not register as "changed".
  ///
  /// ⚠️ Every field of [Agent] that the UI reads belongs here. This list is hand-maintained, and the
  /// cost of forgetting one is silent: the poll fetches the truth, compares it, decides nothing
  /// happened, and throws it away — so the field stays frozen at whatever it was for as long as the
  /// app runs. That is exactly what `grid` did. An agent moved onto another grid by anything other
  /// than this app's own foreground path kept its old assignment on screen, and the retarget banner
  /// went on offering to move an agent that was already where the user had put it. Add the field
  /// here in the same commit you add it to [Agent].
  @visibleForTesting
  static bool agentsEqual(List<Agent> a, List<Agent> b) {
    if (a.length != b.length) return false;
    final byId = {for (final agent in a) agent.id: agent};
    for (final agent in b) {
      final prev = byId[agent.id];
      if (prev == null ||
          prev.name != agent.name ||
          prev.sessionId != agent.sessionId ||
          prev.engine != agent.engine ||
          prev.engineDisplayName != agent.engineDisplayName ||
          prev.engineIconHint != agent.engineIconHint ||
          prev.parentAgentId != agent.parentAgentId ||
          prev.status != agent.status ||
          prev.terminalAvailable != agent.terminalAvailable ||
          prev.terminalUnavailableReason != agent.terminalUnavailableReason ||
          prev.grid != agent.grid) {
        return false;
      }
    }
    return true;
  }

  /// Public retry hook used by the offline join guide's "Retry now" action.
  Future<void> retryOfflineMachine(String machineId) =>
      _pollOfflineMachine(machineId);

  /// Runs `harness link connect <machineId> --stdin --json` (via [CliLink]) for a machine the
  /// relay reported `NO_PEER_LINK` for, then reconnects it. Returns null on success, or an error
  /// message to show inline. The app never sees the password's cryptographic use — this just
  /// pipes it to the CLI on stdin, the same as typing it at a terminal prompt would.
  Future<String?> connectWithPassword(
    String machineId,
    String password, {
    void Function(String stage)? onProgress,
  }) async {
    if (password.isEmpty) return 'Enter the remote password first';
    final result = await cliLink.connect(
      machineId,
      password,
      onProgress: onProgress,
    );
    if (result.error != null) return result.error;
    final targetId = result.linkedMachineId ?? machineId;
    final state = machineStates[targetId];
    if (state != null) {
      state.needsLink = false;
      state.agentLoadStatus = AgentLoadStatus.idle;
      notifyListeners();
      // The old WsConn closed itself permanently on NO_PEER_LINK — connFor() would otherwise see a
      // matching endpointKey and hand back that dead connection instead of dialing a fresh one.
      await _pool?.closeMachine(targetId);
      _connectMachine(state);
    }
    return null;
  }

  List<LinkedMachine> linkedMachines = [];
  bool linkedMachinesLoading = false;
  String? linkedMachinesError;

  /// Sets (or replaces) THIS machine's persistent remote password (`harness remote-password
  /// set --stdin --json`) — another machine later connects with `connectWithPassword` using the
  /// same password, no token copy/paste involved.
  Future<RemotePasswordSetResult> setRemotePassword(String password) =>
      cliLink.setRemotePassword(password);

  /// Queries THIS machine's remote-password state (`harness remote-password status --json`).
  Future<RemotePasswordStatus> remotePasswordStatus() =>
      cliLink.remotePasswordStatus();

  /// Clears THIS machine's remote password (`harness remote-password clear --json`). Returns null
  /// on success.
  Future<String?> clearRemotePassword() => cliLink.clearRemotePassword();

  /// Refreshes the "machines this one trusts" list (`harness link list`).
  Future<void> refreshLinkedMachines() async {
    linkedMachinesLoading = true;
    notifyListeners();
    final result = await cliLink.list();
    linkedMachinesLoading = false;
    linkedMachinesError = result.error;
    linkedMachines = result.machines;
    notifyListeners();
  }

  /// Removes a linked machine's trust pin, then refreshes the list. Returns null on success.
  Future<String?> unlinkMachine(String machineId) async {
    final error = await cliLink.unlink(machineId);
    if (error == null) await refreshLinkedMachines();
    return error;
  }

  Future<void> _pollOfflineMachine(String machineId) async {
    final machine = machineStates[machineId];
    if (machine == null ||
        machine.nodeOnline != false ||
        (!machine.isLocalMachine && machine.pendingOfflineAgentId == null) ||
        _offlinePollsInFlight.contains(machineId)) {
      return;
    }
    _offlinePollsInFlight.add(machineId);
    try {
      if (machine.isLocalMachine) {
        final discovery =
            localCliDiscovery ?? LocalCliDiscovery(config: config);
        final localComputerId = await discovery.computerId();
        if (localComputerId == null ||
            _normalizeComputerId(machine.machine.computerId) !=
                localComputerId) {
          return;
        }
        final endpoint = await discovery.discover(
          expectedComputerId: localComputerId,
        );
        if (endpoint == null || endpoint.computerId != localComputerId) return;
        machine.localEndpoint = endpoint;
        machine.localOnly = true;
        machine.transportMode = MachineTransportMode.localPlaintext;
        machine.nodeOnline = true;
        _connectMachine(machine);
        await _loadMachineData(machine, force: true);
        final pending = machine.pendingOfflineAgentId;
        if (pending != null) unawaited(_recoverPendingAgent(machine, pending));
        return;
      }
      final latest = (await _fetchMachines()).where(
        (item) => item.machineId == machineId,
      );
      if (latest.isEmpty) return;
      final reportedOnline = _nodeOnlineFromStatus(latest.first.status);
      if (reportedOnline == null) return;
      machine.machine = latest.first;
      await _applyNodeStatus(machine, reportedOnline);
    } catch (error) {
      debugPrint('offline node retry failed: $machineId: $error');
    } finally {
      _offlinePollsInFlight.remove(machineId);
    }
  }

  /// Open only the machine data sockets after discovery. Terminal panes remain
  /// lazy and are attached only when the user selects an agent row.
  void _autoConnectAndLoadMachines() {
    final visible = machines.map((machine) => machine.machineId).toSet();
    expandedMachines
      ..removeWhere((machineId) => !visible.contains(machineId))
      ..addAll(visible);
    if (machines.isEmpty) {
      selectedMachineId = null;
      return;
    }
    if (!visible.contains(selectedMachineId)) {
      // This computer, when it is one of them. The backend's order is its own
      // business and the local machine is not reliably first in it — landing on
      // someone else's box is a poor default when the user's own is right there.
      selectedMachineId = machines
          .firstWhere(
            (machine) =>
                machineStates[machine.machineId]?.isLocalMachine == true,
            orElse: () => machines.first,
          )
          .machineId;
    }
    for (final machine in machines) {
      _connectMachine(machineStates[machine.machineId]!);
      unawaited(_loadMachineData(machineStates[machine.machineId]!));
    }
  }

  Future<void> retryMachines() async {
    try {
      await refreshMachines();
      _lastError = null;
    } catch (error) {
      _lastError = 'Could not load machines: $error';
      notifyListeners();
      return;
    }
    await Future.wait(expandedMachines.toList().map(reloadMachineData));
    notifyListeners();
  }

  void toggleExpand(String machineId) {
    if (expandedMachines.contains(machineId)) {
      expandedMachines.remove(machineId);
    } else {
      expandedMachines.add(machineId);
      selectedMachineId = machineId;
      final machine = machineStates[machineId];
      if (machine != null) {
        _connectMachine(machine);
        unawaited(_loadMachineData(machine));
      }
    }
    notifyListeners();
  }

  /// Selects a machine without toggling its tree. Setup/status rows use this
  /// action so clicking an E2EE prompt always opens that machine's setup pane.
  Future<void> selectMachineForSetup(String machineId) async {
    final machine = machineStates[machineId];
    if (machine == null) return;
    _dismissedLinkPrompts.remove(machineId);
    selectedMachineId = machineId;
    expandedMachines.add(machineId);
    // Nothing is torn down here any more. That line existed because the content
    // area was one terminal belonging to whichever machine was selected, so
    // browsing to a second machine's setup form would otherwise have left the
    // first machine's terminal rendering underneath it. Tiles now say what they
    // are on their own and outlive the rail's selection, which makes selecting
    // a machine navigation again — and closing someone's running terminals
    // because they clicked a row would be the surprise, not the fix.
    //
    // The form itself arrives as a tile, which is the only way it can arrive at
    // all: a machine that needs linking has no agents to open.
    showMachinePane(machineId);
    _connectMachine(machine);
    notifyListeners();
  }

  void _connectMachine(MachineState machine) {
    // connFor() starts a new socket and reports `connecting` through onStatus,
    // or returns the existing socket with its current status intact. Do not
    // overwrite an already-connected socket when the user collapses and
    // re-expands the machine row; doing so leaves the UI permanently yellow
    // and disables every agent even though the transport is still ready.
    if (_pool != null &&
        (!machine.isLocalMachine || machine.usesLocalTransport)) {
      _conn(machine.machine.machineId);
    }
  }

  WsConn _conn(String machineId) {
    // The local-manual dev fixture exercises a locally-run backend+node stack directly (no real
    // `harness` CLI involved) — keep it on the old direct-cloud dial. Every other (real) machine now
    // goes through the local CLI daemon regardless of whether it's this computer's own machine or a
    // relayed one: the CLI proxies foreign machines to backend transparently (see `remoteRelay.ts` in
    // the harness CLI repo), so this app never dials backend's WS directly anymore.
    final connection = localManualFixture != null
        ? _pool!.connFor(machineId, transportKind: WsTransportKind.cloudE2ee)
        : _pool!.connFor(
            machineId,
            transportKind: WsTransportKind.localPlaintext,
            localWsUri: _cliEndpoint?.wsUri,
            localProtocolVersion:
                _cliEndpoint?.protocolVersion ?? localWsProtocolVersion,
          );
    _wireConnectionHooks(connection, machineId);
    return connection;
  }

  // Every machine — this computer's own, or a relayed one — now speaks the same plaintext local wire
  // protocol to the CLI (which terminates E2EE itself for relayed machines; see remoteRelay.ts in the
  // harness CLI repo). There is no per-machine branching left here at all.
  //
  // Known gap: LocalManualFixture (main_local_manual.dart, a compile-time-gated dev entry point that
  // exercises a locally-run backend+machine-node stack without SSO) used to run its OWN simulated E2EE
  // handshake against that local stack. That simulation depended on the crypto this app no longer
  // carries — the fixture now sends/receives plaintext-local-framed terminal data like every other
  // machine, which needs the target local machine-node to also expect plaintext for the fixture to
  // keep working end-to-end. Fixing that (if still desired) is a machine-node-side change, out of
  // scope here.
  void _wireConnectionHooks(WsConn connection, String machineId) {
    connection.onBinaryFrame = (frame) =>
        _handleTerminalBinary(machineId, frame);
  }

  /// Bulk terminal data for a machine, which may now be feeding several tiles.
  ///
  /// Offered to EVERY tile on that machine rather than routed by this side:
  /// each session already drops a frame whose `streamId` is not its own, and
  /// that check is the authority on which stream a frame belongs to. Choosing
  /// here instead would mean keeping a second copy of that mapping in sync with
  /// the first, and the copy that drifts is the one nobody is looking at.
  Future<void> _handleTerminalBinary(String machineId, Uint8List raw) async {
    final targets = panesFor(machineId)
        .map((pane) => pane.session)
        .whereType<TerminalSession>()
        .toList();
    if (targets.isEmpty) return;
    final clear = decodeTerminalLocal(raw);
    if (clear == null) {
      // Undecodable says the transport is wrong, not that one stream is — so
      // it goes to all of them.
      for (final terminal in targets) {
        terminal.transportLost('Binary terminal frame could not be decoded');
      }
      return;
    }
    for (final terminal in targets) {
      await terminal.handleBinary(clear);
    }
  }

  Future<bool> _sendTerminalBinary(
    String machineId,
    TerminalBinaryFrame frame,
  ) async {
    final encoded = encodeTerminalLocal(frame);
    if (encoded == null) return false;
    return _conn(machineId).sendTerminalBinary(encoded);
  }

  Future<void> _loadMachineData(
    MachineState machine, {
    bool force = false,
  }) async {
    if (machine.agentLoadStatus == AgentLoadStatus.loaded && !force) return;
    if (machine.isLocalMachine && !machine.usesLocalTransport) {
      machine.transportMode = MachineTransportMode.localOffline;
      machine.nodeOnline = false;
      machine.agentsRefreshing = false;
      machine.agentsLoadError = 'Harness is offline — run harness login';
      machine.agentLoadStatus = machine.agents.isEmpty
          ? AgentLoadStatus.error
          : AgentLoadStatus.loaded;
      notifyListeners();
      return;
    }
    final inFlight = machine.agentsLoadInFlight;
    if (inFlight != null) return inFlight;
    late final Future<void> load;
    load = _performMachineDataLoad(machine).whenComplete(() {
      if (identical(machine.agentsLoadInFlight, load)) {
        machine.agentsLoadInFlight = null;
      }
    });
    machine.agentsLoadInFlight = load;
    return load;
  }

  Future<void> _performMachineDataLoad(MachineState machine) async {
    final hadAgents = machine.agents.isNotEmpty;
    machine.agentsRefreshing = hadAgents;
    if (!hadAgents) machine.agentLoadStatus = AgentLoadStatus.loading;
    machine.agentsLoadError = null;
    notifyListeners();
    final connection = _conn(machine.machine.machineId);
    debugPrint('agents_list start: ${machine.machine.machineId}');
    try {
      final response = await connection.request(
        'agents_list',
        timeout: const Duration(seconds: 10),
      );
      final agents = (response['agents'] as List<dynamic>? ?? [])
          .map((item) => Agent.fromJson(item as Map<String, dynamic>))
          .toList();
      _replaceAgents(machine, agents);
      machine.agentLoadStatus = AgentLoadStatus.loaded;
      machine.agentsRefreshing = false;
      machine.agentsLoadError = null;
      debugPrint(
        'agents_list success: ${machine.machine.machineId} '
        '(${machine.agents.length} agents)',
      );
      await _loadTerminalCapabilities(machine, connection);
    } catch (error) {
      machine.agentsRefreshing = false;
      // A request timing out while the local relay session still nominally reports "connected" means
      // the remote node itself has stopped answering — exactly what a REST-status flip to offline
      // means elsewhere, so route it through _applyNodeStatus (not just `nodeOnline = false`) so the
      // pending agent gets captured for auto-reattach, same as any other offline detection path.
      if (error is WsRequestTimeout) {
        machine.agentsLoadError = machine.isLocalMachine
            ? 'Harness is offline — run harness login'
            : 'Harness is offline — run harness start on that machine';
        if (machine.nodeOnline != false) {
          unawaited(_applyNodeStatus(machine, false));
        }
        if (!machine.isLocalMachine) {
          // The relay's cached upstream session can go stale at the E2EE-session layer without the
          // underlying transport ever closing — most commonly the relayed machine's own Harness
          // process restarting, which drops its in-memory session state but doesn't touch the socket.
          // Nothing else would ever notice, so force a fresh dial rather than let every future retry
          // keep timing out against the same dead session.
          unawaited(connection.forceReconnect());
        }
      } else {
        machine.agentsLoadError = 'Could not load agents: $error';
      }
      // A NO_PEER_LINK close already set needsLink (via onLocalFailure) perhaps a microtask before
      // this catch runs — don't downgrade that specific, actionable state back to a generic error.
      if (!hadAgents && machine.agentLoadStatus != AgentLoadStatus.needsLink) {
        machine.agentLoadStatus = AgentLoadStatus.error;
      }
      debugPrint('agents_list failed: ${machine.machine.machineId}: $error');
    }
    // Order matters: a restored tile for THIS machine claims its agent before
    // the first-run convenience gets to look, so the two can never both open.
    _attachPendingPanes(machine);
    _autoPickFirstAgent();
    notifyListeners();
  }

  /// Whether the app has already opened a terminal on its own.
  ///
  /// Once, at startup, and never again: a later refresh must not reopen a
  /// terminal the user deliberately closed, and a machine that reconnects
  /// mid-session must not yank the pane away from whatever they are watching.
  bool _autoPickedAgent = false;

  /// Open the first agent on this computer, so the app arrives at work instead
  /// of at an instruction.
  ///
  /// "Select a machine, then an agent terminal" is a correct sentence and a
  /// poor first screen: in the ordinary case — one computer, agents already
  /// running on it — there is exactly one thing the user was going to click.
  ///
  /// Runs after a machine's data load rather than after the machine list,
  /// because [selectAgent] refuses on three counts that are only settled by
  /// then: the agent must exist, it must have a tmux terminal, and the
  /// machine's terminal protocol must have been negotiated. Called on every
  /// load and guarded, rather than wired to one specific load, because which
  /// machine answers first is not something this side decides.
  void _autoPickFirstAgent() {
    if (_autoPickedAgent || panes.isNotEmpty) return;

    // This computer first. A remote machine may well answer sooner, and
    // opening a terminal on someone else's box because its list arrived first
    // is a surprise, not a convenience.
    MachineState? target;
    for (final state in machineStates.values) {
      if (state.isLocalMachine) {
        target = state;
        break;
      }
    }
    target ??= machineStates.length == 1 ? machineStates.values.first : null;
    if (target == null) return;
    if (target.nodeOnline == false) return;
    if (!target.terminalCapabilityAvailable) return;

    for (final agent in target.agents) {
      if (!agent.terminalAvailable) continue;
      _autoPickedAgent = true;
      unawaited(selectAgent(target.machine.machineId, agent.id));
      return;
    }
  }

  Future<void> _loadTerminalCapabilities(
    MachineState machine,
    WsConn connection,
  ) async {
    try {
      final result = await connection.request(
        'terminal_capabilities',
        payload: {'protocolVersion': TerminalSession.protocolVersion},
        timeout: const Duration(seconds: 8),
      );
      machine.terminalCapabilityLoaded = true;
      machine.terminalCapabilityAvailable =
          result['protocolVersion'] == TerminalSession.protocolVersion &&
          result['backend'] == 'tmux' &&
          result['available'] == true;
      machine.terminalCapabilityError = machine.terminalCapabilityAvailable
          ? null
          : 'tmux terminal streaming is unavailable';
    } catch (_) {
      machine.terminalCapabilityLoaded = true;
      machine.terminalCapabilityAvailable = false;
      machine.terminalCapabilityError = 'Could not negotiate terminal protocol';
    }
  }

  void _replaceAgents(MachineState machine, List<Agent> agents) {
    final nextIds = agents.map((agent) => agent.id).toSet();
    for (final agentId in machine.processingAgentIds.difference(nextIds)) {
      _cancelTurnActivity(machine.machine.machineId, agentId);
    }
    machine.agents = agents;
    final pending = machine.pendingOfflineAgentId;
    if (pending != null && !nextIds.contains(pending)) {
      machine.pendingOfflineAgentId = null;
      _stopOfflineRetry(machine.machine.machineId);
    }
    if (machine.activeAgentId != null &&
        !nextIds.contains(machine.activeAgentId) &&
        panesFor(machine.machine.machineId).isEmpty) {
      machine.activeAgentId = null;
    }
    machine.processingAgentIds.removeWhere((id) => !nextIds.contains(id));
    machine.sessionAgentIds.clear();
    for (final agent in agents) {
      final sessionId = agent.sessionId;
      if (sessionId != null) machine.sessionAgentIds[sessionId] = agent.id;
    }
    for (final sessionId in machine.pendingProcessingSessions.toList()) {
      final agentId = machine.sessionAgentIds[sessionId];
      if (agentId == null) continue;
      machine.pendingProcessingSessions.remove(sessionId);
      _markAgentProcessing(machine, agentId);
    }
  }

  void _upsertAgent(MachineState machine, Agent agent) {
    final index = machine.agents.indexWhere((item) => item.id == agent.id);
    if (index == -1) {
      machine.agents = [...machine.agents, agent];
    } else {
      machine.agents = [...machine.agents]..[index] = agent;
    }
    machine.sessionAgentIds.removeWhere((_, id) => id == agent.id);
    final sessionId = agent.sessionId;
    if (sessionId != null) {
      machine.sessionAgentIds[sessionId] = agent.id;
      if (machine.pendingProcessingSessions.remove(sessionId)) {
        _markAgentProcessing(machine, agent.id);
      }
    }
    machine.agentLoadStatus = AgentLoadStatus.loaded;
    machine.agentsLoadError = null;
  }

  void _renameAgent(MachineState machine, String agentId, String name) {
    final index = machine.agents.indexWhere((agent) => agent.id == agentId);
    if (index == -1 || name.trim().isEmpty) return;
    final cleanName = name.trim();
    machine.agents = [...machine.agents]
      ..[index] = machine.agents[index].copyWith(name: cleanName);
    for (final pane in panesFor(machine.machine.machineId)) {
      if (pane.agentId != agentId) continue;
      pane.session?.renameAgent(cleanName);
    }
  }

  Future<void> _removeAgent(MachineState machine, String agentId) async {
    machine.agents = machine.agents
        .where((agent) => agent.id != agentId)
        .toList();
    machine.sessionAgentIds.removeWhere((_, id) => id == agentId);
    _cancelTurnActivity(machine.machine.machineId, agentId);
    if (machine.activeAgentId == agentId) machine.activeAgentId = null;
    if (machine.pendingOfflineAgentId == agentId) {
      machine.pendingOfflineAgentId = null;
      _stopOfflineRetry(machine.machine.machineId);
    }
    // Every tile showing it, not just the focused one — and without
    // `terminal_close`, which would be addressed to an agent the machine has
    // already destroyed.
    final machineId = machine.machine.machineId;
    for (final pane in panes.toList()) {
      if (pane.machineId != machineId || pane.agentId != agentId) continue;
      await _detachSession(pane, sendClose: false);
      panes.remove(pane);
      if (focusedPaneId == pane.id) {
        focusedPaneId = panes.isEmpty ? null : panes.first.id;
      }
    }
    _persistLayout();
  }

  String? _eventAgentId(
    MachineState machine,
    Map<String, dynamic> event,
    Map<String, dynamic> payload,
  ) {
    final explicit = payload['agentId'] ?? event['agentId'];
    if (explicit is String && explicit.isNotEmpty) return explicit;
    final session = payload['sessionId'] ?? event['dbSessionId'];
    if (session is! String || session.isEmpty) return null;
    return machine.sessionAgentIds[session];
  }

  String? _eventSessionId(
    Map<String, dynamic> event,
    Map<String, dynamic> payload,
  ) {
    final session = payload['sessionId'] ?? event['dbSessionId'];
    return session is String && session.isNotEmpty ? session : null;
  }

  String _turnActivityKey(String machineId, String agentId) =>
      '$machineId\u0000$agentId';

  void _markAgentProcessing(MachineState machine, String agentId) {
    machine.processingAgentIds.add(agentId);
    final key = _turnActivityKey(machine.machine.machineId, agentId);
    _turnActivityWatchdogs.remove(key)?.cancel();
    _turnActivityWatchdogs[key] = Timer(turnActivityTimeout, () {
      _turnActivityWatchdogs.remove(key);
      final current = machineStates[machine.machine.machineId];
      if (!identical(current, machine)) return;
      if (machine.processingAgentIds.remove(agentId)) notifyListeners();
    });
  }

  void _cancelTurnActivity(String machineId, String agentId) {
    _turnActivityWatchdogs
        .remove(_turnActivityKey(machineId, agentId))
        ?.cancel();
    machineStates[machineId]?.processingAgentIds.remove(agentId);
  }

  void _clearMachineActivity(MachineState machine) {
    for (final agentId in machine.processingAgentIds.toList()) {
      _cancelTurnActivity(machine.machine.machineId, agentId);
    }
    machine.processingAgentIds.clear();
    machine.pendingProcessingSessions.clear();
  }

  void _clearAllTurnActivity() {
    for (final timer in _turnActivityWatchdogs.values) {
      timer.cancel();
    }
    _turnActivityWatchdogs.clear();
    for (final machine in machineStates.values) {
      machine.processingAgentIds.clear();
      machine.pendingProcessingSessions.clear();
    }
  }

  Future<void> reloadMachineData(String machineId) async {
    final machine = machineStates[machineId];
    if (machine == null) return;
    _connectMachine(machine);
    await _loadMachineData(machine, force: true);
  }

  /// One-level directory listing on the remote machine, for the New Agent folder browser.
  /// Returns `{path, entries: [{name, isDir}], truncated}` or `{error}` — the caller renders both.
  Future<Map<String, dynamic>> listRemoteFolder(
    String machineId,
    String? path,
  ) async {
    final connection = _conn(machineId);
    try {
      return await connection.request(
        'fs_list_dir',
        payload: {
          ...?path == null ? null : {'path': path},
        },
        timeout: const Duration(seconds: 10),
      );
    } catch (error) {
      return {'error': 'UNREACHABLE'};
    }
  }

  /// Spawns a new engine session on [machineId] via the harness CLI, then jumps into its terminal.
  /// Returns null on success, or an error message to show inline in the New Agent dialog.
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    bool bypassPermission = false,
    GridAgentOverride? grid,
  }) async {
    final machine = machineStates[machineId];
    if (machine == null) return 'Machine not found';
    final connection = _conn(machineId);
    Map<String, dynamic> result;
    try {
      result = await connection.request(
        'agent_create',
        payload: {
          'engine': engine,
          'cwd': folder,
          'bypassPermission': bypassPermission,
          // Only when the user picked a grid, so a build with no selection
          // sends byte for byte the frame it sent before this existed — see
          // GridAgentOverride for what the CLI still has to do with it.
          if (grid != null) 'grid': grid.toJson(),
        },
        timeout: const Duration(seconds: 20),
      );
    } catch (error) {
      return 'Create agent failed: $error';
    }
    final error = result['error'];
    if (error is String) {
      return error == 'UNSUPPORTED_ON_REMOTE'
          ? 'Update the harness CLI on this machine to use New Agent'
          : 'Create agent failed: $error';
    }
    final raw = result['agent'];
    if (raw is! Map) return 'Create agent failed: malformed response';
    final agent = Agent.fromJson(Map<String, dynamic>.from(raw));
    // Idempotent on agent.id — safe even if the CLI's own agent_synced push for this session
    // arrives separately (it's fire-and-forget on the CLI side and unordered relative to this reply).
    _upsertAgent(machine, agent);
    notifyListeners();
    await selectAgent(machineId, agent.id);
    return null;
  }

  /// Moves an already-running agent onto [grid].
  ///
  /// This RESTARTS the agent. A process's environment is fixed when it is exec'd, so a live engine
  /// cannot be re-pointed — the CLI respawns the pane in place (same pane, same agent id, same
  /// scrollback) with the grid's environment and `--resume`, which brings the conversation back but
  /// not a turn that was in flight. That is why the CLI refuses a busy agent rather than deciding for
  /// the user, and why nothing here is automatic.
  ///
  /// Returns null on success, or a message to show the user.
  Future<String?> moveAgentToGrid(
    String machineId,
    String agentId,
    GridAgentOverride grid,
  ) async {
    final machine = machineStates[machineId];
    if (machine == null) return 'Machine not found';
    Map<String, dynamic> result;
    try {
      result = await _conn(machineId).request(
        'agent_retarget',
        payload: {'agentId': agentId, 'grid': grid.toJson()},
        timeout: const Duration(seconds: 20),
      );
    } catch (error) {
      return 'Move failed: $error';
    }
    final error = result['error'];
    if (error is String) return _retargetMessage(error, result['detail']);
    // The pane now runs a different process, and its grid is re-read by the CLI's next discovery
    // pass. Ask for the list rather than guessing here: this method must not be the second place
    // that has an opinion about which grid an agent is on.
    await _loadMachineData(machine, force: true);
    return null;
  }

  /// [moveAgentToGrid]'s answer when the agent was already gone.
  ///
  /// A sentinel rather than an error string because nobody can act on it, and rather than null
  /// because it did not move either — the caller must be able to leave it out of both tallies.
  static const String agentVanished = 'AGENT_GONE';

  /// Turns a retarget refusal into something the user can act on.
  ///
  /// Every one of these is a deliberate refusal in the CLI, not a crash, so each has a way out worth
  /// naming. `detail`, when present, already reads as a sentence and is preferred to anything
  /// rewritten here.
  static String _retargetMessage(String error, Object? detail) {
    if (error == 'AGENT_NOT_FOUND') return agentVanished;
    if (error == 'AGENT_BUSY') {
      return 'It is running a turn. Move it when the turn finishes.';
    }
    if (error == 'UNSUPPORTED_ON_REMOTE') {
      return 'Update the harness CLI on this machine to move running agents.';
    }
    if (detail is String && detail.isNotEmpty) return detail;
    return 'Move failed: $error';
  }

  /// Renames a machine via `PATCH /api/machines/:machineId` (control-plane REST — the machine's
  /// `name` is backend-owned, unlike an agent's, which lives on the harness CLI). Returns null on
  /// success, or an error message to show inline in the caller's dialog.
  Future<String?> renameMachine(String machineId, String name) async {
    final state = machineStates[machineId];
    if (state == null) return 'Machine not found';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty';
    try {
      await api.renameMachine(machineId: machineId, name: trimmed);
    } catch (error) {
      return 'Rename failed: $error';
    }
    state.machine = state.machine.copyWith(name: trimmed);
    final index = machines.indexWhere((m) => m.machineId == machineId);
    if (index != -1) machines[index] = state.machine;
    notifyListeners();
    return null;
  }

  /// Permanently deletes a machine from the account (backend `DELETE /api/machines/:id`) — not to
  /// be confused with [unlinkMachine], which only drops this computer's local E2EE trust pin and
  /// leaves the machine itself intact. Returns null on success, or an error message to show inline.
  Future<String?> deleteMachine(String machineId) async {
    final state = machineStates[machineId];
    if (state == null) return 'Machine not found';
    try {
      await api.deleteMachine(machineId: machineId);
    } catch (error) {
      return 'Delete failed: $error';
    }
    // Any tile still showing this machine would otherwise sit forever in the "waiting to answer"
    // busy state, since the machine can never be found again after this.
    for (final pane in panesFor(machineId).toList()) {
      await closePane(pane.id, persist: false);
    }
    _stopAgentSyncTimer(machineId);
    machineStates.remove(machineId);
    machines.removeWhere((m) => m.machineId == machineId);
    if (selectedMachineId == machineId) selectedMachineId = null;
    notifyListeners();
    return null;
  }

  /// Renames an agent via `agent_update`. Returns null on success, or an error message to show
  /// inline in the caller's dialog.
  Future<String?> renameAgent(
    String machineId,
    String agentId,
    String name,
  ) async {
    final machine = machineStates[machineId];
    if (machine == null) return 'Machine not found';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty';
    Map<String, dynamic> result;
    try {
      result = await _conn(
        machineId,
      ).request('agent_update', payload: {'agentId': agentId, 'name': trimmed});
    } catch (error) {
      return 'Rename failed: $error';
    }
    final error = result['error'];
    if (error is String) return 'Rename failed: $error';
    _renameAgent(machine, agentId, trimmed);
    notifyListeners();
    return null;
  }

  /// Deletes an agent via `agent_delete`. Returns null on success, or an error message to show
  /// inline in the caller's dialog.
  Future<String?> deleteAgent(String machineId, String agentId) async {
    final machine = machineStates[machineId];
    if (machine == null) return 'Machine not found';
    Map<String, dynamic> result;
    try {
      result = await _conn(machineId)
          .request('agent_delete', payload: {'agentId': agentId});
    } catch (error) {
      return 'Delete failed: $error';
    }
    final error = result['error'];
    if (error is String) return 'Delete failed: $error';
    await _removeAgent(machine, agentId);
    notifyListeners();
    return null;
  }

  /// Restarts an agent via `agent_restart` — exits its current engine process and relaunches it
  /// daemon-side, resuming its session where possible.
  ///
  /// The reply carries the same fresh `Agent` shape `agent_synced` pushes once the new process is
  /// confirmed, so this upserts from the reply directly — idempotent on `agent.id`, same as
  /// [createAgent], and safe even if the CLI's own `agent_synced` push for the restart arrives
  /// separately (fire-and-forget on the CLI side, unordered relative to this reply).
  Future<RestartAgentResult> restartAgent(
    String machineId,
    String agentId,
  ) async {
    final machine = machineStates[machineId];
    if (machine == null) {
      return const RestartAgentResult(error: 'Machine not found');
    }
    Map<String, dynamic> result;
    try {
      result = await _conn(machineId)
          .request('agent_restart', payload: {'agentId': agentId});
    } catch (error) {
      return RestartAgentResult(error: 'Restart failed: $error');
    }
    final error = result['error'];
    if (error is String) {
      final detail = result['detail'];
      return RestartAgentResult(
        error: detail is String ? detail : 'Restart failed: $error',
      );
    }
    final raw = result['agent'];
    if (raw is Map) {
      try {
        _upsertAgent(machine, Agent.fromJson(Map<String, dynamic>.from(raw)));
        notifyListeners();
      } catch (_) {
        // Malformed reply agent — harmless, the CLI's own agent_synced push still lands.
      }
    }
    // Absent (older daemon build) reads as true — assume resumed rather than warn about a fresh
    // session that may not have happened, since this field is purely additive UI polish.
    final resumed = result['resumed'];
    return RestartAgentResult(resumed: resumed is bool ? resumed : true);
  }

  Future<void> _applyNodeStatus(MachineState machine, bool online) async {
    if (_disposed) return;
    final machineId = machine.machine.machineId;
    final wasOnline = machine.nodeOnline;
    machine.nodeOnline = online;

    if (!online) {
      // Every tile on it, not just the focused one: the machine is what went
      // away, so a tile of the same machine sitting in another corner of the
      // grid is just as dead and must say so rather than keep showing a
      // terminal that can no longer receive anything.
      final message = machine.isLocalMachine
          ? 'Harness is offline. Run harness login to reconnect.'
          : 'Harness is offline. Run harness start on that machine to reconnect.';
      for (final pane in panesFor(machineId)) {
        final session = pane.session;
        if (session == null) continue;
        machine.activeAgentId ??= session.agentId;
        machine.pendingOfflineAgentId ??= session.agentId;
        // Do not send terminal_close: the adapter is already gone and the
        // next client attachment should be the only stream that owns the pane.
        session.transportLost(message);
      }
      _startOfflineRetry(machine);
    } else {
      _stopOfflineRetry(machineId);
      if (wasOnline == false) {
        for (final pane in panesFor(machineId)) {
          pane.session?.transportLost(
            'Harness reconnected; restoring terminal…',
          );
        }
      }
      final pending = machine.pendingOfflineAgentId;
      if (pending != null) {
        unawaited(_recoverPendingAgent(machine, pending));
      } else if (panesFor(machineId).any(_paneNeedsAttach)) {
        // A tile restored from the saved layout has no pendingOfflineAgentId —
        // nothing of its was interrupted, it simply arrived before its machine
        // did. Without this it would sit on "Attaching…" forever on a machine
        // that has since come back, because every other route to _attachSession
        // runs off a load that nothing here would trigger.
        unawaited(_loadMachineData(machine, force: true));
      }
    }
    notifyListeners();
  }

  Future<void> _recoverPendingAgent(
    MachineState machine,
    String agentId,
  ) async {
    final machineId = machine.machine.machineId;
    if (!_offlineRecoveryInFlight.add(machineId)) return;
    try {
      // E2EE and agents_list can become ready in separate frames after a
      // node restart. Poll briefly instead of racing a single request.
      for (var attempt = 0; attempt < 40; attempt++) {
        if (_disposed ||
            machine.nodeOnline != true ||
            machine.pendingOfflineAgentId != agentId) {
          return;
        }
        await _loadMachineData(machine, force: true);
        final agent = machine.agents.cast<Agent?>().firstWhere(
          (candidate) => candidate?.id == agentId,
          orElse: () => null,
        );
        if (agent != null &&
            agent.terminalAvailable &&
            machine.terminalCapabilityAvailable) {
          machine.pendingOfflineAgentId = null;
          // Only reattach the terminal if the user is still on THIS machine — recovery can finish
          // well after the user has moved on to a different machine/agent, and forcing selectAgent
          // here would yank their focus back to what they were looking at before, mid-navigation.
          // The recovered agent still shows normally in the rail; they can click it themselves.
          if (selectedMachineId == machineId) {
            await selectAgent(machineId, agentId);
          } else {
            notifyListeners();
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      _offlineRecoveryInFlight.remove(machineId);
    }
  }

  /// Bring an agent up, the way a click on the rail means it.
  ///
  /// Already on screen means FOCUS it, never open it twice: the daemon keeps a
  /// single controller per agent, so a second open is a takeover — the window
  /// would fight itself and the first tile would go dark with
  /// `TERMINAL_TAKEN_OVER`.
  ///
  /// Otherwise it replaces the focused tile rather than adding one. Adding is a
  /// deliberate act (drag a row onto an empty slot); a click is navigation, and
  /// a click that silently grew the grid would make four terminals out of four
  /// glances at the rail.
  Future<void> selectAgent(String machineId, String agentId) async {
    final existing = paneOfAgent(machineId, agentId);
    if (existing != null) {
      selectedMachineId = machineId;
      machineStates[machineId]?.activeAgentId = agentId;
      focusPane(existing.id);
      final terminal = existing.session;
      if (terminal != null &&
          terminal.status != TerminalSessionStatus.opening &&
          terminal.status != TerminalSessionStatus.controlling &&
          terminal.status != TerminalSessionStatus.resyncing) {
        // A healthy pane is focus-only: opening the same daemon controller a
        // second time would take over its own first stream. A frozen/closed
        // pane is different — the explicit retry action needs a fresh session.
        await _detachSession(existing, sendClose: true);
        await _attachSession(existing);
      }
      return;
    }
    await assignAgentToPane(focusedPane?.id, machineId, agentId);
  }

  /// Show a MACHINE in the grid, for the states that belong to the machine
  /// rather than to any agent on it.
  ///
  /// It has to be a tile like any other — the alternative of letting a machine
  /// take over the whole content area would blank three working terminals
  /// belonging to two other machines. The one exception is a machine that
  /// already needs linking: that state now surfaces as a blocking popup
  /// (HomeScreen._maybeShowLinkDialog / showLinkMachineScreenDialog) rather
  /// than a tile, so opening one here too would just be a redundant "not
  /// linked" pane sitting behind it. Selecting is still worth doing — it's
  /// what makes the popup's gate notice this machine — the tile is not.
  void showMachinePane(String machineId) {
    final machine = machineStates[machineId];
    if (machine == null) return;
    _dismissedLinkPrompts.remove(machineId);
    selectedMachineId = machineId;
    if (machine.isRemote && !machine.isLocalMachine && machine.needsLink) {
      notifyListeners();
      return;
    }

    final existing = panes
        .where((pane) => pane.machineId == machineId && pane.agentId == null)
        .firstOrNull;
    if (existing != null) {
      focusedPaneId = existing.id;
      notifyListeners();
      return;
    }

    final target = focusedPane;
    if (target != null && target.agentId == null) {
      target.machineId = machineId;
      focusedPaneId = target.id;
      notifyListeners();
      return;
    }
    if (!canAddPane) {
      // Full grid: reuse the focused tile rather than refusing. Someone who
      // clicked "link required" asked to see it, and a click that did nothing
      // at all would read as a broken row.
      if (target != null) {
        unawaited(_detachSession(target, sendClose: true));
        target.machineId = machineId;
        target.agentId = null;
        _persistLayout();
        notifyListeners();
      }
      return;
    }
    final pane = TerminalPane(id: _nextPaneId++, machineId: machineId);
    panes.add(pane);
    focusedPaneId = pane.id;
    notifyListeners();
  }

  /// Put an agent into a specific tile, or into a NEW tile when [paneId] is
  /// null — which is what a drop on the empty slot means.
  Future<void> assignAgentToPane(
    int? paneId,
    String machineId,
    String agentId,
  ) async {
    final machine = machineStates[machineId];
    if (machine == null) return;

    Agent? agent;
    for (final candidate in machine.agents) {
      if (candidate.id == agentId) {
        agent = candidate;
        break;
      }
    }
    if (agent == null || !agent.terminalAvailable) return;

    // Moving an agent that is already somewhere else must not leave a copy
    // behind, for the takeover reason above. Dropping a row onto a second tile
    // is a MOVE.
    final duplicate = paneOfAgent(machineId, agentId);
    if (duplicate != null && duplicate.id != paneId) {
      await closePane(duplicate.id, persist: false);
    }

    TerminalPane? pane;
    if (paneId != null) {
      for (final candidate in panes) {
        if (candidate.id == paneId) {
          pane = candidate;
          break;
        }
      }
    }
    if (pane == null) {
      if (!canAddPane) return;
      pane = TerminalPane(
        id: _nextPaneId++,
        machineId: machineId,
        agentId: agentId,
      );
      panes.add(pane);
    } else {
      await _detachSession(pane, sendClose: true);
      pane.machineId = machineId;
      pane.agentId = agentId;
    }

    focusedPaneId = pane.id;
    selectedMachineId = machineId;
    _dismissedLinkPrompts.remove(machineId);
    machine.activeAgentId = agentId;
    _persistLayout();

    if (machine.nodeOnline == false) {
      machine.pendingOfflineAgentId = agentId;
      _startOfflineRetry(machine);
      notifyListeners();
      return;
    }
    if (!machine.terminalCapabilityAvailable) return;
    machine.pendingOfflineAgentId = null;
    _stopOfflineRetry(machineId);
    notifyListeners();
    await _attachSession(pane);
  }

  /// Open the stream for a tile that already knows what it wants.
  ///
  /// Separate from [assignAgentToPane] because a restored tile takes this path
  /// on its own, later, when its machine finally answers — the intent was
  /// settled at launch, and nothing about the selection should move again then.
  Future<void> _attachSession(TerminalPane pane) async {
    if (pane.session != null) return;
    final wantedAgentId = pane.agentId;
    if (wantedAgentId == null) return;
    final machine = machineStates[pane.machineId];
    if (machine == null) return;
    if (machine.nodeOnline == false) return;
    if (!machine.terminalCapabilityAvailable) return;

    Agent? agent;
    for (final candidate in machine.agents) {
      if (candidate.id == wantedAgentId) {
        agent = candidate;
        break;
      }
    }
    if (agent == null || !agent.terminalAvailable) return;

    final connection = _conn(pane.machineId);
    final terminal = TerminalSession(
      machineId: pane.machineId,
      agentId: agent.id,
      agentName: agent.name,
      engineId: agent.engine,
      send: connection.sendTerminalFrame,
      sendBinary: (frame) => _sendTerminalBinary(pane.machineId, frame),
      onOpenStalled: connection.forceReconnect,
    );
    pane.session = terminal;
    terminal.addListener(notifyListeners);
    notifyListeners();
    await terminal.open(waitForViewportSize: true);
  }

  Future<void> _detachSession(
    TerminalPane pane, {
    required bool sendClose,
  }) async {
    final terminal = pane.session;
    pane.session = null;
    if (terminal == null) return;
    terminal.removeListener(notifyListeners);
    if (sendClose) await terminal.close();
    terminal.dispose();
  }

  /// Take a tile off the grid.
  ///
  /// Closing sends `terminal_close`, which is what lets the daemon put the
  /// agent's tmux window back to the size it had before this app borrowed it —
  /// a tile that vanished without saying so would leave that agent living in a
  /// quarter-width terminal.
  /// Put the pane at [paneId] where [targetPaneId] is, and that one where this
  /// one was.
  ///
  /// A SWAP, not an insert. Position here is nothing but the index in [panes] —
  /// PaneGrid lays the list out row-major — and on a 2x2 grid "between two
  /// cells" names no place, so shifting the others would move tiles the user
  /// did not touch. Swapping leaves every other tile exactly where it was.
  ///
  /// Focus follows the PANE, not the slot: `focusedPaneId` is an id, so a tile
  /// that was focused stays focused after it moves, which is what the hand that
  /// dragged it expects.
  void reorderPane(int paneId, int targetPaneId) {
    if (paneId == targetPaneId) return;
    final from = panes.indexWhere((pane) => pane.id == paneId);
    final to = panes.indexWhere((pane) => pane.id == targetPaneId);
    if (from == -1 || to == -1) return;
    final moved = panes[from];
    panes[from] = panes[to];
    panes[to] = moved;
    _persistLayout();
    notifyListeners();
  }

  /// Move the focused pane one slot, for the keyboard twin of the drag.
  ///
  /// Stops at the ends rather than wrapping: the grid is a shape, not a ring,
  /// and a tile jumping from the last slot to the first reads as a bug.
  void movePaneBy(int delta) {
    final id = focusedPaneId;
    if (id == null) return;
    final from = panes.indexWhere((pane) => pane.id == id);
    if (from == -1) return;
    final to = from + delta;
    if (to < 0 || to >= panes.length) return;
    reorderPane(id, panes[to].id);
  }

  Future<void> closePane(int paneId, {bool persist = true}) async {
    final index = panes.indexWhere((pane) => pane.id == paneId);
    if (index == -1) return;
    final pane = panes.removeAt(index);
    await _detachSession(pane, sendClose: true);
    if (focusedPaneId == paneId) {
      focusedPaneId = panes.isEmpty
          ? null
          : panes[index.clamp(0, panes.length - 1)].id;
    }
    if (persist) _persistLayout();
    notifyListeners();
  }

  Future<void> _closeAllPanes({bool persist = true}) async {
    final open = panes.toList();
    panes.clear();
    focusedPaneId = null;
    for (final pane in open) {
      await _detachSession(pane, sendClose: true);
    }
    if (persist) _persistLayout();
  }

  void _persistLayout() {
    final store = _paneLayout;
    if (store == null) return;
    unawaited(
      store.save([
        for (final pane in panes)
          // Machine tiles are deliberately not remembered: they are a prompt
          // about a machine's state right now ("link required"), and reopening
          // to a wall of prompts the user already answered would be noise.
          if (pane.agentId case final agentId?)
            PaneLayoutEntry(
              machineId: pane.machineId,
              agentId: agentId,
              composerVisible: pane.composerVisible,
            ),
      ]),
    );
  }

  /// Rebuild the grid from disk as INTENT only — the tiles appear immediately,
  /// each saying which machine it is waiting for, and attach themselves as
  /// their machines answer.
  ///
  /// The tiles cannot wait for the machines: machines answer in an order this
  /// side does not decide, a restored grid commonly spans two of them, and one
  /// being slow or offline must not hold the others blank.
  Future<void> _restorePaneLayout() async {
    if (panes.isNotEmpty) return;
    final store = _paneLayout;
    if (store == null) return;
    final entries = await store.load();
    if (entries.isEmpty) return;
    for (final entry in entries) {
      panes.add(
        TerminalPane(
          id: _nextPaneId++,
          machineId: entry.machineId,
          agentId: entry.agentId,
        )..composerVisible = entry.composerVisible,
      );
    }
    focusedPaneId = panes.first.id;
    // A restored grid IS the choice of what to open, so the first-run
    // convenience must not also fire and add a fifth agent nobody asked for.
    _autoPickedAgent = true;
    notifyListeners();
  }

  /// Attach any tile of this machine that is still waiting.
  ///
  /// Called after every load rather than once, because the three things
  /// [_attachSession] insists on — the agent exists, it has a tmux terminal,
  /// and the machine's terminal protocol has been negotiated — become true at
  /// different moments, and a machine that goes away and returns has to be able
  /// to re-arrive at them.
  void _attachPendingPanes(MachineState machine) {
    final machineId = machine.machine.machineId;
    for (final pane in panes.toList()) {
      if (pane.machineId != machineId) continue;
      if (!_paneNeedsAttach(pane)) continue;
      // Covers a tile that never attached AND one holding a stream the machine
      // lost. Only the first used to be covered, and the second is why a
      // reconnect left every tile but one frozen on "restoring terminal…":
      // recovery ran off pendingOfflineAgentId, which is a single slot, so it
      // could only ever promise restoration to one of them.
      unawaited(_reattachPane(pane));
    }
  }

  /// Whether this tile is showing something that is not a working terminal.
  ///
  /// `takenOver` is deliberately absent. A stream someone else claimed is only
  /// reopened when a person asks for it — see [selectAgent], which is reached
  /// from the tile's own retry button. Doing it automatically would have two
  /// windows trading one terminal back and forth for as long as both stayed
  /// open.
  bool _paneNeedsAttach(TerminalPane pane) {
    if (pane.agentId == null) return false;
    final session = pane.session;
    if (session == null) return true;
    return switch (session.status) {
      TerminalSessionStatus.error || TerminalSessionStatus.closed => true,
      _ => false,
    };
  }

  /// Throw away a tile's dead stream and open a fresh one for the same agent.
  ///
  /// `sendClose: false` — the stream being replaced is one the machine has
  /// already lost or closed, so a close addressed to it would at best be
  /// ignored and at worst land on whatever took its place.
  Future<void> _reattachPane(TerminalPane pane) async {
    await _detachSession(pane, sendClose: false);
    await _attachSession(pane);
  }

  /// Resolve a dial agent to the machine that owns it.
  ///
  /// New CLIs state the machine explicitly. Older CLIs only sent an agent id;
  /// that is safe to retain only when the current snapshots contain exactly
  /// one matching machine. The websocket carrying the event is always the
  /// local daemon and is therefore not evidence that the agent is local.
  String? _dialFocusMachine(Map<String, dynamic> payload, String agentId) {
    final explicitMachineId = payload['machineId'];
    if (explicitMachineId is String && explicitMachineId.isNotEmpty) {
      final state = machineStates[explicitMachineId];
      if (state == null ||
          !state.agents.any((candidate) => candidate.id == agentId)) {
        return null;
      }
      return explicitMachineId;
    }

    String? match;
    for (final entry in machineStates.entries) {
      if (!entry.value.agents.any((candidate) => candidate.id == agentId)) {
        continue;
      }
      if (match != null) return null; // Ambiguous legacy event: do not guess.
      match = entry.key;
    }
    return match;
  }

  Future<void> _handleEvent(
    String machineId,
    Map<String, dynamic> event,
  ) async {
    final machine = machineStates[machineId];
    if (machine == null) return;
    final type = event['type'] as String? ?? '';
    final payload = (event['payload'] as Map<String, dynamic>?) ?? {};
    // EVERY tile on this machine sees the frame, and each decides for itself.
    //
    // Not a routing choice — a correctness one. `handleFrame` answers "this was
    // a terminal frame", NOT "this was mine": a session that is not the one
    // being addressed still returns true so the app-level switch skips it. With
    // one terminal those two meanings were the same sentence. With four they
    // are not, and stopping at the first `true` would have let whichever tile
    // happened to be first swallow another tile's `terminal_ready` — the reply
    // is matched by requestId AND agentId inside the session, so only the right
    // one acts on it, but only if it is allowed to see it.
    //
    // It also fixes a fault that was invisible at one tile: a
    // `terminal_transport_error` describes the whole connection, and every
    // session must learn the transport died. Stopping early would have told one
    // tile and left the rest showing a terminal that can no longer receive
    // anything.
    var consumedByTerminal = false;
    for (final pane in panesFor(machineId).toList()) {
      final session = pane.session;
      if (session == null) continue;
      if (await session.handleFrame(type, payload)) consumedByTerminal = true;
    }
    if (consumedByTerminal) return;
    switch (type) {
      // ── the dial, over the cable, forwarded by the local daemon ──────────────────────────────────
      // Local-only frames (backend.sendLocal in the harness CLI): they describe a hand at THIS desk, so
      // they never reach the cloud web audience, who may be sitting at another computer entirely.
      case 'dial_scroll':
        // Straight through, including the reports carrying no travel — the ends of a stroke are the point
        // of the message. The window does no arithmetic here; the terminal that owns the scrollback does.
        final phase = switch (payload['phase']) {
          'down' => 0,
          'up' => 2,
          _ => 1,
        };
        activeTerminal?.scroll(
          phase,
          (payload['dy'] as num?)?.round() ?? 0,
          (payload['velocity'] as num?)?.round() ?? 0,
        );
        break;
      case 'dial_focus':
        // Turning the dial to an agent brings that agent's terminal up here. selectAgent is the ordinary
        // selection path — the same one a click on the rail takes — so an agent with no terminal, an
        // offline machine and a missing id all fail exactly the way they already do.
        final agentId = payload['agentId'];
        if (agentId is String && agentId.isNotEmpty) {
          final targetMachineId = _dialFocusMachine(payload, agentId);
          if (targetMachineId != null) {
            unawaited(selectAgent(targetMachineId, agentId));
          }
        }
        break;
      case 'node_status':
        final online = payload['online'] == true;
        await _applyNodeStatus(machine, online);
        break;
      case 'machine_select_error':
        _lastError =
            'Machine selection failed: ${payload['error'] ?? 'unknown error'}';
        machine.connectionStatus = ConnectionStatus.disconnected;
        break;
      case 'agent_synced':
        final raw = payload['agent'];
        if (raw is Map) {
          try {
            final agent = Agent.fromJson(Map<String, dynamic>.from(raw));
            if (agent.terminalAvailable) {
              _upsertAgent(machine, agent);
            } else {
              await _removeAgent(machine, agent.id);
            }
          } catch (_) {
            unawaited(_loadMachineData(machine, force: true));
          }
        } else {
          unawaited(_loadMachineData(machine, force: true));
        }
        break;
      case 'agent_created':
        final raw = payload['agent'];
        if (raw is Map && raw['terminal'] is Map) {
          try {
            _upsertAgent(
              machine,
              Agent.fromJson(Map<String, dynamic>.from(raw)),
            );
          } catch (_) {
            unawaited(_loadMachineData(machine, force: true));
          }
        } else {
          unawaited(_loadMachineData(machine, force: true));
        }
        break;
      case 'agent_renamed':
        final agentId = _eventAgentId(machine, event, payload);
        final name = payload['name'];
        if (agentId != null && name is String) {
          _renameAgent(machine, agentId, name);
        } else {
          unawaited(_loadMachineData(machine, force: true));
        }
        break;
      case 'agent_deleted':
        final agentId = _eventAgentId(machine, event, payload);
        if (agentId != null) {
          await _removeAgent(machine, agentId);
        } else {
          unawaited(_loadMachineData(machine, force: true));
        }
        break;
      case 'turn_started':
      case 'turn_heartbeat':
        final agentId = _eventAgentId(machine, event, payload);
        if (agentId != null) {
          _markAgentProcessing(machine, agentId);
        } else {
          final sessionId = _eventSessionId(event, payload);
          if (sessionId != null) {
            machine.pendingProcessingSessions.add(sessionId);
          }
        }
        break;
      case 'turn_ended':
        final agentId = _eventAgentId(machine, event, payload);
        if (agentId != null) {
          _cancelTurnActivity(machine.machine.machineId, agentId);
        } else {
          final sessionId = _eventSessionId(event, payload);
          if (sessionId != null) {
            machine.pendingProcessingSessions.remove(sessionId);
          }
        }
        break;
    }
    notifyListeners();
  }

  /// Put an already-built session on the grid.
  ///
  /// The seam tests used to get from assigning `activeTerminal` directly, which
  /// a grid cannot offer: a session on screen is a session in a TILE, and the
  /// tile is what every lifecycle path — a machine going offline, an agent
  /// being deleted, a frame arriving — actually looks for.
  @visibleForTesting
  TerminalPane adoptSessionForTest(TerminalSession session) {
    final pane = TerminalPane(
      id: _nextPaneId++,
      machineId: session.machineId,
      agentId: session.agentId,
    )..session = session;
    panes.add(pane);
    focusedPaneId = pane.id;
    session.addListener(notifyListeners);
    return pane;
  }

  @visibleForTesting
  Future<void> handleEventForTest(
    String machineId,
    Map<String, dynamic> event,
  ) => _handleEvent(machineId, event);

  @override
  void dispose() {
    _disposed = true;
    _daemonSupervisionTimer?.cancel();
    _updateCheckTimer?.cancel();
    _stopAllOfflineRetries();
    _stopAllLinkRetries();
    _stopAllAgentSyncTimers();
    _clearAllTurnActivity();
    for (final pane in panes) {
      pane.session?.removeListener(notifyListeners);
      pane.session?.dispose();
    }
    panes.clear();
    super.dispose();
  }
}

final appStateProvider = Provider<AppNotifier>((ref) {
  final app = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: ConfigStore(),
    paneLayoutStore: PaneLayoutStore(),
  );
  app.bootstrap();
  return app;
});
