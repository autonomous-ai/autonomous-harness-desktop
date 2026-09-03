# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Harness Desktop — a Flutter macOS app (Linux/Windows runners exist but are unexercised) that lists Harness
machines and attaches xterm terminals to the agents running on them. Package name is `harness`
(`import 'package:harness/...'`). This repo was split out of a monorepo; a few comments still point at
files that live in the `autonomous-harness` (CLI) or `autonomous-code` (backend) checkouts.

## Toolchain and commands

`pubspec.yaml` pins `sdk: ^3.13.0`, i.e. **Flutter ≥ 3.47 / Dart ≥ 3.13**. An older Flutter fails at
`flutter pub get` ("version solving failed") and every command below fails with it — check
`flutter --version` first.

The macOS project is migrated to **Swift Package Manager** (`macos/Runner.xcodeproj` references
`FlutterGeneratedPluginSwiftPackage`). Run `flutter config --enable-swift-package-manager` once, then
`flutter pub get` — the generated `macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`
only lists the plugin dependencies when SPM is on at `pub get` time. With SPM off, `flutter run` falls
back to CocoaPods and rewrites tracked files (`project.pbxproj`, `contents.xcworkspacedata`, the
`Flutter-*.xcconfig`s) and adds `macos/Podfile`; revert those rather than committing them.

```bash
flutter pub get
flutter analyze                                   # lints: package:flutter_lints, no custom rules
flutter test                                      # whole unit/widget suite (test/)
flutter test test/terminal_session_test.dart      # one file
flutter test test/ws_conn_test.dart --plain-name "reconnects"   # one test by name substring
flutter run -d macos
flutter build macos --debug
flutter build macos --release
```

Integration tests (`integration_test/`) need a device: `flutter test integration_test/native_terminal_e2e_test.dart -d macos`.
`local_terminal_e2e_test.dart` and `prod_terminal_e2e_test.dart` still import `package:harness/e2ee/*`
and `widgets/remote_setup_screen.dart`, which no longer exist, and `native_terminal_e2e_test.dart`
builds `TerminalPanel` without its required `focused` argument — all three fail `flutter analyze` and
are the only analyzer errors in the repo (everything else is `info` inside `third_party/xterm`). Fix or
delete them before relying on them.

Local stack / E2E scripts (need sibling `autonomous-code` and `autonomous-harness` checkouts, override
with `AUTONOMOUS_CODE_ROOT` / `HARNESS_REPO_ROOT`; see README):

```bash
make terminal-local-manual   # boots backend+CLI locally and runs lib/main_local_manual.dart
make terminal-local-e2e
make terminal-prod-e2e       # opt-in, refuses without PROD_TERMINAL_E2E=1 + release evidence vars
```

Release (`make upload-desktop`, `make upload-node-runtime ARGS=22.16.0`) is documented in RELEASE.md.
The published version comes from the remote GCS `metadata.json`; `pubspec.yaml`'s `version:` is a
placeholder and is never bumped. Test the updater against a scratch manifest with
`--dart-define=DESKTOP_UPDATE_METADATA_URL=...`; `HARNESS_RUNTIME_METADATA_URL` does the same for the
managed Node runtime.

## Architecture

### The app talks only to the local `harness` CLI

This is the single most important thing to know. The desktop app **never** dials the cloud backend or
holds an SSO token:

- **Auth** lives in the CLI. `lib/auth/cli_login.dart` shells out to `harness auth status --json` and
  drives `harness login --json` (NDJSON event stream); `cli_link.dart` wraps `harness link create/import/list`.
- **REST** (`lib/api/api_client.dart`, Dio) goes to `AppConfig.localCliBaseUrl` (`http://127.0.0.1:18473`),
  and the CLI proxies to the backend with its own session. Responses are `{success, data|error}` and
  unwrapped into `ApiException`.
- **WebSocket** (`lib/ws/`) — `WsPool` owns one `WsConn` per machine. Every real connection uses
  `WsTransportKind.localPlaintext` against the CLI daemon's loopback WS (discovered/started by
  `LocalCliDiscovery`, which runs `harness start` when needed). The CLI terminates E2EE for relayed
  machines; the app carries no crypto. Close code `4404`/`NO_PEER_LINK` means the machine needs
  `harness link import` — surfaced as `MachineState.needsLink` and polled via `_linkRetryTimers`.
- The **only** direct-to-backend path is `LocalManualFixture` (`lib/main_local_manual.dart`), a
  compile-time-gated dev entrypoint fed by `scripts/start-terminal-local-manual.sh`. It fails closed
  unless every `--dart-define` is present.

