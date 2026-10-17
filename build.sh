#!/bin/bash
# Builds "PatchCache.app" from main.swift + "PatchCache.html" in this folder.
# Run it again any time you get a new "PatchCache.html" — your data is stored separately and stays put.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PatchCache"
APP="build/$APP_NAME.app"
HTML="PatchCache.html"

echo ""
echo "== PatchCache: building the Mac app =="

# 1. Apple's Command Line Tools (free) provide the Swift compiler.
if ! command -v swiftc >/dev/null 2>&1 || ! swiftc --version >/dev/null 2>&1; then
  echo ""
  echo "Apple's Command Line Tools need to be installed first."
  echo "A window should pop up — click Install, wait for it to finish, then run this script again."
  xcode-select --install 2>/dev/null || true
  exit 1
fi

if [ ! -f "$HTML" ]; then
  echo ""
  echo "Couldn't find \"$HTML\" in this folder. Put the latest copy next to build.sh and run again."
  exit 1
fi

# 2. Compile
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "Compiling (this can take a minute the first time)…"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos11.0" \
  main.swift -o "$APP/Contents/MacOS/PatchCache" \
  -framework Cocoa -framework WebKit

# 3. Page + icon
cp -X "$HTML" "$APP/Contents/Resources/index.html"
if [ -d AppIcon.iconset ]; then
  iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || echo "(icon skipped)"
fi

# 4. App info
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PatchCache</string>
  <key>CFBundleDisplayName</key><string>PatchCache</string>
  <key>CFBundleIdentifier</key><string>local.jdub.patchcache</string>
  <key>CFBundleExecutable</key><string>PatchCache</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# 5. Sign it for this Mac only (free "ad-hoc" signature) and clear download flags
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "(signing skipped)"

echo ""
echo "Done!  →  $(pwd)/$APP"
echo "Drag it into your Applications folder (replace the old one if asked), then open it."
echo "Your data lives in ~/Library/Application Support/PatchCache/ and isn't touched by rebuilding."
open -R "$APP"
