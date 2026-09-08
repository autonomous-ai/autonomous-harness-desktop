# Harness Desktop

Harness Desktop is the native Flutter client for browsing Harness machines and
interacting with their terminal-backed agents. It runs natively on **macOS
and Linux (Ubuntu)** and includes an unexercised Windows runner.

## Development

Install a compatible Flutter SDK, then run the project from this repository
root:

```bash
flutter pub get
flutter test
flutter run -d macos   # or: flutter run -d linux
```

Useful validation commands:

```bash
dart analyze
flutter build macos --debug
flutter build macos --release
flutter build linux --release   # must run on an Ubuntu host — no cross-compiling
```

The terminal core is vendored at `third_party/xterm`. Do not replace it with an
upstream package upgrade without preserving the local rendering and IME fixes.

## Local and production terminal E2E

The terminal E2E scripts exercise this desktop client together with source
checkouts of the Harness backend and CLI. Their default layout is:

```text
.../autonomous-ai/
  autonomous-code/
  autonomous-harness/
  autonomous-harness-desktop/
```

Set `AUTONOMOUS_CODE_ROOT` when the backend checkout is elsewhere and
`HARNESS_REPO_ROOT` when the Harness CLI checkout is elsewhere.

```bash
bash scripts/start-terminal-local-manual.sh
bash scripts/test-terminal-local-e2e.sh
PROD_TERMINAL_E2E=1 ... bash scripts/test-terminal-prod-e2e.sh
```

The production script deliberately requires release, deployment, machine, and
commit evidence before it sends terminal traffic to production.

## Autonomous device pairing

Open **Settings → Devices**, select **Pair an Autonomous device**, then enter the displayed
computer address and pairing code on the Autonomous device. The CLI owns the pairing deadline;
Desktop refreshes every two seconds during pairing and every sixty seconds
otherwise. **Refresh** also reads the current state manually.

**Replace Autonomous device** requires confirmation. The current Autonomous device keeps access until the
replacement completes an authenticated connection. Cancelling the pending pairing
keeps the current Autonomous device. **Revoke Autonomous device** removes the selected Autonomous device's access immediately
and requires confirmation. Closing Desktop does not stop the CLI daemon or revoke
pairing. The Autonomous device can interact only with agents on the paired computer.

The CLI contract is implemented in `autonomous-harness`:
`cli/src/lib/autonomous-device/transport.ts` — `pairStart` opens the pairing window without
revoking the current Autonomous device; `receive` confirms the replacement only after encrypted
`autonomous_device_finished` proves possession of the session key and signed welcome challenge.
`cli/src/lib/autonomous-device/store.ts` — `confirm` persists the new active identity.

An older CLI shows the `harness update` instruction. Desktop uses
`HarnessCliRunner.start` for `harness autonomous-device ... --json` so pairing codes are not
written to the process-output transcript. Codes remain in widget memory. Commands
that time out are not automatically retried. A polling response that omits the code
retains it only when `expiresAt` matches the same active pairing window; a terminal
state or a different window clears it. `lib/autonomous_device/autonomous_device_cli.dart` wraps the CLI,
and `test/autonomous_device_pairing_test.dart` covers this lifetime and the pairing UI.
Widget tests inject a fake `AutonomousDeviceCli`;
`kUnderTest` disables background polling and real CLI process execution.

## Releases

The application self-updates from the Harness desktop metadata manifest in the
public GCS release bucket. Release commands stay in this repository:

```bash
make upload-desktop           # macOS
make upload-desktop-linux     # Linux (ARM64 or x64) — must run on the matching Ubuntu build host
make upload-desktop-linux ARCH=arm64
make upload-desktop-linux ARCH=amd64  # amd64 is the x64 artifact
make upload-node-runtime ARGS="22.23.2"
```

See [RELEASE.md](RELEASE.md) for signing, notarization, versioning, managed
Node runtime publishing, safe test releases, and rollback behavior.
