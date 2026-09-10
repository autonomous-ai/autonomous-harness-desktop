# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Harness Desktop — a Flutter app that lists Harness machines and attaches xterm terminals to the
agents running on them. **macOS and Linux (Ubuntu) are both real, released targets** — first-run
provisioning (`lib/bootstrap/environment_provisioner.dart`), self-update
(`lib/update/desktop_updater.dart`), and packaging (`scripts/upload-desktop.sh` /
`scripts/upload-desktop-linux.sh`, see RELEASE.md) all branch per-OS internally rather than being
separate code paths. The Windows runner exists but is unexercised. Package name is `harness`
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
flutter run -d macos                              # or: flutter run -d linux
flutter build macos --debug
flutter build macos --release
flutter build linux --release                     # Ubuntu build host only — no cross-compiling
```

Integration tests (`integration_test/`) need a device: `flutter test integration_test/native_terminal_e2e_test.dart -d macos`
(swap `-d linux` on an Ubuntu host).
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

Release (`make upload-desktop` for macOS, `make upload-desktop-linux` for Linux — the latter must run
on an Ubuntu host) is documented in RELEASE.md. Both platforms publish to the same GCS
`metadata.json` under different keys (`desktop-macos` / `desktop-linux-x64`) and share one version
number by default; `pubspec.yaml`'s `version:` is a placeholder and is never bumped — Linux instead
gets a `version.txt` written into the built bundle at package time (see `lib/core/app_version.dart`,
since `flutter build linux` has no Info.plist-style stamping). Test the updater against a scratch
manifest with `--dart-define=DESKTOP_UPDATE_METADATA_URL=...`; `HARNESS_RUNTIME_METADATA_URL` does
the same for the desktop updater only. The managed Node runtime is still published from this repo with
`make upload-node-runtime ARGS=22.23.2` (`darwin-arm64`, `darwin-x64`, `linux-x64`, `linux-arm64`), but
its consumer is now the `harness` installer rather than this app.

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
`lib/bootstrap/environment_provisioner.dart` installs the CLI, tmux and the **Grid** CLI on first run
(the `preparingEnvironment` status) — three steps, not four.

Node is deliberately not the user's: it is a private, sha256-verified runtime under
`~/.harness/runtime`, never Homebrew, nvm or PATH. **The app does not install it — `install.sh` does**,
on its own or on the app's behalf, and records it in `current-node`; the launcher it writes names that
binary absolutely, so a Finder launch (PATH is launchd's bare `/usr/bin:/bin:/usr/sbin:/sbin`) and a
Terminal launch behave identically. One implementation, shared with everyone who installs the CLI from
a terminal, instead of a second copy here that had to keep its own pinned checksums in step.
**tmux** is the one dependency still taken from the OS package manager, and the only reason the setup
screen ever opens a terminal: a fresh Homebrew or any `apt-get install` needs a password prompt on a
real tty.

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
  `https://api-grid.autonomous.ai/v1/grid/me` directly with a bearer token, because the Harness CLI
  owns a Harness session and knows nothing about Grid accounts. That token is **the machine's own
  Grid session**, read by `GridSessionStore` (`grid/grid_session.dart`) out of the *Grid* CLI's
  `~/.grid/credentials.toml` — the file `grid login` writes. This app never writes it: one Grid
  sign-in per machine, and a second copy here is a second thing to expire and to disagree about.
  Loaded before the first frame by `loadPersistedSettings`, and read **per request** rather than
  captured in `GridApiClient`'s constructor, so a sign-in or a `grid logout` mid-session lands
  without rebuilding a controller. Only three top-level keys are parsed (`session_token`, `api_url`,
  `email`), scanning stops at the first `[` table because `name`/`email` mean something else under
  `[[networks]]`, and `api_url` is honoured so a `grid` pointed at staging does not send its token
  to production. Signing in is `GridSessionStore.signIn()` → `harness grid login --json`, which
  hands the Harness session this app already has to `grid login --harness` over that child's
  **stdin** — no browser, and the account token never reaches an argv. Its refusals already name
  their own way forward, so they are shown verbatim rather than re-worded. **The app signs in for
  you on bootstrap (`AppNotifier._ensureGridSession`), but ONLY when the machine has no Grid session
  at all, or when the one it has belongs to a DIFFERENT account** — every run mints a fresh 365-day
  session and revokes nothing, so signing in on each launch would pile sessions onto the account,
  with `grid logout --everywhere` (all-or-nothing, every machine) as the only cleanup. A session
  matching the Harness account is therefore left exactly alone; the address is compared inside
  `GridSessionStore.signIn(account:)`, so the guard stays in one place rather than once per caller,
  and an address it cannot know reads as "leave it alone" (a slow `api.me()` must not look like a
  mismatch). Settings ▸ Grid still says the mismatch out loud (`_AccountMismatch`) for the window
  between the two. **`logout()` now signs Grid out too** (`GridSessionStore.signOut` →
  `harness grid logout --json`, this machine only): the CLI itself still has no cascade in either
  direction, so without this a sign-out left a live 365-day token on the machine and the next person
  to sign in inherited the previous one's grids. It never blocks the Harness sign-out — trapping
  somebody in the account they asked to leave over a Grid failure would be worse — but it is logged
  rather than swallowed, because a failure means the credential is still there. ⚠️ `grid logout`
  **stops whatever engine this machine is serving** before deleting anything, and that engine is
  detached and normally outlives the app, so a sign-out now ends a share the user left running.
  No session is a state,
  not an error: `GridSignedOutException` → `GridNetworksSignedOut` → the sign-in card in Settings ▸
  Grid, kept apart from `GridNetworksFailed` because that one offers a Retry and retrying a sign-out
  fails identically forever. `--dart-define=GRID_API_TOKEN=…` still pins a token for a build that
  wants an account it has not signed into here. **The hardcoded developer token is gone** — it was a
  real credential in the repo, and every build made from that branch read one person's grids.
  Response fields were read off the live API, not the OpenAPI spec, whose `/v1/grid/me` response
  schema is empty.
- **The surface is called PROVIDERS, and a "grid" is what the code still calls one.** Settings ▸
  Providers, `New provider`, `Filter providers` — the rename is copy and rail labels only; every
  type, store, controller and API path is still `Grid*`/`grid_*`, because the control plane's
  vocabulary is `grid` and a half-renamed data layer is worse than an honestly split one. **"Grid"
  survives in the copy wherever it names the PRODUCT** — the sign-in card, `harness grid login`,
  "Join one from the Grid app" — since that is a real, separate account a person signs into.
