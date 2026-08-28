# Harness Desktop

Harness Desktop is the native Flutter client for browsing Harness machines and
interacting with their terminal-backed agents. It runs natively on macOS and
includes Linux and Windows runners.

## Development

Install a compatible Flutter SDK, then run the project from this repository
root:

```bash
flutter pub get
flutter test
flutter run -d macos
```

Useful validation commands:

```bash
dart analyze
flutter build macos --debug
flutter build macos --release
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

## Releases

The application self-updates from the Harness desktop metadata manifest in the
public GCS release bucket. Release commands stay in this repository:

```bash
make upload-desktop
make upload-node-runtime ARGS="22.16.0"
```

See [RELEASE.md](RELEASE.md) for signing, notarization, versioning, managed
Node runtime publishing, safe test releases, and rollback behavior.
