#!/bin/bash
#
# Builds Centipede and packages it as a double-clickable Centipede.app bundle
# (release binary + Info.plist + generated icon, ad-hoc code-signed).
#
# Usage:  ./make_app.sh
# Then:   cp -R Centipede.app /Applications/   (or just double-click it)

set -euo pipefail
cd "$(dirname "$0")"

APP="Centipede"
BUNDLE_ID="io.github.sneeper.centipede"
VERSION="1.0"
APPDIR="$APP.app"

# Extra flags for swift build. Normally empty; set SWIFT_BUILD_FLAGS=--disable-sandbox
# only if your shell is itself sandboxed and the build complains about sandbox-exec.
FLAGS="${SWIFT_BUILD_FLAGS:-}"

echo "==> Building release binary..."
swift build -c release $FLAGS
BIN="$(swift build -c release $FLAGS --show-bin-path)/$APP"

echo "==> Assembling $APPDIR ..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
cp "$BIN" "$APPDIR/Contents/MacOS/$APP"

echo "==> Generating icon..."
WORK="$(mktemp -d)"
ICONSET="$WORK/$APP.iconset"
MASTER="Resources/AppIcon.png"      # the committed 1024 master image
mkdir -p "$ICONSET"

# Downscale the master into every size iconutil expects.
sip() { sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null; }
sip 16   icon_16x16.png
sip 32   icon_16x16@2x.png
sip 32   icon_32x32.png
sip 64   icon_32x32@2x.png
sip 128  icon_128x128.png
sip 256  icon_128x128@2x.png
sip 256  icon_256x256.png
sip 512  icon_256x256@2x.png
sip 512  icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APPDIR/Contents/Resources/$APP.icns"

echo "==> Writing Info.plist..."
cat > "$APPDIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>$APP</string>
    <key>CFBundleDisplayName</key>         <string>$APP</string>
    <key>CFBundleExecutable</key>          <string>$APP</string>
    <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>            <string>$APP</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>$VERSION</string>
    <key>CFBundleVersion</key>             <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>      <string>13.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSPrincipalClass</key>            <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>   <string>public.app-category.games</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APPDIR/Contents/PkgInfo"

echo "==> Ad-hoc code-signing..."
codesign --force --deep --sign - "$APPDIR"

rm -rf "$WORK"
echo "==> Done: $(pwd)/$APPDIR"
echo "    Run it:   open $APPDIR"
echo "    Install:  cp -R $APPDIR /Applications/"
