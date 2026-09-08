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
  at all** — every run mints a fresh 365-day session and revokes nothing, so signing in on each
  launch would pile sessions onto the account, with `grid logout --everywhere` (all-or-nothing,
  every machine) as the only cleanup. An existing session is therefore left alone whoever owns it,
  which leaves Settings ▸ Grid one duty: `_AccountMismatch` says whose grids these are when the Grid
  CLI's account is not the Harness one. No session is a state,
  not an error: `GridSignedOutException` → `GridNetworksSignedOut` → the sign-in card in Settings ▸
  Grid, kept apart from `GridNetworksFailed` because that one offers a Retry and retrying a sign-out
  fails identically forever. `--dart-define=GRID_API_TOKEN=…` still pins a token for a build that
  wants an account it has not signed into here. **The hardcoded developer token is gone** — it was a
  real credential in the repo, and every build made from that branch read one person's grids.
  Response fields were read off the live API, not the OpenAPI spec, whose `/v1/grid/me` response
  schema is empty.
- **Picking a grid retargets NEW agents only.** `gridSelectionStore` (`lib/grid/`, persisted like
  `themeModeStore`, loaded in `loadPersistedSettings`) holds the chosen grid, and only the grid —
  **two** controls write it and they are the same store: the sidebar's grid pill
  (`widgets/grid_target_pill.dart`, above the account footer — one menu, where the answer is already
  on screen) and Settings ▸ Grid, which keeps the table because that is where a grid is *compared*
  rather than merely picked. Both list `gridNetworksController`, the shared singleton, so neither
  holds a half-stale copy. The label for "no grid" is `kNoGridTargetLabel` beside the store — four
  places print it. The model is chosen per agent, not globally, and
  **only once the agent exists**: the agent view's header menu (`widgets/agent_model_menu.dart`)
  picks it for a running agent, and the New agent dialog offers no model at all — every new agent
  launches on Auto (no `model` on the wire, the grid chooses), because a model picked before there
  is an agent to apply it to is a second door onto a setting the header menu already owns. At create
  time the New agent
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
  `lib/gridWebMcp.ts` wires it into claude, codex, opencode and hermes as an MCP server named
  `grid-web`.
  **The control plane, not the relay** (grid ADR 0041 D-a: a relay is per-grid, can be asleep, and
  may be a LAN address), built from the *session's* `apiBaseUrl` so a `grid` signed into staging does
  not send agents at production. The address is sent rather than derived because the machine running
  the agent may have no Grid session at all. **No second credential**: ADR 0041 D-b takes the
  per-grid access token and requires no scope of it, `consumer` included, which is exactly what
  `/networks/{id}/credentials` mints. The three engines are the three `grid mcp config` prints for —
  the ones whose header handling was measured on the wire. ⚠️ The key still travels only in the
  pane's environment: Claude Code expands `${GRID_API_KEY}` inside `--mcp-config` (the JSON-string
  form, so no file), Codex reads `env_http_headers` off `-c`, opencode expands `{env:…}` in the
  config the launch already writes, and hermes interpolates `${…}` Cursor-style in a **managed-scope
  overlay** (`HERMES_MANAGED_DIR`, deep-merged over the user's `config.yaml` — not `HERMES_HOME`,
  which would move auth, sessions and memory too). That is the OPPOSITE of ADR 0041 D-d, which is
  right about a person pasting into their own dotfile and wrong here, where the daemon owns both
  ends. ⚠️ Hermes' overlay REPLACES `/etc/hermes` rather than adding to it, so `cli.ts` drops it on a
  machine that has one and the agent starts without web tools instead of losing an administrator's
  policy. An absent `mcpUrl` wires nothing, so an older desktop launches exactly as it did.
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
  **Manage models is the one part of this feature that is NOT the Grid CLI**: the shelf is
  `POST /v1/grid/catalog` on the control plane (`GridApiClient.catalog`/`catalogDetail`, the same
  bearer as the Grid tab), because `grid catalog` answers with two or three picks ranked for THIS
  machine and that is far too short to browse. Both are shown, labelled apart. A version's
  `pull_spec` names only the FIRST file, so a split GGUF is downloaded through every URL in `urls`
  (`share/pull_spec.dart`) — pulling the named one alone leaves a model that will not load.
- **The status rail is the app's one polling reader** (`lib/widgets/status_rail/`,
  `grid/grid_overview_controller.dart`): a 26px full-bleed strip along the window's bottom edge
  showing what the chosen grid is made of. Its data is `GET {relay}/grid/overview` — the RELAY, not
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