- **Picking a provider retargets NEW agents only, and ENABLED is a second, separate question.**
  `gridSelectionStore` (`lib/grid/`, persisted like `themeModeStore`, loaded in
  `loadPersistedSettings`) holds the DEFAULT — the one provider new agents launch against — and
  `providerEnablementStore` (`grid/provider_enablement_store.dart`) holds which providers this
  computer will offer at all, of which many can be on. They were one radio before, which made "stop
  offering me this provider" impossible to say without also moving every new agent. **Turning the
  default OFF hands the default to the next enabled provider** rather than refusing the click, and
  clears it when there is none left — `ProviderAllOffBanner` is what then says so, because the
  consequence lands on agents launched later and nothing on screen would otherwise look wrong.
  **Enablement is a CLIENT-side filter and calls no API**: the grid keeps running, this account stays
  a member, and only the pickers skip it. Its file is its OWN — `~/.harness/desktop-app/
  providers_config.json`, not `state.json` — because it is a *set* whose membership is the point, and
  it stores only the **disabled** ids, so a provider it has never heard of is enabled and a fresh
  install needs no file. Both stores are read by the sidebar's provider pill
  (`widgets/grid_target_pill.dart` — `gridTargetMenuOptions` takes `isEnabled` and DROPS a
  switched-off provider rather than dimming it) and by Settings ▸ Providers. Both list
  `gridNetworksController`, the shared singleton, so neither holds a half-stale copy. The label for
  "no provider" is `kNoGridTargetLabel` beside the selection store — **the pill still prints it, and
  Settings no longer does**: a picker may offer "use nothing", but a roster of providers must not
  carry a row that is not one. **Grid is hidden in a shipped build** (`kGridSurfaceEnabled`,
  `grid/grid_surface.dart` — `kDebugMode` or `--dart-define=HARNESS_GRID_SURFACE=true`): it is a
  feature still being built, so its own flag rather than `kDebugSurfaceEnabled`, which is developer
  furniture and must be switchable apart from it. Four places read it — the two Settings rows
  (`_kGridSections`), the rail's pill, the status rail's readout (the strip stays, for the version
  mark), and **`GridSelectionStore.load`, which is the one that matters**: `state.json` is shared
  with the debug build where a grid IS picked, so without it a release build would inherit that
  choice off disk and launch agents on a grid it shows no picker, no pane and no way out of. The
  stored key is left alone, not cleared — it is the other build's setting. `settingsGroupsFor` takes
  both gates as arguments so the shipped shape can be asserted from a test run, which by definition
  has everything switched on, and `kDefaultSettingsSection` is derived from the visible list rather
  than named (it used to name Grid, the first row a shipped build drops).
  The model is chosen per agent, not globally, and **only once the agent exists**: the agent view's
  header pill (`widgets/agent_model_menu.dart`) picks it for a running agent, and the New agent
  dialog offers no model at all — every new agent launches on Auto (no `model` on the wire, the grid
  chooses), because a model picked before there is an agent to apply it to is a second door onto a
  setting the header already owns. **The pill prints one word — `Model` — not the model id**
  (`kModelPillLabel`): a pane header already carries the agent's name, a status dot, a transport
  badge and the pane's own buttons, so four panes side by side leave it ~150px and a real id
  ellipsized to `DeepSeek-V4-F…`, which answers nothing and costs the width anyway. The answer is
  on hover, where the tooltip leads with the model and follows with the caveat, and in the picker,
  where the row the agent is on is ticked. **⇧⌘M opens the same picker for the focused pane** — never plain ⌘M, which is
  Minimize and is matched by AppKit before the keystroke reaches Flutter (the trap that once ate
  ⌘V in a terminal pane). Both doors run one function, `pickAgentModel`, and share one in-flight
  set, `retargetingAgents` (keyed `machineId/agentId`): it is what stops a second restart landing
  on the first, and what draws the pill's skeleton for a restart the keyboard started. It draws
  **nothing at all** only where there are no providers in the build (`kGridSurfaceEnabled`, taken as a `@visibleForTesting` argument so the
  shipped shape can be asserted). It used to leave whenever the SIDEBAR had picked no default,
  which was right while the menu could only offer that one grid's models — with the picker listing
  every provider, that hid the door for exactly the people who had not found the sidebar's picker.
  **The choices themselves are a DIALOG, grouped by provider**
  (`widgets/model_picker_dialog.dart`, rows from the pure `grid/model_picker_options.dart`), the
  shape OpenCode's model picker uses: a search that crosses providers, the last five picks under
  `Recent` (`grid/model_recents_store.dart`, loaded by `loadPersistedSettings` because it is drawn
  on the frame the panel opens), then one group per provider with the models it serves, and ↑/↓/↵.
  It replaced a dropdown that could only list the models of the ONE provider the sidebar had
  picked, which made "run this agent on that other provider" a trip to the sidebar that also
  changed where every future agent launched. A pick therefore carries **both halves** — a
  `ModelChoice` is a provider *and* a model, because a model id names nothing without the relay
  that answers for it — so one restart can do what two used to, and the sidebar's default is not
  touched by moving one agent. `gridModelsController` is keyed **per network** for the same reason:
  a single slot had each provider's answer evicting the last one's. The highlight is held as a
  choice, never as a row number, since a provider answering late inserts rows above it — and it is
  re-placed on the agent's own row until the reader takes the keyboard, because that row does not
  exist on the frame the panel opens on. `Auto` and
  the no-provider row (`kNoGridTargetLabel`) are different rows on purpose (the relay's own virtual
  `auto` id is dropped from every list — see `kAutoModelId`), and a provider switched off in
  Settings ▸ Providers is not offered here either. ⚠️ **A provider with nothing to pick is dropped
  from the list entirely** — still loading, failed, or serving no models: header, note and all. An
  account on four grids opened a panel that was four names over four apologies, none of them a
  choice. What is still happening is said ONCE, under the list, by `modelPickerModelsNote`
  (`Loading models…`, or the failure when a load ended in one) — dropping the rows is right,
  dropping the fact that grids are still being asked is not, since the reader would otherwise watch
  the list grow with no idea why. A grid serving NOTHING is silent there: it is neither pending nor
  broken, and there is nothing to wait for or fix. At create time the New agent
  dialog calls `resolveGridAgentOverride()`, which mints a fresh relay key, and `createAgent` adds it
  as `payload.grid` — **only when a grid is picked**, so an unselected build sends the frame it
  always did. The harness CLI (`autonomous-harness`, `cli/src/lib/gridLaunch.ts`) reads that field
  and gives the new tmux session `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_MODEL` via
  `new-session -e`, so the key never lands in the engine's argv. **Seven engines are grid-capable —
  claude, codex, copilot, grok, hermes, opencode, pi**; the CLI refuses the rest with
  `GRID_ENGINE_UNSUPPORTED` rather than running them on their own login, and `kGridCapableEngines` in
  `grid/grid_agent_override.dart` mirrors that list to warn before the click. Keep the two in sync. Moving a RUNNING agent is `agent_retarget`,
  and a CLI that predates it answers `UNSUPPORTED` from `backendSocket`'s default case — which is
  what every **published** release still does, so `make install-cli` in `autonomous-harness` is part
  of testing this feature. Every CLI refusal reaches Dart as a thrown `WsRequestFailure` (never as an
  `error` key on a returned map); `AppNotifier.retargetMessage` turns its `code` into the sentence
  the user sees.
