#!/bin/sh
# make-app.sh — release packaging for MacPorts
#
# Builds per-arch release binaries, lipo's them into a universal binary,
# assembles dist/<APP_NAME>.app (ad-hoc signed), and produces the versioned
# release artifacts in one run:
#
#   dist/MacPorts.app              (local, unversioned — used by build.sh)
#   dist/MacPorts-v<VERSION>.zip
#   dist/MacPorts-v<VERSION>.dmg
#
# Naming: everything below is derived from APP_NAME. To rename the app,
# change APP_NAME in ONE place. SPM_TARGET is the Swift package target that
# produces the release binaries (Package.swift) — it may differ from
# APP_NAME and does not affect the distributed bundle names.
#
# Prereqs: swift (Command Line Tools), lipo, sips, iconutil, codesign,
#          plutil, ditto, hdiutil, shasum.
#
# Usage:
#   sh Scripts/make-app.sh                 # default version 0.1.0
#   sh Scripts/make-app.sh 0.2.0          # explicit version argument
#   VERSION=0.2.0 sh Scripts/make-app.sh  # env override
#   ARCHS=x86_64 sh Scripts/make-app.sh   # restrict architectures (test/CI)
#
# Notes:
#  - Architectures are built SEPARATELY and combined with lipo, because a
#    single multi-arch `swift build --arch arm64 --arch x86_64` needs the
#    XCBuild backend (full Xcode). Per-arch builds cross-compile fine with
#    just Command Line Tools.
#  - Signing is ad-hoc ("local use"). For Gatekeeper-free distribution,
#    sign with a Developer ID certificate + notarize (e.g. in CI).
#  - Icon source: Resources/icon-master.png (square PNG, transparent bg).
#    1024x1024 recommended; smaller masters are upscaled for the @2x slots.
#  - The DMG contains the .app plus an "Applications" symlink for
#    drag-to-install.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- naming (change APP_NAME here to rename the app) ---------------------
APP_NAME="MacPorts"        # bundle / zip / dmg / volname / CFBundle* name
SPM_TARGET="MacPortsUI"    # SPM executable target (built binary name)

# --- version & architecture selection ------------------------------------
if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
    VERSION="$1"
elif [ -n "${VERSION:-}" ]; then
    : # env-provided
else
    VERSION="0.1.0"
fi
case "$VERSION" in
    *[!0-9.]*|"")
        echo "error: version must be dot-separated numbers (got: '$VERSION')" >&2
        exit 1
        ;;
esac
CFBUNDLEVERSION="$(echo "$VERSION" | tr -d '.')"

if [ -n "${ARCHS:-}" ]; then
    ARCH_LIST="$ARCHS"
else
    ARCH_LIST="arm64 x86_64"
fi

MASTER="Resources/icon-master.png"
OUT="dist"
APP="$OUT/${APP_NAME}.app"
ZIP="$OUT/${APP_NAME}-v${VERSION}.zip"
DMG="$OUT/${APP_NAME}-v${VERSION}.dmg"

# Ensure the output dir exists before anything writes into it (lipo's temp
# file, the .app, the iconset). On a clean checkout dist/ is gitignored
# and absent, so without this the first lipo call dies with
# "can't create temporary output file: dist/... (No such file or directory)".
mkdir -p "$OUT"

[ -f "$MASTER" ] || { echo "error: icon master not found: $MASTER" >&2; exit 1; }

# Warn (do not fail) if the master is smaller than 1024.
W="$(sips -g pixelWidth "$MASTER" | awk '/pixelWidth/ {print $2}')"
if [ "${W:-0}" -lt 1024 ]; then
    echo "note: icon master is ${W}px; @2x slots will be upscaled (recommend 1024px)"
fi

# --- per-arch release builds -> universal binary -------------------------
echo "==> building release binary for: $ARCH_LIST"
BINS=""
for A in $ARCH_LIST; do
    echo "    swift build -c release --arch $A"
    swift build -c release --arch "$A"
    B="$(swift build -c release --arch "$A" --show-bin-path | tail -1)"
    [ -f "$B/$SPM_TARGET" ] || { echo "error: $A build produced no binary" >&2; exit 1; }
    BINS="$BINS $B/$SPM_TARGET"
done

UNIBIN="$OUT/${APP_NAME}.universal.tmp"
lipo -create $BINS -o "$UNIBIN"
echo "    universal: $(lipo -archs "$UNIBIN")"

# --- AppIcon.icns ---------------------------------------------------------
echo "==> building AppIcon.icns"
rm -rf "$OUT/icon.iconset"
mkdir -p "$OUT/icon.iconset" "$OUT"
ICO="$OUT/icon.iconset"
# Official iconset slot names (underscore form; required by iconutil).
sips -z 16   16   "$MASTER" --out "$ICO/icon_16x16.png"      >/dev/null
sips -z 32   32   "$MASTER" --out "$ICO/icon_16x16@2x.png"  >/dev/null
sips -z 32   32   "$MASTER" --out "$ICO/icon_32x32.png"     >/dev/null
sips -z 64   64   "$MASTER" --out "$ICO/icon_32x32@2x.png"  >/dev/null
sips -z 128  128  "$MASTER" --out "$ICO/icon_128x128.png"   >/dev/null
sips -z 256  256  "$MASTER" --out "$ICO/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$MASTER" --out "$ICO/icon_256x256.png"   >/dev/null
sips -z 512  512  "$MASTER" --out "$ICO/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$MASTER" --out "$ICO/icon_512x512.png"   >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICO/icon_512x512@2x.png" >/dev/null
ICNS="$OUT/AppIcon.icns"
rm -f "$ICNS"
iconutil -c icns "$ICO" -o "$ICNS"

# --- assemble the .app ----------------------------------------------------
echo "==> assembling $APP (v$VERSION)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$UNIBIN" "$APP/Contents/MacOS/${APP_NAME}"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>local.macportsui.reference</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$CFBUNDLEVERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
rm -f "$UNIBIN"

# --- ad-hoc codesign (bundle) --------------------------------------------
echo "==> ad-hoc codesign"
codesign --force --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

# --- release artifacts: .zip + .dmg ---------------------------------------
echo "==> packaging $ZIP"
rm -f "$ZIP"
( cd "$OUT" && ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}-v${VERSION}.zip" )

echo "==> packaging $DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" 2>/dev/null || true' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create \
    -volname "${APP_NAME} v${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

# --- summary ----------------------------------------------------------------
echo
echo "==> checksums (attach alongside the release)"
shasum -a 256 "$ZIP" "$DMG"

echo
echo "Done (v${VERSION}):"
echo "  $APP   (local, run: open $APP)"
echo "  $ZIP"
echo "  $DMG"
