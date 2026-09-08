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

Settings → Devices discovers Autonomous devices on the same network using the
CLI's `_autonomous._tcp` discovery, reusing the device's existing advertisement. Start pairing on the Autonomous
device to generate its code, select that device in Desktop, and enter the code.
The Mac connects directly to the selected device without backend routing or a
manually entered IP address. The device needs no backend credentials; Harness’s
existing Mac login/start requirements remain unchanged.

Desktop uses `harness autonomous-device discover --json` to populate the picker.
The CLI resolves the selected discovery ID to its host and port. Pairing runs
`harness autonomous-device pair --code-stdin --device <discoveryId> --json` through
`HarnessCliRunner`; the code travels through stdin only, never argv or logs.
Code normalization matches the original Harness pairing implementation, including
Crockford aliases and separators. The original PAKE handshake authenticates the
connection. Changing or losing the selected discovery identity clears entered
code, and a code mismatch remains visible through background refreshes. A mismatch
consumes the device pairing window: generate a new code before retrying. Rate
limits require waiting five minutes before another attempt. Desktop allows the
pair command fifty seconds to finish, beyond the CLI’s bounded handshake deadline.

`status` and `list` report direct connections and saved device identities.
Revocation requires confirmation and targets the complete saved fingerprint.
Closing Desktop leaves the CLI daemon running. Discovery and status refresh every sixty seconds, including when no device is
paired. Use Refresh to discover a newly started device immediately. Pasted codes
may include separators, for example `ABC-123`. Older CLIs show `harness update`
guidance. Widget tests inject a fake CLI, and the `kUnderTest` gate prevents real
processes and background polling.

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

Pairing failures use the original Harness manager's validation and attempt limits.
If the device code expires, start pairing again on the Autonomous device.