- **A grid launch also hands the agent the grid's WEB TOOLS.** The same `payload.grid` carries
  `mcpUrl` — `grid_web_mcp.dart`, the control plane's `/v1/grid/web-mcp/` — and the CLI's
  `lib/gridWebMcp.ts` wires it into claude, codex, copilot, opencode and hermes as an MCP server
  named `grid-web`.
  **The control plane, not the relay** (grid ADR 0041 D-a: a relay is per-grid, can be asleep, and
  may be a LAN address), built from the *session's* `apiBaseUrl` so a `grid` signed into staging does
  not send agents at production. The address is sent rather than derived because the machine running
  the agent may have no Grid session at all. **No second credential**: ADR 0041 D-b takes the
  per-grid access token and requires no scope of it, `consumer` included, which is exactly what
  `/networks/{id}/credentials` mints. The engines wired are the ones whose header handling was
  measured on the wire rather than read off a vendor page — the three `grid mcp config` prints for,
  plus hermes and copilot since. ⚠️ The key still travels only in the
  pane's environment: Claude Code expands `${GRID_API_KEY}` inside `--mcp-config` (the JSON-string
  form, so no file) and **copilot expands the same `${…}` in the same document** under
  `--additional-mcp-config`, which augments `~/.copilot/mcp-config.json` rather than replacing it —
  so both share one builder, `mcpServersConfig`. Codex reads `env_http_headers` off `-c`, opencode
  expands `{env:…}` in the
  config the launch already writes, and hermes interpolates `${…}` Cursor-style in a **managed-scope
  overlay** (`HERMES_MANAGED_DIR`, deep-merged over the user's `config.yaml` — not `HERMES_HOME`,
  which would move auth, sessions and memory too). That is the OPPOSITE of ADR 0041 D-d, which is
  right about a person pasting into their own dotfile and wrong here, where the daemon owns both
  ends. ⚠️ Hermes' overlay REPLACES `/etc/hermes` rather than adding to it, so `cli.ts` drops it on a
  machine that has one and the agent starts without web tools instead of losing an administrator's
  policy. ⚠️ **The reference syntax is not interchangeable and each one was measured**: copilot sends
  opencode's `{env:…}` and a `${env:…}` through VERBATIM, so the wrong spelling puts the literal
  string on the wire and the tools fail authentication with nothing naming why. An absent `mcpUrl`
  wires nothing, so an older desktop launches exactly as it did.
- **Share Intelligence is the one place this app drives a SECOND CLI.** `lib/share/` runs the *Grid*
  CLI (`~/.local/bin/grid`, `GridCli` in `share/grid_cli.dart`, always `grid --remote …`), because
  `harness` cannot serve inference: the models live in `~/.grid/models`, the engine is
  `~/.grid/bin/llama-server`, and `grid join <grid-id> …` is what puts this Mac on a grid. This app
  installs `grid` at boot too (`EnvironmentStep.grid`), but as the one **optional** step: it is
  install-if-missing and never upgrade-if-old — a `grid` built from source must survive a launch,
  the way the harness CLI's self-update does not — and a failure marks the step `unavailable`
  rather than `failed`, so `isReady` (required steps only) still lets the app boot. "Not installed"
  therefore stays a state the pane explains, not a failure it repairs.
  Three routes (`ShareRoute`): a local GGUF, a vendor key, or an OpenAI-compatible server already
  running here. **A key never reaches argv** (`ps` is world-readable) — it goes in the child's
  environment, which is why `GridCli.start` takes `secrets` separately. The engine `grid join`
  starts is **detached and outlives the app**, so "am I sharing?" is answered by re-reading the
  CLI's run record (`~/.grid/run/engines/<grid-id>/*.json`, `share/engine_run.dart`), never by
  anything this app remembers — and closing Harness does not stop it, which the rail's footnote
  says out loud. Reached as Settings ▸ Grid ▸ Share Intelligence; `lib/shared/theme/share_page_theme.dart`
  is the page's own palette, copied value-for-value from Grid — keep the two in step.