`lib/core/harness_cli_runner.dart` is how the app finds the CLI without a shell: prefer
`~/.harness/runtime/current-node` + `~/.harness/cli/cli.js`, then `~/.local/bin/harness`, then PATH.
`lib/bootstrap/environment_provisioner.dart` installs the managed Node runtime, the CLI and tmux on first
run (the `preparingEnvironment` status).

### Boot and state

`lib/main.dart`: `CrashLog.install()` → `loadPersistedSettings()` (theme mode + terminal font, awaited
before the first frame to avoid flicker) → `RootShell`, which switches on `AppStatus`
(`bootstrapping → preparingEnvironment → unauthenticated → authenticated`); a forced update
(`hasForcedUpdate`, major/minor bump) overrides every other screen.

`lib/state/app_state.dart` (`AppNotifier`, a `ChangeNotifier` exposed through the single Riverpod
`appStateProvider`) is the whole app model: machines, agents, connections, panes, updater, login.
Widgets receive `notifier` explicitly and rebuild via `ListenableBuilder`; Riverpod is only the
injection point (`main_local_manual.dart` overrides it). `bootstrap()` → `_prepareEnvironment()` →
`cliLogin.checkStatus()` → `_finishBootstrapSignedIn()` (restore pane layout, create `WsPool`, ensure
the daemon, `api.me()`, `refreshMachines()`).

Per-machine runtime state is `MachineState` (connection status, transport mode, agents, `nodeOnline`
from `node_status` pushes — distinct from our own socket status, pending offline agent, turn activity).

### Terminals

- `TerminalPane` (`lib/state/terminal_pane.dart`) separates **intent** (machine + agent id, stable
  `id` used as the widget key) from the live `TerminalSession`, so a tile can exist before its machine
  answers and survive the machine going offline. `PaneLayoutStore` persists intent only, max 4 panes;
  `PaneGrid` renders fixed 1–4 tile shapes (deliberately not a splittable tree).
- `TerminalSession` (`lib/terminal/terminal_session.dart`, protocol v3) owns one `xterm` `Terminal`
  for one agent: `terminal_open`/`terminal_ready` handshake matched by requestId+agentId, seq-tracked
  output with bounded resync and one auto-reopen, batched input/resize, heartbeat, and
  `onOpenStalled` to force a transport redial. `engineId == 'grok'` scrolls via tmux copy-mode instead
  of mouse reports (see `scrollViaTmuxCopyMode`).
- Bulk terminal bytes are binary WS frames framed by `lib/terminal/terminal_binary.dart`
  (`HTRL` magic, kinds input/output/keyframe/sync, zlib flag). `AppNotifier._handleTerminalBinary`
  decodes once and offers the frame to **every** session on that machine; each session drops frames
  whose `streamId` is not its own. The same fan-out applies to JSON events in `_handleEvent`: all pane
  sessions get `handleFrame` first (a session returns true for any terminal frame, even one not
  addressed to it), then the app-level switch handles `node_status`, `agent_*`, `turn_*`, and the
  hardware-dial events `dial_scroll`/`dial_focus`.
- `third_party/xterm` is a **vendored, patched** xterm 4.0.0 (atomic `replaceRange` fix for scroll
  regions — see its `README.autonomous.md`). Do not replace it with the pub package; the regression
  lives in `test/terminal_session_test.dart`.

### Theming — two files, one source of truth

- `lib/shared/theme/app_theme.dart` (imported as `grid`) is the design-system token layer:
  `AppPalette`/`AppSurface`/... members are **getters** that resolve against the global
  `grid.AppTheme.brightness`, which `_GridTokenScope` in `main.dart` sets from `Theme.of(context)`.
  Chrome widgets call `grid.AppTheme.watch(context)` at the top of `build` so `const` subtrees still
  repaint on a theme flip.
- `lib/theme/app_theme.dart` (`AppColors`, `AppTheme.terminalLight/terminalDark`) is a set of
  adapters over those tokens. Nothing here is `const` on purpose — freezing a colour is how light mode
  silently breaks. Do not add a parallel palette.
- `ThemeModeStore` and `TerminalFontStore` are `ValueNotifier` singletons (they must resolve above the
  provider scope and before sign-in).

### Persistence and native integration

- All local state is in `HarnessFileStore` (`~/.harness/desktop-app/state.json`, mode 0600, keyed
  strings behind `LocalKeyValueStore`): connection config, skipped update version, theme, font, pane
  layout. `~/.harness/computer-id` is the machine identity shared with the CLI.
