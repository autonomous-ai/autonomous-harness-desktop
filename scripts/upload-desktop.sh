#!/usr/bin/env bash
# Release the desktop app: bump version -> build -> notarize -> zip -> upload to a PUBLIC GCS bucket.
# The running app polls the manifest (DesktopUpdater) and offers to restart when a newer build
# lands. See RELEASE.md.
#
# Usage:
#   bash scripts/upload-desktop.sh              # auto-bump (1.2.3 -> 1.2.4; 1.2.99 -> 1.3.1)
#   bash scripts/upload-desktop.sh --force       # bump the MINOR version (1.2.3 -> 1.3.1) — running
#                                                 # apps treat this as a mandatory update and block
#                                                 # until they install it (see desktop_updater.dart)
#   bash scripts/upload-desktop.sh 1.3.0         # release an explicit version (a major bump, e.g.
#                                                 # 2.0.0, is also forced — no separate flag for it)
#   bash scripts/upload-desktop.sh --no-bump     # keep the current published version, build + upload
#   bash scripts/upload-desktop.sh --no-build    # upload the existing build/ artifact as-is
#   bash scripts/upload-desktop.sh --no-notarize # skip Apple notarization (Developer ID signed only)
#   GCS_BUCKET=other bash scripts/upload-desktop.sh   # env overrides (see below)
#
# The CURRENT version is read from the remote metadata.json on GCS (single source of truth) and the
# patch is bumped from there — nothing is git-committed, and `pubspec.yaml`'s `version:` field is
# never touched. The version is stamped into the built bundle's Info.plist via `flutter build`'s
# `--build-name`/`--build-number` flags, and this script asserts the artifact really carries it
# before publishing, so the running release always equals the published manifest version.
#
# Prereqs: `gsutil` authenticated with WRITE access; the bucket/objects must be public-read;
# `flutter` on PATH; the Xcode project signs Release with a "Developer ID Application" identity
# (see macos/Runner.xcodeproj — CODE_SIGN_IDENTITY/DEVELOPMENT_TEAM) whose certificate + private key
# must be in this machine's LOGIN keychain (NOT the System keychain — that one prompts for an admin
# password on every codesign, which a non-interactive build can't answer). For notarization, a
# `notarytool` keychain profile must exist — one-time setup, run once yourself (never pass the
# password as a script argument or env var, it would land in shell history):
#   xcrun notarytool store-credentials "harness-notarize" \
#     --apple-id "you@example.com" --team-id "54DJVWMJCC" --password "xxxx-xxxx-xxxx-xxxx"
# (an app-specific password from appleid.apple.com, not your Apple ID password). Override the
# profile name with NOTARY_PROFILE if you used a different one, or skip notarizing with
# --no-notarize (the build stays Developer ID signed, just without Apple's online-verifiable ticket
# — Gatekeeper is more likely to warn on a copy downloaded fresh by someone else).
set -euo pipefail
set +x

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repository root
APP_BUNDLE="$APP_DIR/build/macos/Build/Products/Release/Harness.app"

# --- GCS config (all overridable via env) ---
GCS_BUCKET="${GCS_BUCKET:-s3-autonomous-upgrade-3}"
GCS_PUBLIC_BASE_URL="${GCS_PUBLIC_BASE_URL:-https://storage.googleapis.com/${GCS_BUCKET}}"
METADATA_PATH="${METADATA_PATH:-harness/desktop/metadata.json}"
OTA_KEY="${OTA_KEY:-desktop-macos}"   # must match _otaKey in lib/update/desktop_updater.dart