- **Which grid this computer SERVES is not `GridSelectionStore`.** It is
  `share/share_target_store.dart`, and the split is the point: Providers' `DEFAULT` answers "where do
  the agents I start get credentials" (what this machine *consumes*), the share target answers "who
  do my GPU and my keys answer for" (what it *gives*). One value for both meant pointing the share
  at a lab grid silently moved every new agent with it. `resolveShareTarget(pin, providersDefault)`
  is the only place the precedence is written: **an absent pin means "follow Providers", not "no
  grid"**, so a machine that never opens the picker behaves exactly as it did before the picker
  existed, and a pin deliberately does NOT track the default afterwards. The page says which of the
  two produced the grid it is showing in every state (`ShareTargetPicker`) — a reader looking at
  `Water Grid` has to be able to tell, without leaving the page, whether their agents moved too.
  The picker **locks while an engine is up**: a join is per-grid and detached, so switching under a
  live run would leave it serving a grid the page no longer names, with no Stop button anywhere for
  it (Stop only ever leaves the grid currently on screen). ⚠️ `ShareController.refresh` takes a
  **nullable** grid id on purpose — what this machine can offer is a fact about the machine, so the
  probe runs before any grid is chosen and the rail (which holds the picker) can draw itself.
  **Manage models is the one part of this feature that is NOT the Grid CLI**: the shelf is
  `POST /v1/grid/catalog` on the control plane (`GridApiClient.catalog`/`catalogDetail`, the same
  bearer as the Grid tab), because `grid catalog` answers with two or three picks ranked for THIS
  machine and that is far too short to browse. Both are shown, labelled apart. A version's
  `pull_spec` names only the FIRST file, so a split GGUF is downloaded through every URL in `urls`
  (`share/pull_spec.dart`) — pulling the named one alone leaves a model that will not load.
- **The status rail is where the app polls** (`lib/widgets/status_rail/`,
  `grid/grid_overview_controller.dart`): a 26px full-bleed strip along the window's bottom edge
  showing what the chosen grid is made of. Two pollers now hang off it, never both at once — the grid
  overview below, and the agent-account usage further down. Its data is `GET {relay}/grid/overview` — the RELAY, not
  the control plane, because the relay is what dispatches the work — reached with a fresh key from
  `credentials(networkId)` every 60s. **A figure the relay did not send is null, never zero**: a zero
  is a measurement and a blank is an admission, and on this strip the difference is the whole point.
  The last good answer stays on screen when a refresh fails (`stale` turns the dot amber). The work
  figure is `answered.freshInput` (tokens_in − tokens_cached), not the total, which cache hits
  dominate. Member count is owner-only on the server and reads null on a 403 — the figure is then
  omitted, because "we may not ask" and "nobody is here" must not render the same.
  **The five panels are Grid's own files, ported rather than rewritten** —
  `grid_power_panel.dart`, `grid_stat_panels.dart`, `grid_models_panel.dart`,
  `memory_split_bar.dart`, `pill_panel_shell.dart`, and the pure half of
  `node_display.dart`/`node_metrics.dart`/`node_groups.dart`/`model_usage.dart` under
  `lib/grid/`. The only change is Riverpod out, constructor parameters in; keep them in step
  with Grid. `test/fixtures/` is one real relay answer, anonymised, and it is what drives
  `grid_panels_test.dart` — a hand-written fixture has none of the shapes these panels
  exist to fit.
- **Agent-account usage is the rail's OTHER readout, and it stands exactly where the grid's
  cannot** (`lib/usage/`, `widgets/status_rail/usage_readout.dart` + `usage_panel.dart`). With a grid
  chosen the strip reads the grid; with none — or in a build where `kGridSurfaceEnabled` is off — it
  reads what the Claude and Codex accounts on this machine have spent. The two never share the strip,
  which is why they share one hover/pin surface (`rail_figure.dart`, extracted from the grid rail
  rather than copied) and one `_PanelKind`. It replaced the words "No grid chosen", a sentence that
  tells someone what they already know and hands a riddle to anyone whose build has no picker.
  **This is the SECOND exception to "the app talks only to the local CLI"**, after Grid, and it is a
  narrower one: nothing here is dialled on the app's own behalf. `UsageCredentials` reads the tokens
  the agent CLIs already wrote — the macOS Keychain item `Claude Code-credentials` (falling back to
  `~/.claude/.credentials.json`, which is all Linux has) and `~/.codex/auth.json` — and spends them
  against the vendors' own usage endpoints. It never writes or refreshes them: one sign-in per
  machine, owned by the CLI that made it, the same rule Grid follows with `credentials.toml`.
  A rate limit is scoped to an **account**, not a machine, so reading it here is right even though
  the agents run elsewhere — provided the remote machines sign in as the same account. They are also
  the reason this poller is not gated on a grid: an account's limit is true with no grid at all.
  ⚠️ **Both endpoints are undocumented** — `api.anthropic.com/api/oauth/usage` (needs
  `anthropic-beta: oauth-2025-04-20` and the CLI's own user agent, because the OAuth token was minted
  for the CLI) and `chatgpt.com/backend-api/wham/usage`. Either can change without notice; both
  failures land as a `ProviderUsage` state rather than an exception. **`signedOut` is kept apart from
  `failed`** for the reason Grid keeps `GridNetworksSignedOut` apart from `GridNetworksFailed`:
  retrying a sign-out fails identically forever. Claude's Fable window has been spelled three ways
  across releases and all three are tried; Codex names its windows from `limit_window_seconds` rather
  than assuming, because a confident "5h" beside a real percentage reads as measured.
  `loading` is false **before** `start()` as well as after the first answer — a controller nobody
  started is not waiting for anything, and a skeleton for it would promise an answer never coming.
  That is also what keeps `flutter test` honest: `kUnderTest` (`core/test_run.dart`, shared with
  `AnalyticsConfig`) stops the poll auto-starting, since a `Timer.periodic` is a `pumpAndSettle` that
  never settles and these sources would otherwise shell out to `security` and open real sockets.
