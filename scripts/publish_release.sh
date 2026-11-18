#!/usr/bin/env bash
# Publish an unsigned IPA to the public SideStore source
# (akriv777-png/sanya-releases) and prepend it to apps.json.
#
# Usage:
#   scripts/publish_release.sh <ipa-path> [localized-description]
#
# Optional env: VERSION, BUILD, RELEASES_REPO, NOTES
# Auth: existing `gh` login or $GITHUB_TOKEN. No secrets are written
# to the release repo.

set -euo pipefail

usage() { echo "Usage: $0 <ipa-path> [localized-description]" >&2; exit 1; }

IPA=${1:-}
[[ -n "$IPA" && -f "$IPA" ]] || usage
IPA=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$IPA")

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
IOS_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
RELEASES_REPO=${RELEASES_REPO:-akriv777-png/sanya-releases}

if [[ -z "${VERSION:-}" || -z "${BUILD:-}" ]]; then
  VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' "$IOS_ROOT/project.yml")
  BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' "$IOS_ROOT/project.yml")
fi

if [[ -z "${VERSION:-}" || -z "${BUILD:-}" ]]; then
  echo "Could not determine VERSION/BUILD from project.yml" >&2
  exit 1
fi

if [[ $# -ge 2 ]]; then
  NOTES=$2
else
  NOTES=${NOTES:-"Сборка ${VERSION} (build ${BUILD})."}
fi

TAG="v${VERSION}-${BUILD}"
ASSET="Sanya-v${VERSION}-${BUILD}-unsigned.ipa"
SIZE=$(stat -c%s "$IPA")
DATE=$(python3 -c "from datetime import datetime; print(datetime.now().astimezone().isoformat(timespec='seconds'))")
DOWNLOAD_URL="https://github.com/${RELEASES_REPO}/releases/download/${TAG}/${ASSET}"
SOURCE_URL="https://raw.githubusercontent.com/${RELEASES_REPO}/main/apps.json"

if ! command -v gh >/dev/null; then
  echo "gh is required" >&2
  exit 1
fi

if gh release view "$TAG" --repo "$RELEASES_REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists in $RELEASES_REPO" >&2
  exit 1
fi

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

cp "$IPA" "$WORKDIR/$ASSET"

echo "Creating $RELEASES_REPO release $TAG ($SIZE bytes)"
gh release create "$TAG" "$WORKDIR/$ASSET" \
  --repo "$RELEASES_REPO" \
  --title "Саня v${VERSION} (build ${BUILD})" \
  --notes "$NOTES"

SRC_DIR="$WORKDIR/src"
gh repo clone "$RELEASES_REPO" "$SRC_DIR" -- --depth 1

export PUBLISH_SRC="$SRC_DIR"
export PUBLISH_VERSION="$VERSION"
export PUBLISH_BUILD="$BUILD"
export PUBLISH_DATE="$DATE"
export PUBLISH_NOTES="$NOTES"
export PUBLISH_URL="$DOWNLOAD_URL"
export PUBLISH_SIZE="$SIZE"

python3 - <<'PY'
import json, os, sys, pathlib

path = pathlib.Path(os.environ["PUBLISH_SRC"]) / "apps.json"
data = json.loads(path.read_text(encoding="utf-8"))
entry = {
    "version": os.environ["PUBLISH_VERSION"],
    "buildVersion": os.environ["PUBLISH_BUILD"],
    "date": os.environ["PUBLISH_DATE"],
    "localizedDescription": os.environ["PUBLISH_NOTES"],
    "downloadURL": os.environ["PUBLISH_URL"],
    "size": int(os.environ["PUBLISH_SIZE"]),
    "minOSVersion": "17.0",
}
apps = data.setdefault("apps", [])
app = next((a for a in apps if a.get("bundleIdentifier") == "com.nezich.sanya"), None)
if app is None:
    sys.exit("apps.json has no app with bundleIdentifier com.nezich.sanya")
versions = app.setdefault("versions", [])
if (
    versions
    and versions[0].get("version") == entry["version"]
    and str(versions[0].get("buildVersion")) == str(entry["buildVersion"])
):
    versions[0] = entry
else:
    versions.insert(0, entry)
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("apps.json latest:", entry["version"], entry["buildVersion"], entry["downloadURL"])
PY

git -C "$SRC_DIR" config user.name "akriv777-png"
git -C "$SRC_DIR" config user.email "akriv777-png@users.noreply.github.com"
git -C "$SRC_DIR" add apps.json
git -C "$SRC_DIR" diff --cached --quiet && { echo "apps.json unchanged"; exit 0; }
git -C "$SRC_DIR" commit -m "apps.json: add ${TAG}"
git -C "$SRC_DIR" push origin HEAD

echo
echo "Source URL: $SOURCE_URL"
echo "IPA URL:    $DOWNLOAD_URL"
echo "Release:    https://github.com/${RELEASES_REPO}/releases/tag/${TAG}"
