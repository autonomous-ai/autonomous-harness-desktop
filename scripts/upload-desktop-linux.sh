#!/usr/bin/env bash
# Release the Linux desktop app: bump version -> build -> package -> upload to a PUBLIC GCS bucket.
# Mirrors scripts/upload-desktop.sh (macOS) — see RELEASE.md for the shared design this follows.
# There is no Apple-equivalent signing/notarization step here: the running app self-updates from a
# checksum-verified manifest entry (DesktopUpdater), which is the trust boundary on both platforms.
#
# Usage:
#   bash scripts/upload-desktop-linux.sh              # auto-bump (1.2.3 -> 1.2.4; 1.2.99 -> 1.3.1)
#   bash scripts/upload-desktop-linux.sh --force       # bump the MINOR version (1.2.3 -> 1.3.1) —
#                                                       # running apps treat this as a mandatory
#                                                       # update (see desktop_updater.dart)
#   bash scripts/upload-desktop-linux.sh 1.3.0         # release an explicit version (a major bump,
#                                                       # e.g. 2.0.0, is also forced)
#   bash scripts/upload-desktop-linux.sh --no-bump     # keep the current published version, build + upload
#   bash scripts/upload-desktop-linux.sh --no-build    # upload the existing build/ artifact as-is
#   GCS_BUCKET=other bash scripts/upload-desktop-linux.sh   # env overrides (see below)
#
# The CURRENT version is read from the remote metadata.json on GCS — the SAME manifest the macOS
# script publishes to, under a different key (desktop-linux-x64) — so both platforms share one
# version number by default. Nothing is git-committed; pubspec.yaml's `version:` field is never
# touched (see RELEASE.md).
#
# `flutter build linux` has no Info.plist-style version stamping, so this script writes a plain
# version.txt into the built bundle instead — read back by lib/core/app_version.dart at runtime and
# by lib/update/desktop_updater.dart's downloadAndStage() when verifying a downloaded update.
#
# Prereqs: `gsutil` authenticated with WRITE access; the bucket/objects must be public-read;
# `flutter` on PATH; must run on an actual Linux (Ubuntu) build host — `flutter build linux` cannot
# cross-compile a Linux bundle from macOS or Windows.
set -euo pipefail
set +x

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repository root
BUNDLE_DIR="$APP_DIR/build/linux/x64/release/bundle"

# --- GCS config (all overridable via env) ---
GCS_BUCKET="${GCS_BUCKET:-s3-autonomous-upgrade-3}"
GCS_PUBLIC_BASE_URL="${GCS_PUBLIC_BASE_URL:-https://storage.googleapis.com/${GCS_BUCKET}}"
METADATA_PATH="${METADATA_PATH:-harness/desktop/metadata.json}"
OTA_KEY="${OTA_KEY:-desktop-linux-x64}"   # must match _otaKeyLinux in lib/update/desktop_updater.dart

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
# consistent with scripts/upload-desktop.sh so "the next minor" means the same thing on both
# platforms. A minor bump is what running apps treat as a mandatory update.
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

# --- Parse args (optional explicit version + flags) ---
NEW_VER=""
DO_BUMP=1
DO_FORCE=0
DO_BUILD=1
for arg in "$@"; do
  case "$arg" in
    --force)       DO_FORCE=1 ;;
    --no-bump)     DO_BUMP=0 ;;
    --no-build)    DO_BUILD=0 ;;
    -*)            echo "error: unknown flag '$arg'" >&2; exit 1 ;;
    *)             NEW_VER="$arg" ;;
  esac
done
if [ "$DO_FORCE" -eq 1 ] && [ "$DO_BUMP" -eq 0 ]; then
  echo "error: --force and --no-bump contradict each other" >&2
  exit 1
fi

[ "$(uname -s)" = "Linux" ] || { echo "error: this must run on a Linux build host — flutter build linux cannot cross-compile" >&2; exit 1; }
command -v gsutil  >/dev/null 2>&1 || { echo "error: gsutil not found — install/authenticate the gcloud SDK" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }
command -v flutter >/dev/null 2>&1 || { echo "error: flutter not found" >&2; exit 1; }
command -v tar      >/dev/null 2>&1 || { echo "error: tar not found" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "error: sha256sum not found" >&2; exit 1; }

cleanup() { rm -f "${SRC:-}" "${DST:-}"; rm -rf "${STAGE_ROOT:-}"; }
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
echo ">> releasing version: $VER"

# --- Step 2: build ---
if [ "$DO_BUILD" -eq 1 ]; then
  echo ">> building release $VER"
  rm -rf "$BUNDLE_DIR"
  ( cd "$APP_DIR" && flutter build linux --release )
else
  echo ">> skipping build (--no-build)"
fi
[ -d "$BUNDLE_DIR" ] || { echo "error: build bundle missing: $BUNDLE_DIR — drop --no-build" >&2; exit 1; }
[ -x "$BUNDLE_DIR/harness" ] || { echo "error: no harness executable in $BUNDLE_DIR" >&2; exit 1; }

# flutter build linux has no Info.plist-style version stamp — write one ourselves, and assert it
# before packaging so the published manifest always matches what's actually inside the archive.
echo "$VER" > "$BUNDLE_DIR/version.txt"
STAMPED="$(cat "$BUNDLE_DIR/version.txt")"
[ "$STAMPED" = "$VER" ] || { echo "error: version.txt is '$STAMPED', expected '$VER'" >&2; exit 1; }

# --- Step 3: package ---
# The archive's top-level directory name (Harness/) is part of the contract: downloadAndStage() in
# lib/update/desktop_updater.dart expects the unpacked bundle at "$stagingDir/Harness".
STAGE_ROOT="$(mktemp -d)"
cp -a "$BUNDLE_DIR" "$STAGE_ROOT/Harness"
TARBALL="$APP_DIR/build/Harness-linux-x64-$VER.tar.gz"
rm -f "$TARBALL"
echo ">> packaging $TARBALL"
( cd "$STAGE_ROOT" && tar -czf "$TARBALL" Harness )

# --- Step 4: upload the artifact + merge the manifest ---
GCS_PATH="${GCS_PATH:-harness/desktop/${VER}/Harness-linux-x64.tar.gz}"
URL="${GCS_PUBLIC_BASE_URL%/}/${GCS_PATH#/}"
SHA="$(sha256sum "$TARBALL" | awk '{print $1}')"
SIZE="$(wc -c < "$TARBALL" | tr -d ' ')"

echo ">> uploading release $VER ($SIZE bytes, sha256=$SHA)"
echo "   dest: gs://${GCS_BUCKET}/${GCS_PATH}"
gsutil -h "Cache-Control:no-cache, no-store, must-revalidate" cp "$TARBALL" "gs://${GCS_BUCKET}/${GCS_PATH}"

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
echo ">> published desktop app (linux-x64) $VER"
echo "   url:      $URL"
echo "   sha256:   $SHA"
echo "   manifest: ${GCS_PUBLIC_BASE_URL%/}/${METADATA_PATH#/}"
echo "   Running Linux apps poll this on their own schedule (DesktopUpdater, every few hours + on launch)."