- **A nearly-spent subscription is the ONE thing this app says unprompted**
  (`lib/usage/usage_pressure.dart`, `usage_offer.dart`, `usage_nudge_store.dart`;
  `widgets/usage_limit_notice.dart` + `usage_limit_card.dart` + `usage_offer_actions.dart`).
  Two thresholds, one meaning each: **80% changes a colour, 90% speaks**. The rail figure and
  `UsageBar` share both through `usagePressureOf`, so a window cannot be amber in the strip and
  plain in the panel that expands it — `19% used` and `92% used` used to print in identical ink,
  which made the readout useless for the one question it answers at a glance.
  ⚠️ **It is deliberately NOT a modal.** These panes are terminals: a dialog takes focus off
  whichever one has it, so keystrokes meant for a running agent land nowhere — and 90% of a window
  arrives precisely when somebody is deep in a turn. It is also not full-bleed like `_ErrorStrip`:
  a row in the shell's `Column` would SIGWINCH every pty on screen to deliver a message, so it
  floats at bottom-left, over the figure it is about, taking no layout.
  **It never draws without something to press.** `usageOfferFor` answers null in four cases —
  a build with no providers (`kGridSurfaceEnabled`), an engine this computer does not run at all,
  a provider chosen with every candidate mid-turn (the CLI would answer `AGENT_BUSY`), and below
  the threshold. ⚠️ **The two offers ask DIFFERENT questions of `UsageAgentTally`**, and reading
  both off `candidates` was a real hole: a computer whose only Codex agent had been moved onto a
  provider by hand watched that account hit 97% and was offered nothing, while `New agent` would
  have launched the next one straight back onto the spent subscription because no DEFAULT was
  picked. Moving asks `candidates` ("what is on that subscription now"); choosing a default asks
  `present` ("does this computer run that engine at all"), and an agent parked on a provider
  answers yes. In every one of those cases the amber figure has already said the only thing left
  to say, and a warning the reader can only agree with is not worth interrupting for.
  ⚠️ **The silence names itself**: `resolveUsageOffer` returns a `UsageOfferBlocked` beside the
  offer and the notice logs it (`app` category, so Settings ▸ Debug shows it live). Four unrelated
  facts about a machine produce the identical blank and each is fixed somewhere else entirely, so
  a red figure with nothing beside it reads as a broken feature — this is what tells whoever is
  looking which of the four it is. It is also what caught the `candidates`/`present` hole above.
  With a default provider the button MOVES
  the idle agents (`applyAgentModel` per agent, Auto model, sequential — a retarget respawns the
  pane in place with `--resume`, so this is not destructive); with none it opens Settings ▸
  Providers. ⚠️ **Only the MOVE closes the card.** Choosing a provider does not answer the
  question, it changes which offer applies — the card should come back reading `Move 3 agents to
  Water Grid`, which is the step that gets the work going again; silencing it there would strand
  somebody one click short. ⚠️ **Any dismissal buys `kUsageNudgeCoolOff` of quiet from the notice as a whole**, not just
  from the window it closed: two accounts can be over the threshold at once, and closing the first
  used to put the second on screen in the same place under the pointer that had just clicked — so
  the second click landed on a card nobody had read. No timer behind it; the poll rebuilds this
  once a minute anyway.
  **Once per rate-limit window**: `UsageNudgeStore` keys a dismissal by
  `provider|label` — deliberately WITHOUT the reset time, which both vendors recompute on every
  answer, so a key carrying it would change under a once-a-minute poll — and expires it at the
  window's own reset, or `kUsageDismissGrace` when the vendor sent none. **Every entry expires**,
  which is why there is no permanent opt-out and why the file cannot grow. The `UsageController`
  moved to `_HomeScreenState`: the notice and the rail read the SAME poller, or the card could
  name a percentage the figure under it disagreed with. Three events —
  `usage_limit_warned`/`_offer`/`_dismissed` — because a warning nobody sees and a warning nobody
  acts on produce the same number of moves.
- **The token ledger is the OTHER usage feature, and the two must not be merged** (`lib/usage/ledger/`,
  Settings ▸ Usage in `settings/sections/usage_section.dart` + `usage_panels.dart`). The rail's readout
  above asks the vendors *how much of your rate limit is left* — a percentage, scoped to an **account**,
  true whichever machine burned it. This counts **tokens**, scoped to **this machine**, with a history:
  it reads the logs the agent CLIs already wrote to this disk and calls nobody. Ported from Orca
  (`src/main/{claude,codex,opencode}-usage/`); keep the pricing tables in step with its
  `claude-model-pricing.ts` / `codex-model-pricing.ts`.
  **Three providers, three unrelated formats.** Claude: JSONL under `~/.claude/projects` *and*
  `~/.claude/transcripts` (the older layout — reading only the first drops every pre-move session),
  usage off `message.usage` on `type == "assistant"` rows. Codex: JSONL under
  `$CODEX_HOME`/`~/.codex/{sessions,archived_sessions}`, usage off `event_msg`/`token_count`. OpenCode:
  a **SQLite** database at `$XDG_DATA_HOME/opencode/opencode*.db`, one aggregate row per session.
  ⚠️ **Codex reports CUMULATIVE totals where Claude reports per-turn figures** — summing
  `total_token_usage` would bill a 40-turn session forty times over, so `resolveCodexDelta` takes the
  increment and guards the compaction/resume regressions. ⚠️ **`UsageTotals.freshInput` is
  cache-EXCLUSIVE for all three**, which costs Codex a subtraction because its `input_tokens` includes
  `cached_input_tokens`; Orca deliberately does *not* normalise, which is right for a scanner that
  round-trips a file format and wrong here, where one panel adds all three together. Codex's
  `cache_write_input_tokens` is dropped on purpose — OpenAI writes its cache free, so a bucket for it
  would show tokens nobody is billed for.
  **`costUsd` is nullable and null is never zero.** Only OpenCode fills it, from its own `cost` column;
  Claude and Codex are priced from `model_pricing.dart`, and a model that matches no row leaves
  `hasUnpricedModel` set so the panel calls the figure a floor. A Grid session records a real `0.0`
  (Grid inference is free, grid ADR 0039 D-g) and that measurement must not render like an unpriced
  model. Same rule as the rail: `LedgerStatus.unavailable` is kept apart from `failed`, because a
  machine with no OpenCode is never fixed by retrying.
  **Off is the resting state**, per provider, persisted through `LocalKeyValueStore`: these transcripts
  hold every prompt, path and branch a session touched and this feature wants only the counts, so
  nothing is read until somebody switches it on — and switching one off deletes its snapshot from disk
  as well as from memory. Scans are incremental against a `{path, mtime, size}` fingerprint cached in
  `~/.harness/desktop-app/usage-ledger-<provider>.json`, and `kLedgerStaleAfter` (5 min) keeps opening
  the pane from re-walking the disk; a cold Claude scan is ~3s over 71 transcripts, which is why
  neither of those is optional. Nothing polls — a ledger only moves when an agent writes here.
  ⚠️ **Local only, by decision.** Agents launched onto remote machines write their transcripts there and
  nothing here reaches them; the pane's subtitle says so, because a total that silently excluded most of
  a team's work would be worse than no total. `UsageSource` in `usage/usage_source.dart` is where a
  per-machine source would arrive if that changes.
  `sqlite3` is a **Dart-only FFI** dependency (never `sqlite3_flutter_libs`): it dlopens the system
  library, so it registers no native plugin and leaves the macOS SPM package list alone. `kUnderTest`
  keeps `UsageSection` from auto-loading, for the same reason the rail's poller does not start there.
  ⚠️ **The snapshot goes through `SnapshotStore` (`core/snapshot_store.dart`), and a test MUST pass
  `MemorySnapshotStore`** — this is not tidiness. A real `File.writeAsString` never completes inside
  `testWidgets`' fake-async zone, so a store awaiting one hangs the whole run until the shell is
  killed rather than failing; that seam is what keeps `dart:io` out of a widget test, exactly as
  `LocalKeyValueStore` does. It is deliberately NOT `LocalKeyValueStore`: that is `state.json`, one
  small locked document, and a multi-megabyte usage snapshot in it would be rewritten on every theme
  flip. `HarnessStats` uses the same seam.
