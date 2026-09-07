# Releasing the desktop app

Running apps self-update from a public GCS bucket (`lib/update/desktop_updater.dart`). Publishing is
a single command run from a machine with an authenticated `gsutil` and `flutter` on PATH.

```bash
make upload-desktop                     # auto-bump (1.2.3 -> 1.2.4; 1.2.99 -> 1.3.1)
make upload-desktop ARGS="--force"      # bump the MINOR version (1.2.3 -> 1.3.1) — running apps
                                         # treat this as a mandatory update and block until installed
make upload-desktop ARGS="1.3.0"        # release an explicit version (a major bump is forced too)
make upload-desktop ARGS="--no-bump"    # keep the current published version, rebuild + upload
make upload-desktop ARGS="--no-build"   # upload the existing build/ artifact as-is
```

## Managed Node runtime

The first-run desktop bootstrap installs Node under `~/.harness/runtime`; it does not alter the
user's system Node, Homebrew, nvm, or shell PATH. Publish both macOS architectures before releasing
a desktop build that requires a new Node version:

```bash
make upload-node-runtime ARGS="22.16.0"
```

The publisher downloads the official Node archives and `SHASUMS256.txt`, verifies each archive before
uploading, then atomically merges `harness/runtime/metadata.json`. The app verifies the manifest's
size and SHA-256 again before extracting an archive. A runtime manifest applies to fresh installs;
roll out a changed runtime to existing users with a newer desktop build. Never replace an existing
versioned archive in place.

Until that managed manifest exists, the desktop build falls back to its checksum-pinned official
Node 22 archive. The fallback keeps first-run setup functional but is intentionally not a replacement
for publishing the managed runtime channel before release.

## What the script does

1. Reads the current version from the **remote** `metadata.json` and bumps the patch. The manifest is
   the single source of truth — nothing is git-committed, matching the CLI/firmware/orangepi flows.
   `pubspec.yaml`'s `version:` field is never touched; it's a dev-only placeholder.
2. Runs `flutter build macos --release --build-name=<version> --build-number=<n>` — the version is
   stamped into the bundle's `Info.plist` at build time, not read from any file.
3. Asserts the built bundle's `CFBundleShortVersionString` really carries that version before
   publishing anything.
4. Packages the `.app` with `ditto -c -k --sequesterRsrc --keepParent` (keeps the bundle structure and
   extended attributes intact — a plain `zip` does not).
5. Uploads the zip with `Cache-Control: no-cache`.
6. Download-merge-reuploads `metadata.json`, touching only the `desktop-macos` key.

A failed build stops the release; nothing is uploaded and no version is consumed.

## GCS layout

```
gs://s3-autonomous-upgrade-3/harness/desktop/metadata.json
gs://s3-autonomous-upgrade-3/harness/desktop/<version>/Harness-macos.zip
```

```json
{
  "desktop-macos": {
    "version": "1.2.4",
    "url": "https://storage.googleapis.com/s3-autonomous-upgrade-3/harness/desktop/1.2.4/Harness-macos.zip",
    "sha256": "<64 hex>",
    "size": 45231920
  }
}
```

The bucket must be public-read — that is bucket policy, not something the script sets.

## Signing — Developer ID, notarized

The Release build is signed with a real **Developer ID Application** certificate (team
`54DJVWMJCC`, "Autonomous Inc.") and notarized — a freshly downloaded copy (browser, Slack,
AirDrop — anything that sets the `com.apple.quarantine` extended attribute) passes Gatekeeper with
no "unidentified developer" prompt and no manual Open Anyway/`xattr -d` workaround needed.

What that takes, end to end:

- **The signing certificate** (`Developer ID Application: Autonomous Inc. (54DJVWMJCC)`) must be in
  the machine's **login** keychain — not the System keychain, which prompts for an admin password
  on every `codesign` invocation and breaks a non-interactive build. `security find-identity -v -p
  codesigning` should list it with no password needed to check.
- **`macos/Runner.xcodeproj`**'s Runner target Release config carries `CODE_SIGN_STYLE = Manual`,
  `CODE_SIGN_IDENTITY = "Developer ID Application"`, `DEVELOPMENT_TEAM = 54DJVWMJCC`,
  `ENABLE_HARDENED_RUNTIME = YES`, and `OTHER_CODE_SIGN_FLAGS = "--timestamp"` — notarization hard-
  rejects a signature with no secure timestamp ("Archive contains critical validation errors"), and
  Manual signing style doesn't request one on its own the way Automatic does.
- **`macos/Runner/Release.entitlements`** pins `com.apple.security.get-task-allow` to `false` —
  Flutter's build backend stamps this `true` regardless of build mode, and notarization rejects a
  debugger-attachable binary outright.
- **A `notarytool` keychain profile** must exist for the script's notarize step (see the comment
  block at the top of `scripts/upload-desktop.sh` for the one-time `store-credentials` setup —
  needs an app-specific password from appleid.apple.com, never the Apple ID's own password).