next_desktop_version() {
  local current="$1" major minor patch
  if [[ ! "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: version '$current' must look like X.Y.Z" >&2
    return 1
  fi
  major=$((10#${BASH_REMATCH[1]}))
  minor=$((10#${BASH_REMATCH[2]}))
  patch=$((10#${BASH_REMATCH[3]}))
  if (( patch >= 99 )); then
    printf '%d.%d.1\n' "$major" "$((minor + 1))"
  else
    printf '%d.%d.%d\n' "$major" "$minor" "$((patch + 1))"
  fi
}

# Same "reset to .1, not .0" convention as next_desktop_version()'s patch rollover above — kept
# consistent so "the next minor" means the same thing everywhere. A minor bump is what running apps
# treat as a mandatory update (see isForcedUpdate() in lib/update/desktop_updater.dart).
bump_minor_version() {
  local current="$1" major minor
  if [[ ! "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: version '$current' must look like X.Y.Z" >&2
    return 1
  fi
  major=$((10#${BASH_REMATCH[1]}))
  minor=$((10#${BASH_REMATCH[2]}))
  printf '%d.%d.1\n' "$major" "$((minor + 1))"
}

# Deterministic integer CFBundleVersion from X.Y.Z — `flutter build`'s --build-number needs an int,
# and this way it never has to be tracked separately from the version we're actually publishing.
build_number_for() {
  local ver="$1" major minor patch
  IFS='.' read -r major minor patch <<< "$ver"
  printf '%d\n' "$(( (10#$major * 10000) + (10#$minor * 100) + 10#$patch ))"
}

# --- Parse args (optional explicit version + flags) ---
NEW_VER=""
DO_BUMP=1
DO_FORCE=0
DO_BUILD=1
DO_NOTARIZE=1
for arg in "$@"; do
  case "$arg" in
    --force)       DO_FORCE=1 ;;
    --no-bump)     DO_BUMP=0 ;;
    --no-build)    DO_BUILD=0 ;;
    --no-notarize) DO_NOTARIZE=0 ;;
    -*)            echo "error: unknown flag '$arg'" >&2; exit 1 ;;
    *)             NEW_VER="$arg" ;;
  esac
done
if [ "$DO_FORCE" -eq 1 ] && [ "$DO_BUMP" -eq 0 ]; then
  echo "error: --force and --no-bump contradict each other" >&2
  exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-harness-notarize}"

command -v gsutil  >/dev/null 2>&1 || { echo "error: gsutil not found — install/authenticate the gcloud SDK" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }
command -v flutter >/dev/null 2>&1 || { echo "error: flutter not found" >&2; exit 1; }
if [ "$DO_NOTARIZE" -eq 1 ]; then
  command -v xcrun >/dev/null 2>&1 || { echo "error: xcrun not found — install Xcode command line tools" >&2; exit 1; }
fi

cleanup() { rm -f "${SRC:-}" "${DST:-}"; }
trap cleanup EXIT

# --- Step 1: resolve the version (source of truth = remote metadata.json) ---
META_URL="${GCS_PUBLIC_BASE_URL%/}/${METADATA_PATH#/}"
CUR="$(curl -fsSL "$META_URL" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get(sys.argv[1], {}).get("version", ""))
except Exception:
    print("")
' "$OTA_KEY" 2>/dev/null || true)"
CUR="$(printf '%s' "$CUR" | tr -d '[:space:]')"
if [ -n "$CUR" ]; then
  echo ">> current published version (from metadata.json): $CUR"
else
  CUR="1.0.0"
  echo ">> could not read remote metadata — starting from $CUR" >&2
fi
if [ -n "$NEW_VER" ]; then
  VER="$NEW_VER"                                   # explicit version wins
elif [ "$DO_FORCE" -eq 1 ]; then
  VER="$(bump_minor_version "$CUR")"
elif [ "$DO_BUMP" -eq 1 ]; then
  VER="$(next_desktop_version "$CUR")"
else
  VER="$CUR"                                       # --no-bump: keep current
fi
BUILD_NUM="$(build_number_for "$VER")"
echo ">> releasing version: $VER (build $BUILD_NUM)"

# --- Step 2: build ---
if [ "$DO_BUILD" -eq 1 ]; then
  echo ">> building release $VER"
  # Xcode's incremental build sometimes decides the Info.plist processing step is already
  # up to date and skips re-stamping MARKETING_VERSION/CURRENT_PROJECT_VERSION into it, silently
  # leaving a PREVIOUS build's version (or pubspec.yaml's dev placeholder) in the bundle even
  # though --build-name/--build-number were passed correctly. Removing the bundle first forces a
  # real rebuild instead of trusting the cache — the STAMPED check below still verifies it caught
  # this rather than relying on it never happening again.
  rm -rf "$APP_BUNDLE"
  ( cd "$APP_DIR" && flutter build macos --release --build-name="$VER" --build-number="$BUILD_NUM" )
else
  echo ">> skipping build (--no-build)"
fi
[ -d "$APP_BUNDLE" ] || { echo "error: app bundle missing: $APP_BUNDLE — drop --no-build" >&2; exit 1; }

# The bundle must actually carry the version we are about to advertise; publishing a manifest entry
# that points at a differently-stamped build would make the running app compare against a version it
# never actually receives.
STAMPED="$(plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
[ "$STAMPED" = "$VER" ] || { echo "error: bundle CFBundleShortVersionString is '$STAMPED', expected '$VER'" >&2; exit 1; }

# --- Step 3: package ---
ZIP="$APP_DIR/build/Harness-macos-$VER.zip"
rm -f "$ZIP"
echo ">> packaging $ZIP"
( cd "$(dirname "$APP_BUNDLE")" && ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP_BUNDLE")" "$ZIP" )

# --- Step 3b: notarize + staple ---
# Apple's notary service inspects a zip (or the .app directly) and returns a ticket; stapling
# embeds that ticket INTO the .app so Gatekeeper can verify it offline on first launch, without
# reaching Apple's servers. Stapling changes the .app's contents, so the zip submitted above is
# now stale — it has to be rebuilt from the stapled bundle before it's the thing that gets uploaded.
if [ "$DO_NOTARIZE" -eq 1 ]; then
  echo ">> submitting for notarization (keychain profile: $NOTARY_PROFILE)"
  # `submit --wait` exits 0 once it has a TERMINAL status, even if that status is "Invalid" — a
  # rejected submission is not a tool failure as far as its own exit code is concerned, so the
  # verdict has to be read out of the response instead of trusted from $?.
  NOTARY_JSON="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  echo "$NOTARY_JSON"
  NOTARY_STATUS="$(printf '%s' "$NOTARY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)"
  NOTARY_ID="$(printf '%s' "$NOTARY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
  if [ "$NOTARY_STATUS" != "Accepted" ]; then
    echo "error: notarization did not succeed (status: ${NOTARY_STATUS:-unknown}) — full reasons:" >&2
    xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
  fi
  echo ">> stapling notarization ticket to $APP_BUNDLE"
  xcrun stapler staple "$APP_BUNDLE"

  echo ">> re-packaging $ZIP with the stapled ticket"
  rm -f "$ZIP"
  ( cd "$(dirname "$APP_BUNDLE")" && ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP_BUNDLE")" "$ZIP" )

  # Fails closed rather than silently shipping a build Gatekeeper would reject on someone else's Mac.
  spctl -a -vv --type execute "$APP_BUNDLE" || {
    echo "error: Gatekeeper assessment failed on the stapled bundle" >&2
    exit 1
  }
else
  echo ">> skipping notarization (--no-notarize) — Developer ID signed only"
fi

# --- Step 4: upload the artifact + merge the manifest ---
GCS_PATH="${GCS_PATH:-harness/desktop/${VER}/Harness-macos.zip}"
URL="${GCS_PUBLIC_BASE_URL%/}/${GCS_PATH#/}"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
SIZE="$(wc -c < "$ZIP" | tr -d ' ')"

echo ">> uploading release $VER ($SIZE bytes, sha256=$SHA)"
echo "   dest: gs://${GCS_BUCKET}/${GCS_PATH}"
gsutil -h "Cache-Control:no-cache, no-store, must-revalidate" cp "$ZIP" "gs://${GCS_BUCKET}/${GCS_PATH}"

echo ">> merging manifest: gs://${GCS_BUCKET}/${METADATA_PATH}  (${OTA_KEY})"
SRC="$(mktemp)"; DST="$(mktemp)"   # removed by cleanup() on EXIT
if ! gsutil cp "gs://${GCS_BUCKET}/${METADATA_PATH}" "$SRC" 2>/dev/null; then
  echo "   (no existing metadata.json — creating a new one)"
  printf '{}' > "$SRC"
fi
# NOTE: pass paths/values via argv, NEVER pipe the existing JSON into this heredoc — the heredoc
# claims stdin, so the pipe is silently dropped and every upload would blank metadata.json.
python3 - "$SRC" "$DST" "$OTA_KEY" "$VER" "$URL" "$SHA" "$SIZE" <<'PY'
import json, sys
src, dst, key, version, url, sha, size = sys.argv[1:8]
try:
    with open(src) as f:
        raw = f.read()
    data = json.loads(raw) if raw.strip() else {}
except (OSError, json.JSONDecodeError):
    data = {}
if not isinstance(data, dict):
    data = {}
data[key] = {"version": version, "url": url, "sha256": sha, "size": int(size)}
with open(dst, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
gsutil -h "Content-Type:application/json" \
       -h "Cache-Control:no-cache, no-store, must-revalidate" \
       cp "$DST" "gs://${GCS_BUCKET}/${METADATA_PATH}"

echo
echo ">> published desktop app $VER"
echo "   url:      $URL"
echo "   sha256:   $SHA"
echo "   manifest: ${GCS_PUBLIC_BASE_URL%/}/${METADATA_PATH#/}"
echo "   Running apps poll this on their own schedule (DesktopUpdater, every few hours + on launch)."