- **Settings ▸ Usage has a second half, and it counts the APP rather than the CLIs**
  (`lib/stats/harness_stats.dart`, drawn by `StatsSummaryCards`). Ported from Orca's
  `src/main/stats/`: agents spawned, time agents worked, and a "Tracking since" line. These are this
  app's own events, so unlike the ledger there is no permission to ask and no switch — an app may
  count what it did. `harnessStats` is a singleton like `analytics`, loaded by
  `loadPersistedSettings` (not for the first frame — because the counters start moving as soon as an
  agent does, and a load landing after the first `onAgentSpawned` would overwrite it) and flushed by
  `AnalyticsLifecycle.didRequestAppExit`, which is the ONLY place a turn still running at quit gets
  its time counted.
  Three hooks, all in `AppNotifier`: `createAgent` (**not** the `agent_created` push, which also
  fires for agents another client made on the same machine), the `turn_started` case (**not**
  `turn_heartbeat`, which is a turn already under way), and `_cancelTurnActivity` plus the turn
  watchdog for the end. ⚠️ **The watchdog end is load-bearing**: it is the only close a stalled turn
  ever gets, and a stats turn left open would sit there until quit and then bank every hour since as
  work. A start on a live key is ignored rather than restarting the clock, and an end with no start
  contributes nothing — that is what makes the disconnect sweep safe.
  ⚠️ **Two deliberate departures from Orca.** The third card is TURNS, not PRs created: this app
  opens no pull requests, and a card wired to a number that can only read zero is worse than one
  showing something true. And no event log is kept — Orca persists 10,000 events beside its
  aggregates for breakdowns it does not draw, at ~900KB per write; `firstEventAt` is stored directly,
  which is the one thing that log was protecting.
- **The per-provider detail pane is ONE file, not three** (`settings/sections/usage_provider_pane.dart`
  with `usage_detail_panels.dart`), against Orca's near-identical `ClaudeUsagePane` /
  `CodexUsagePane` / `OpenCodeUsagePane`. Everything that differs between providers is already in
  `usage/ledger/usage_report.dart`; three copies of the layout would be three places to fix a
  spacing bug. The lens picker at the top of Settings ▸ Usage switches between the overview and one
  provider, and `_Lens` is a nullable `LedgerProvider` so the per-provider cases stay exactly the
  providers that exist.
  **The overview opens on the last 30 days**, the window Orca's default range shows, so a figure here
  can be compared against one there — `_kDefaultOverviewRange`. All-time is a click away in the same
  picker the provider panes carry. Measured on one machine: 30 days reads 3.2B tokens / 20 active days
  / 80 sessions, where all-time reads 3.8B / 33 / 92 — both true, answering different questions. The
  intensity grid draws a fixed six weeks whatever the range is, as Orca's does: `overview.days` is
  already clipped, so the days before the window fill in as EMPTY cells rather than as stray data, and
  shrinking the strip to the range only costs it the context a heatmap exists for. Clipping
  happens in `clipLedger` at draw time, not at scan time: the scan is the expensive half and does not
  depend on the window being looked at, and `ledgerFromEntries` is shared with `buildProviderLedger` so
  a clipped ledger cannot sum its cost differently from the full one.
  ⚠️ **There is a RANGE filter and deliberately no SCOPE filter.** Orca offers "Orca worktrees only"
  against "all local usage" because it owns the worktrees its agents run in. This app owns no such
  boundary — agents launched through Harness run on OTHER machines and write their transcripts there
  — so a "Harness only" lens over this computer's logs would filter on a distinction that does not
  exist here and would answer nearly zero. Everything local is counted and the pane says so.
  ⚠️ **OpenCode's `tokens_cache_read` is a PEER of `tokens_input`, not a subset — Orca gets this
  wrong and this app must not copy it.** `opencode-usage-row-parsing.ts` clamps it with
  `Math.min(cache.read, input)` on the assumption it is contained, the way Codex's cached input is.
  Measured against a live database, three of nine sessions read more from cache than they had input at
  all (7,680 cached against 72 input), which no subset can do; the clamp threw away 30.2k of 51.0k real
  cache reads and dropped them from the total besides. OpenCode's schema keeps `tokens_input`,
  `tokens_cache_read` and `tokens_cache_write` as three columns, the Anthropic shape rather than the
  OpenAI one. Codex remains the only provider whose input needs the subtraction.
  ⚠️ **`UsageSessionsTable` states its width instead of stretching.** Inside a horizontal
  `SingleChildScrollView` the incoming width is unbounded, so `CrossAxisAlignment.stretch` asks for
  an infinite row and the layout throws; `_sessionTableWidth` sums the columns, which is the only
  honest width it has.