`scripts/upload-desktop.sh` submits the packaged zip to Apple's notary service (`notarytool submit
--wait`), staples the returned ticket onto the `.app` (`stapler staple` — this changes the bundle's
contents, so the zip is rebuilt from the stapled bundle before upload), and asserts `spctl -a`
accepts the result before publishing anything. Skip notarizing with `--no-notarize` (the build
stays Developer ID signed, just without Apple's ticket — more likely to prompt Gatekeeper on a copy
downloaded fresh by someone else, though probably still fine for the OTA self-update path below,
which doesn't reliably pick up the quarantine flag in the first place).

## How a running app self-updates

1. `DesktopUpdater` checks the manifest once on launch, then every few hours
   (`lib/update/desktop_updater.dart`).
2. Compares against the running app's own version (`package_info_plus`) — strictly newer only, so
   republishing an old build cannot downgrade anyone.
3. After the user chooses **Update now**, downloads the zip and verifies its sha256 **before** anything is unpacked. A mismatch is discarded.
4. Unpacks into a staging directory and re-reads `CFBundleShortVersionString` from the staged bundle as
   a sanity check that the download really is the version it claims to be.
5. Checks on launch (including the sign-in screen) and every few hours. When a newer build exists,
   it shows a non-blocking notification. The user chooses **Update now** to download and install it,
   or **Skip version** to silence that exact version. A later version is shown normally; the account
   menu also has **Check for updates** to revisit a skipped version.
6. On restart: a detached helper process waits for this app to exit, backs the current bundle up as
   `Harness.app.prev`, swaps the staged build into place, relaunches it, and — if the relaunched app
   doesn't stay alive a few seconds later — restores `Harness.app.prev` and relaunches the old build
   instead.

## Rolling out safely

Publish to a scratch manifest before touching the real one, and point a test build at it via
`--dart-define`:

```bash
METADATA_PATH=harness/desktop/metadata-test.json make upload-desktop
```

```bash
flutter run -d macos --dart-define=DESKTOP_UPDATE_METADATA_URL=https://storage.googleapis.com/s3-autonomous-upgrade-3/harness/desktop/metadata-test.json
```

## Rollback

The relaunch-health check (step 6 above) only guards against a build that fails to start. To roll back
a build that starts but is otherwise broken, publish a **higher** version containing the older code —
the updater refuses to move backwards, so editing the manifest to an older version will not roll a
running app back.

## Linux

`make upload-desktop-linux` (`scripts/upload-desktop-linux.sh`) is the Linux (x64) counterpart of
`make upload-desktop`, publishing to the **same** `metadata.json` under a different key so both
platforms share one version number by default:

```bash
make upload-desktop-linux                     # auto-bump, same version semantics as upload-desktop
make upload-desktop-linux ARGS="--force"      # mandatory update, same rule as macOS
make upload-desktop-linux ARGS="1.3.0"        # explicit version
make upload-desktop-linux ARGS="--no-bump"
make upload-desktop-linux ARGS="--no-build"
```

Must run on an actual Ubuntu/Linux build host — `flutter build linux` cannot cross-compile a Linux
bundle from macOS or Windows.

**No signing/notarization step** — there is no Linux equivalent of Apple's Developer ID/notarization,
and none is needed: the trust boundary is the same sha256-verified manifest entry `DesktopUpdater`
already checks on every platform.

**No Info.plist-style version stamp.** `flutter build linux` has nowhere to stamp a version the way
Xcode does into `Info.plist`, so the release script writes a plain `version.txt` into the built
bundle (`build/linux/x64/release/bundle/version.txt`) and asserts it before packaging. Both
`lib/core/app_version.dart` (what Settings ▸ About shows) and `lib/update/desktop_updater.dart`'s
`downloadAndStage()` (verifying a downloaded update) read this file back on Linux, falling through to
`PackageInfo.fromPlatform()` (which would otherwise just return `pubspec.yaml`'s never-bumped
placeholder) everywhere else.

### GCS layout

```
gs://s3-autonomous-upgrade-3/harness/desktop/metadata.json          (shared with macOS, different key)
gs://s3-autonomous-upgrade-3/harness/desktop/<version>/Harness-linux-x64.tar.gz
```

```json
{
  "desktop-linux-x64": {
    "version": "1.2.4",
    "url": "https://storage.googleapis.com/s3-autonomous-upgrade-3/harness/desktop/1.2.4/Harness-linux-x64.tar.gz",
    "sha256": "<64 hex>",
    "size": 41230011
  }
}
```

The archive's top-level directory is always named `Harness/` (the release script stages the built
`bundle/` under that name before tarring it) — `lib/update/desktop_updater.dart`'s
`downloadAndStage()` expects the unpacked archive at `<stagingDir>/Harness`, matching the installed
layout `apps/web/src/app/desktop/install.sh` (in `autonomous-code`) creates at
`~/.local/opt/Harness`.

### How a running Linux app self-updates

Same shape as macOS (see above), with the platform-specific pieces:

1. `DesktopUpdater` reads the `desktop-linux-x64` manifest entry instead of `desktop-macos`.
2. The downloaded archive is a `.tar.gz`, unpacked with `tar` instead of `ditto`.
3. The staged bundle's version comes from its `version.txt`, not an `Info.plist` extraction.
4. On restart, the detached helper `mv`s the install directory (`~/.local/opt/Harness` by default)
   the same way the macOS script swaps `Harness.app`, then execs the bundle's own `harness` binary
   directly (there's no `open -n`/LaunchServices equivalent for a plain packaged Linux binary) and
   checks it's still alive with `pgrep -f`, same as macOS.

### Rolling out safely / rollback

Same conventions as macOS — publish to a scratch `METADATA_PATH` first, and roll back only by
publishing a newer version containing the older code (see above).
