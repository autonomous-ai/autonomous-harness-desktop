#!/usr/bin/env bash
# Where the internal build of a commit lives — for whoever hands it to a tester, and for
# .github/workflows/internal-build.yml, which asks this same script so the two cannot disagree.
#
# Usage:
#   bash scripts/internal-build-link.sh                  # HEAD: both macOS builds' download links
#   bash scripts/internal-build-link.sh 4f3c2a1          # any commit this checkout knows
#   bash scripts/internal-build-link.sh --object <sha> <intel|apple-silicon>
#                                                        # the GCS object, minus .zip/.dmg (CI)
#
# This repository is PUBLIC, and so is every Actions log and run summary: a link printed there is
# printed for everyone. So the workflow prints none. Each build's path instead carries
# HMAC-SHA256(INTERNAL_BUILD_KEY, "<commit>/<variant>") — whoever holds the key can work out the
# link for any commit, and nobody else can: the bucket refuses anonymous listing, so there is no
# other way to find it. RELEASE.md, "Internal builds".
#
# The key is the repository secret INTERNAL_BUILD_KEY. Give this script the same value, either
#   export INTERNAL_BUILD_KEY=...                        # this shell only, or once, on a Mac:
#   security add-generic-password -U -s harness-internal-build-key -a "$USER" -w
set -euo pipefail
set +x   # the key must never reach a trace

BUCKET="${GCS_BUCKET:-s3-autonomous-upgrade-3}"
ROOT="harness/desktop-internal"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  echo "usage: bash scripts/internal-build-link.sh [commit]" >&2
  echo "       bash scripts/internal-build-link.sh --object <commit> <intel|apple-silicon>" >&2
  exit 1
}

build_key() {
  if [ -n "${INTERNAL_BUILD_KEY:-}" ]; then
    printf '%s' "$INTERNAL_BUILD_KEY"
    return
  fi
  if command -v security >/dev/null 2>&1 &&
    security find-generic-password -s harness-internal-build-key -w 2>/dev/null; then
    return
  fi
  die "no INTERNAL_BUILD_KEY — export it, or keep it in the keychain:
       security add-generic-password -U -s harness-internal-build-key -a \"\$USER\" -w"
}

# A full SHA as it is; anything else resolved by this checkout.
resolve_commit() {
  if [[ "$1" =~ ^[0-9a-f]{40}$ ]]; then
    echo "$1"
    return
  fi
  git rev-parse --verify --quiet "$1^{commit}" || die "not a commit this checkout knows: $1"
}

# The object for one build, without its extension. The file a tester downloads names the commit.
object_for() {  # <commit> <variant>, with KEY set
  local artifact
  case "$2" in
    intel)         artifact="Harness-${1:0:7}-macos" ;;
    apple-silicon) artifact="Harness-${1:0:7}-macos-arm64" ;;
    *) die "the build is intel or apple-silicon, not '$2'" ;;
  esac
  local token
  # Through the environment, never argv: a process list is readable by anything on the machine.
  token="$(HMAC_KEY="$KEY" python3 -c '
import hashlib, hmac, os, sys
print(hmac.new(os.environ["HMAC_KEY"].encode(), sys.argv[1].encode(), hashlib.sha256).hexdigest()[:32])
' "$1/$2")"
  echo "$ROOT/$token/$artifact"
}

command -v python3 >/dev/null 2>&1 || die "python3 not found"

if [ "${1:-}" = --object ]; then
  [ $# -eq 3 ] || usage
  commit="$(resolve_commit "$2")"
  KEY="$(build_key)"
  object_for "$commit" "$3"
  exit 0
fi
[ $# -le 1 ] || usage
case "${1:-}" in -*) usage ;; esac

commit="$(resolve_commit "${1:-HEAD}")"
KEY="$(build_key)"
echo "Internal build of ${commit:0:12} — hand these to testers, never to a public page:"
for variant in apple-silicon intel; do
  object="$(object_for "$commit" "$variant")"
  url="https://storage.googleapis.com/$BUCKET/$object.dmg"
  # 200 once CI has uploaded it, 404 before (measured 2026-09-10) — which says nothing to someone
  # without the name, and the name is the part only the key gives out.
  code="$(curl -s -o /dev/null -I -w '%{http_code}' "$url" || true)"
  if [ "$code" = 200 ]; then state="ready"; else state="not there (HTTP $code) — still building, or never built"; fi
  if [ "$variant" = intel ]; then label="Intel, on Skia (runs on any Mac)"; else label="Apple Silicon, on Impeller"; fi
  echo
  echo "  $label — $state"
  echo "  $url"
  echo "  take it back:  gsutil -m rm -r gs://$BUCKET/${object%/*}"
done
