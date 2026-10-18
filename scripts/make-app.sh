#!/bin/bash
# Release .app paketi üretir. Varsayılan: ad-hoc imza (yalnızca bu Mac'te çalışır).
# Dağıtım için: SIGN_ID="Developer ID Application: Ad Soyad (TEAMID)" scripts/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="Breezy"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
SIGN_ID="${SIGN_ID:--}"

swift build -c release -q --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/CleanerApp"
APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/CleanerApp"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>CleanerApp</string>
  <key>CFBundleIdentifier</key><string>com.sercancelenk.breezy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST
codesign --force --options runtime --sign "$SIGN_ID" "$APP"
echo "$APP"
echo "Notarization (Developer ID ile): ditto -c -k --keepParent \"$APP\" build/$APP_NAME.zip && xcrun notarytool submit build/$APP_NAME.zip --keychain-profile <profil> --wait && xcrun stapler staple \"$APP\""