- **The rail's two panels open the only surfaces this app grew that the CLI
  knows nothing about.** "View dashboard" opens the node dashboard
  (`lib/widgets/node_dashboard/`, logic in `grid/node_dashboard_view.dart`
  + `node_dashboard_layout.dart`) — one card per machine, off the same overview
  poll the rail already runs, so opening it starts no second timer.
  **It is a SCREEN, pushed the way `showSettingsScreen` is** — a faded
  `PageRouteBuilder`, "Back to app" rather than a close ✕, gutters instead of a
  1180×860 cap, so a wide display buys real extra columns. The dialog form
  (`node_dashboard_dialog.dart`, `showNodeDashboard`) is kept for callers that
  want a dismissable box, and **both surfaces draw the same
  `NodeDashboardBody`** (`node_dashboard_body.dart`) — a surface owns only its
  frame, its header and its way out, so the two can never drift into two
  dashboards that disagree. Each hands the body an `onLeaveSurface`, because the
  empty state's offers push Settings and pushing before leaving pops the thing
  just pushed. `NodeDashboardViewStore` is passed in rather than made per
  surface, so filters survive leaving the screen and coming back. Rows are
  laid out with `IntrinsicHeight`, never a `GridView`: a tile has to be given its
  height up front and the fullest cards overflowed the guess by 22px. **No card
  may contain a `LayoutBuilder`** for the same reason — `IntrinsicHeight` asks
  every child for its intrinsic height and `LayoutBuilder` throws rather than
  answer, so both tracks are `CustomPaint`. `NodeDashboardViewStore` holds the
  sort and filters for as long as the app runs (not persisted: a filter that
  survived a relaunch would greet somebody with half their grid hidden since
  yesterday).
  "Invite people to X" opens the share sheet (`lib/widgets/share_grid/`,
  `grid/grid_members_controller.dart`, `grid/invite_email.dart`) — invite,
  change a grant, remove. **A role change is ONE `POST …/members`**, which
  upserts; DELETE-then-POST drops the person off the grid entirely if its second
  half fails. Removing is the owner's alone and gates the whole trailing column;
  a member admitted by the grid's email domain has no row to delete, so it draws
  none. **"Who can join" is a STATEMENT, not a control** (`grid/grid_access.dart`):
  Grid lets an owner flip the rule, and flipping it restarts the grid under
  everyone on it — under one shared developer token that would land on somebody
  else's grid, in somebody else's name. The wire values are the control plane's
  own (`grid_networks/store.py`), not Grid's client enum, which only half
  overlaps them; a `private-domain` grid's NAME is its domain, which is where
  "@autonomous.ai emails" comes from, because `access_domain` reads null on
  every network `GET /v1/grid/me` returns.