- The window is frameless on macOS via `window_manager` (`lib/core/desktop_window.dart`, same size and
  `TitleBarStyle.hidden` as Grid). The traffic lights float over the rail's head, which leaves
  `railTopInset` above the wordmark and is a `DragToMoveArea`; so are the pane headers. A screen that
  fills the window goes through `FullWindowScreen` (`lib/widgets/window_chrome.dart`) for its drag
  strip, and a full-width band at the top edge pads by `trafficLightClearance`.
- `macos/Runner/MainFlutterWindow.swift` installs native menu items and calls into Dart over the
  `harness/app_menu` MethodChannel (`checkForUpdates`, `flashFirmware`, `showShortcuts`, terminal font
  size). Keep the menu in Swift; only the handler lives in `RootShell`.
- **Grid is the one exception to "the app talks only to the local CLI"**: `lib/grid/` calls
  `https://api-grid.autonomous.ai/v1/grid/me` directly with its own bearer token, because the Harness
  CLI owns a Harness session and knows nothing about Grid accounts. `kGridSessionToken` in
  `grid_api_client.dart` is a **hardcoded developer token** — TODO(BE), it must not ship; override it
  with `--dart-define=GRID_API_TOKEN=…`. Response fields were read off the live API, not the OpenAPI
  spec, whose `/v1/grid/me` response schema is empty.
- **Picking a grid retargets NEW agents only.** `gridSelectionStore` (`lib/grid/`, persisted like
  `themeModeStore`, loaded in `loadPersistedSettings`) holds the chosen grid + model; the sidebar's
  `GridSelector` and Settings ▸ Grid both write it. At create time the New agent dialog calls
  `resolveGridAgentOverride()`, which mints a fresh relay key, and `createAgent` adds it as
  `payload.grid` — **only when a grid is picked**, so an unselected build sends the frame it always
  did. The harness CLI (`autonomous-harness`, `cli/src/lib/gridLaunch.ts`) reads that field and
  gives the new tmux session `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_MODEL` via
  `new-session -e`, so the key never lands in the engine's argv. **Claude Code is the only
  grid-capable engine**; the CLI refuses the rest with `GRID_ENGINE_UNSUPPORTED` rather than running
  them on their own login, and `kGridCapableEngines` in `widgets/new_agent_dialog.dart` mirrors that
  list to warn before the click. Keep the two in sync.
- Settings is a **screen**, not a dialog (`lib/settings/`): `showSettingsScreen` pushes a faded route
  whose rail lists `kSettingsGroups` from `settings_section.dart` and whose pane is one widget per
  `SettingsSection` (`sections/`). Adding a setting means adding an enum value, a group entry and a
  section widget — nothing else. Panes are framed by `shared/widgets/section_scaffold.dart` (copied
  from Grid).
- `lib/shortcuts/app_shortcuts.dart` is the one list that feeds both the live bindings and the ⌘/
  sheet; `shortcuts/shortcuts_list.dart` is the rendered body both the sheet and Settings ▸ Keyboard
  shortcuts draw, so the two cannot disagree. Every shortcut is ⌘-based: Ctrl belongs to the
  shell/tmux, ⌥ is a Meta prefix for the pty, and ⌘C/⌘V/⌘A are owned by xterm.
- `lib/flash/` flashes the ESP32-S3 dial through the CLI runner; `SerialPortLease` pauses daemon
  supervision while the port is held so `harness start` cannot steal it mid-write.
- `lib/update/desktop_updater.dart` self-updates from the GCS manifest (sha256-verified, strictly
  newer only, major/minor = forced). `_otaKey` must match `OTA_KEY` in `scripts/upload-desktop.sh`.

## Testing conventions

Unit tests build `AppNotifier(config: AppConfig.dev, authSession: AuthSession(), configStore: null)`
and set `status` directly, or pass subclass fakes (`CliLogin`, `EnvironmentProvisioner`, `ConfigStore`)
so nothing shells out to a real `harness` binary. Stores (`PaneLayoutStore`, `ThemeModeStore`,
`TerminalFontStore`) take an in-memory `LocalKeyValueStore` implementation instead of touching
`~/.harness`. `TerminalSession` is exercised with recording `send`/`sendBinary` closures and
`handleFrame`/`handleBinary`. Use the `@visibleForTesting` seams on `AppNotifier`
(`handleEventForTest`, `adoptSessionForTest`) rather than reaching into private state.
