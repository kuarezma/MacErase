#!/bin/zsh
# Builds build/MacErase.app (release, ad-hoc signed). Usage: [APP_VERSION=1.2.0 APP_BUILD=7] Scripts/build_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)/MacErase
APP=build/MacErase.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacErase"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
ICONSET=build/AppIcon.iconset
swift Scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
[ -s "$APP/Contents/Resources/AppIcon.icns" ] || { echo "icon generation failed" >&2; exit 1; }
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MacErase</string>
<key>CFBundleDisplayName</key><string>MacErase</string>
<key>CFBundleDevelopmentRegion</key><string>tr</string>
<key>CFBundleLocalizations</key><array><string>tr</string><string>en</string></array>
<key>CFBundleIdentifier</key><string>local.macerase.app</string>
<key>CFBundleExecutable</key><string>MacErase</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${APP_VERSION:-1.0}</string>
<key>CFBundleVersion</key><string>${APP_BUILD:-1}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --deep -s - "$APP"
echo "Built $APP"