- **Behavioural analytics is a PORT of Grid's, not a second design** (`lib/analytics/`, copied from
  `autonomous-grid-app/lib/infrastructure/analytics/`). It reports to **Autonomous Analytics**, the
  stream the website and Grid already feed, so one person's path across the three products is one
  funnel; `AnalyticsConfig.category` (`harness-desktop`) is what keeps them apart inside it. Not to
  be confused with the CLI's `harness analytics`, which is a different product entirely — aggregate
  usage metering uploaded to the Harness backend. ⚠️ **It reports under GRID's write key**, not one
  of its own: `_defaultWriteKey` is the same constant `autonomous-grid-app` ships, so both apps
  append into one analytics project and are separable **only by `category`**, not at the source —
  a quota, a retention rule or a rotated key set on that project lands on both at once
  (**TODO(BE)**: a Harness Desktop key is a one-constant change here). `--dart-define=HARNESS_ANALYTICS_KEY=…`
  overrides it for a dev build. It still mutes for three other reasons — `HARNESS_ANALYTICS_DISABLED`,
  a test run, and an opt-out (`{"enabled": false}` in `~/.harness/desktop-app/analytics.json`) —
  checked in that order so `flutter test` never reads a real Harness home. The sink is a **singleton** (`analytics`), like
  `themeModeStore`: the call sites are `main`, `AppNotifier`, a settings pane and a menu inside a
  pane header, and most were handed a notifier rather than a `Ref`. Every event name is written down
  **once**, in `analytics_events.dart` — two call sites naming one action differently is what makes
  a stream unqueryable — and params are product facts only: a short code, an option, a count, an id.
  **Never** a prompt, terminal output, an agent or machine name, a path, or a grid's name. Two
  events are deliberately not where you would look for them: `app_opened` is sent by `AppNotifier`
  when bootstrap resolves (a first-frame event would report every launch as signed out) and
  `grid_networks_loaded` by `GridNetworksController` on its first answer (both doors read that one
  shared controller, so a per-surface event would count one account twice). **The agent funnel is
  three events, one per step, because the interesting numbers are the DROPS between them**:
  `new_agent_opened` is sent by `showNewAgentDialog` itself rather than by its four callers, so a
  fifth door cannot forget to report (its `source` is `required`, not defaulted); `agent_created`
  is sent by the **dialog**, not `createAgent`, because only the dialog can tell Auto (`on_grid`
  true, no model) from the engine's own login (`on_grid` false) — both reach the notifier as one
  null override — and it covers EVERY agent, unlike `grid_agent_launched`, which counts only the
  ones pointed at a grid (so a grid agent fires both; `agent_created where on_grid` is the same set
  and is the one to build on); `app_first_message` rides the CLI's `turn_started` rather than the
  composer, so a message typed straight into the terminal counts, and it fires **once per signed-in
  session, not per agent** (`_awaitingFirstMessage`) — the question is how long somebody sits
  logged in before talking to anything at all, so it carries the wait and `from` (`sign_in` against
  `launch`, two populations that must not be averaged together) and deliberately names no agent,
  engine or machine. Sign-out clears the clock: a session that ended without a message reports
  nothing, and its absence is the finding. `app_closed` hooks only
  `didRequestAppExit` — intercepting the window's close button needs `setPreventClose(true)`, and a
  bug on that path leaves a window nobody can close.
  **Settings ▸ Tracking is where that stream is read back** (`analytics/analytics_log.dart`,
  `settings/sections/tracking_*.dart`, ported from Grid's Tracking tab), and it answers the
  question analytics always raises and normally cannot: *did that event actually leave, and what
  was in it?* — an event never sent, sent with a missing field, or refused by the server looks
  exactly like one that landed, because the app is silent either way by design. `QueuedAnalytics`
  reports each row's life to an `AnalyticsLog` (`queued → attempted → settled`), so a retry is
  **one row with two attempts** rather than two rows, and the dialog shows the payload *as sent*
  beside the params the call site passed — the gap between those two is the bug it exists to find.
  Gated by `kDebugSurfaceEnabled` like Settings ▸ Debug, which now hides two rail rows rather than
  one (`_kDeveloperSections` in `settings_section.dart` names both, once). **The muted case is the
  one that matters**: a build can send nothing for four separate reasons, and a Tracking screen that
  were blank for any of them would be the exact trap it exists to spring — hence `MutedAnalytics`,
  which records every event as `dropped` with the reason, and a header card
  that says `Off` and why in a sentence. A release build has no such screen and gets `NoopAnalytics`
  and a `NoopAnalyticsLog`, so nothing is retained for a surface that is not there. The buffer is
  in memory and never written to disk — a stream that measures the app must not become a second
  thing the app writes on every click — which is also why recording is right even for a user who
  opted out: their choice is about what we *send*, and this sends nothing.
- **Settings ▸ Providers is a SPLIT, not a table** (`settings/sections/provider_split_pane.dart`,
  framed by `grid_section.dart`): a rail of every provider on the left, and on the right everything
  about whichever one the rail has selected. Selecting a row READS a provider; `Make default` is
  what changes where agents launch — separated because the table's row-as-radio made looking at a
  provider indistinguishable from moving every new agent onto it. The panel prints what the old
  per-row drawer hid (id, signaling, owner, the router's models **by name**, created) with one
  deliberate omission: **`Provider type` is gone**, since it is the control plane's wire spelling
  (`permissioned-public`) of the rule "Who can join" states two rows above in words. Under 820px the
  two halves stack. ⚠️ **`GridHero` and `GridNetworkTable` are the pane this replaced and nothing
  builds them any more** — kept, not deleted, so the design can come back without being rewritten
  from the log; `grid_hero_test.dart` builds `GridHero` directly, which is the only way left to
  reach it, and is what stops it rotting silently.
- Settings is a **screen**, not a dialog (`lib/settings/`): `showSettingsScreen` pushes a faded route
  whose rail lists `settingsGroups` from `settings_section.dart` and whose pane is one widget per
  `SettingsSection` (`sections/`). Adding a setting means adding an enum value, a group entry and a
  section widget — nothing else. Panes are framed by `shared/widgets/section_scaffold.dart` (copied
  from Grid), and one setting inside a pane is a `shared/widgets/setting_row.dart` — a raised block
  with its title and detail on the left and its control, fixed at `SettingRow.controlWidth`, on the
  right. Appearance and Terminal both use it; a pane that invents its own row shape is the bug.
  Controls come from `shared/widgets/` too (`AppSelectField`, `AppIconButton`) — raw Material
  `DropdownButton`/`IconButton` do not match anything else in the app.
- **The log is written to files, and Settings ▸ Debug reads them back** (`lib/logging/`,
  `settings/sections/debug_*.dart`). `appLog` (`app-YYYYMMDD.log`) is the narrative — `app`, `ws`,
  `api`, `flutter` — and `cliLog` (`cli-YYYYMMDD.log`) is a transcript of every child process, both
  ported from Grid and both pruned after 14 days. The two CLI chokepoints write it:
  `HarnessCliRunner.run/start` and `GridCli.run/start` go through `logging/cli_transcript.dart`,
  which logs the command **as a person reads it** (`harness auth status --json`, never the managed
  tier's `<node> <cli.js>` argv) and never its environment — a key rides there precisely to stay out
  of argv. Both Dio clients carry `attachHttpLog`, one `api` line per finished request, method and
  URL only. **What a child PRINTS can still be a credential**, so CLI output and URLs go through
  `redactSecretsInText` (`logging/redact.dart`, beside the frame-level `redactValue`) before
  anything is written. The Debug pane is a **mirror** of those sinks, not a second stream
  (`log_stream.dart` + `log_stream_sinks.dart`): a bounded ring of the last 500 entries that
  `installFileLogs` tees into, so a line on screen is a line the file already has. It is developer
  furniture — `kDebugSurfaceEnabled` (`logging/debug_surface.dart`, `kDebugMode` or
  `--dart-define=HARNESS_DEBUG_SURFACE=true`) gates the rail row, the ⌘D shortcut
  (`kDebugShortcut`, in `appShortcuts()` rather than `kAppShortcuts`) and the ring itself; the log
  FILES are written either way, because a shipped app with no stderr is exactly the one whose logs
  matter.
- **A screen that waits on a call waits in the shape of its answer.** `shared/widgets/skeleton.dart`
  (`Skeleton`, `SkeletonText`, `SkeletonLine`, `SkeletonList`, `SkeletonBlock`) draws placeholders and
  `shared/widgets/pulse.dart` owns the app's one loading rhythm — an opacity breath between
  `AppSurface.recess` and `recessHover`, never a shimmer sweep, frozen at the **peak** under Reduce
  Motion because a block held at 40% reads as disabled. A spinner is still right where the shape is
  genuinely unknown (boot, a button mid-action); a list, table, card, row or figure gets a skeleton.
  Three rules the call sites keep, all guarded by `test/skeleton_test.dart` and
  `test/skeleton_sites_test.dart`: a placeholder is measured from the real content (`SkeletonText`
  lays out the style with a `TextPainter` rather than trusting arithmetic — see `AppMenuRowMetrics`
  for why), it wears the real row's surface and padding, and it is never **taller** than the answer
  usually is, since a skeleton that shrinks jumps the page upward. **"Loading" and "answered with
  nothing" must not render the same** — hence `AppNotifier.machinesLoading`, which is set on the
  first fetch only so a refresh keeps the rows already on screen. Same reason the status rail blanks
  its figures only before the first reading and `SharePane` blanks only before the first probe.
- `lib/shortcuts/app_shortcuts.dart` is the one list that feeds both the live bindings and the ⌘/
  sheet. `shortcutRows()` there is that list as the UI prints it — one row per action, so the two
  activators on "focus the next pane" (`⌘]`, `⌃⇥`) fold into one line, and `⌘1`–`⌘9` join as one.
  `shortcuts/shortcuts_list.dart` renders those rows in the two shapes the app needs and nothing
  else: `ShortcutsList` (the ⌘/ sheet's column, inside a 420px dialog) and `ShortcutsDeck` (Settings
  ▸ Keyboard shortcuts, group cards reflowed across the pane, plus the recessed "the terminal keeps"
  card built from `kTerminalOwnedKeys`). Same rows behind both, so they cannot disagree; keycaps come
  from `shortcuts/key_cap.dart`. Every shortcut is ⌘-based — Ctrl belongs to the shell/tmux, ⌥ is a
  Meta prefix for the pty, and ⌘C/⌘V/⌘A are owned by xterm — with one pinned exception, `⌃⇥`/`⌃⇧⇥`
  for the panes, which the terminal is made to let past.
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
