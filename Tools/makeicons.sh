#!/bin/bash
#
# Regenerates the iOS/macOS asset catalog (Assets.xcassets/AppIcon.appiconset)
# from the master icon. Run after changing Resources/AppIcon.png:
#
#     ./Tools/makeicons.sh
#
# (The macOS .icns for the SwiftPM app is built separately by make_app.sh, which
#  also reads Resources/AppIcon.png.)

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-Resources/AppIcon.png}"
OUT="Resources/Assets.xcassets/AppIcon.appiconset"
[ -f "$SRC" ] || { echo "missing source image: $SRC"; exit 1; }

mkdir -p "$OUT"
for s in 16 32 64 128 256 512 1024; do
  sips -z "$s" "$s" "$SRC" --out "$OUT/icon_${s}.png" >/dev/null
done

# iOS uses a single 1024 image (Xcode auto-scales); macOS needs the full set.
cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon_1024.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

cat > "Resources/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON

echo "Generated $OUT"
