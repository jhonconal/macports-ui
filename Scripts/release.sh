#!/bin/sh
# release.sh — one-shot version release for MacPorts
#
# Pipeline:
#   1. Build universal (arm64 + x86_64) release artifacts via make-app.sh
#      (universal .app + versioned .zip/.dmg into dist/)
#   2. Archive the build into release/ under the UNIFORM name
#      MacPorts-latest.{zip,dmg,sha256,meta.json} — every release simply
#      overwrites that one set, so release/ always holds ONLY the latest
#      build (git history keeps every previous version).
#   3. Create/update git tag v<VERSION>
#   4. If gh CLI is available and --no-gh is not set: create a GitHub
#      Release (v<VERSION>) and upload the artifacts. GitHub's Releases
#      page then always shows the latest release on top and lists every
#      older version for browsing/downloading.
#
# Usage:
#   sh Scripts/release.sh 0.2.0                # full pipeline + GitHub Release
#   sh Scripts/release.sh 0.2.0 --no-gh        # build + tag only, no gh
#   VERSION=0.2.0 sh Scripts/release.sh --no-gh
#
# Notes:
#   - Version must be X.Y.Z (validated by make-app.sh).
#   - Run this on a clean tree; it `git add release/`-stages artifacts.
#   - Commit/tag is NOT auto-pushed; review then:
#       git push origin main && git push origin v0.2.0
#     (or re-run with gh authenticated; gh release create auto-pushes the tag
#      only when the tag exists locally and the remote is set — for safety we
#      leave pushing to you.)

set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

# --- version & flags --------------------------------------------------------
NO_GH=0
if [ "${1:-}" = "--no-gh" ]; then
    NO_GH=1
    shift
fi
if [ -n "${1:-}" ]; then
    VERSION="$1"
elif [ -n "${VERSION:-}" ]; then
    :
else
    VERSION="0.1.0"
fi

case "$VERSION" in
    *[^0-9.]*|'') echo "error: version must be X.Y.Z (got: '$VERSION')" >&2; exit 1 ;;
esac
TAG="v${VERSION}"

echo "== [1/4] building universal release artifacts (arm64 + x86_64) =="
sh Scripts/make-app.sh "$VERSION"

echo "== [2/4] archiving into release/ as MacPorts-latest.* =="
mkdir -p release
# Uniform naming: release/ always carries exactly one rolling set.
rm -f release/MacPorts-v* 2>/dev/null || true
cp -f "dist/MacPorts-v${VERSION}.zip" "release/MacPorts-latest.zip"
cp -f "dist/MacPorts-v${VERSION}.dmg" "release/MacPorts-latest.dmg"
shasum -a 256 "release/MacPorts-latest.zip" "release/MacPorts-latest.dmg" \
    > "release/MacPorts-latest.sha256"
# Which version the rolling set currently is (so `git clone` users can tell)
cat > "release/MacPorts-latest.meta.json" <<EOF
{
  "name": "MacPorts",
  "channel": "latest",
  "version": "${VERSION}",
  "tag": "${TAG}",
  "architectures": ["arm64", "x86_64"],
  "platform": "macOS 13+",
  "date": "$(date +%Y-%m-%d)"
}
EOF
echo "    $(ls -1 release/MacPorts-latest.* | sed 's/^/    /')"

echo "== [3/4] git tag ${TAG} =="
if git rev-parse --git-dir >/dev/null 2>&1; then
    git add release/
    # Refresh the existing tag if re-releasing the same version (rare)
    git tag -f "$TAG"
    echo "    tagged ${TAG} (commit not pushed)"
else
    echo "    (not a git repository; skipped)"
fi

if [ "$NO_GH" -eq 1 ]; then
    echo "== [4/4] gh release skipped (--no-gh) =="
    echo "Next: review, then  git push origin main && git push origin ${TAG}"
    echo "        and create the GitHub Release manually if desired."
    exit 0
fi

echo "== [4/4] GitHub release =="
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    # Only delete + recreate if a release for this tag already exists
    if gh release view "$TAG" >/dev/null 2>&1; then
        gh release delete "$TAG" --cleanup-tag --yes
    fi
    gh release create "$TAG" \
        "dist/MacPorts-v${VERSION}.zip" \
        "dist/MacPorts-v${VERSION}.dmg" \
        --title "MacPorts ${VERSION}" \
        --notes "Universal macOS build (arm64 + x86_64), ad-hoc signed.
Requirements: macOS 13+, MacPorts installed. First launch may be blocked
by Gatekeeper (not notarized) — see the repository README."
    echo "    GitHub Release ${TAG} created. Users can now download the latest"
    echo "    version and browse older releases at: <repo>/releases"
else
    echo "    gh CLI not available (or not authenticated); create the Release manually:"
    echo "      git tag -f ${TAG} && git push origin main ${TAG}"
    echo "      then upload dist/MacPorts-v${VERSION}.{zip,dmg} at <repo>/releases/new"
fi

echo "done."
