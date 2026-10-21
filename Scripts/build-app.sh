#!/bin/bash
# Builds "PDF Smasher.app" (universal: Apple silicon + Intel) and a distributable DMG.
#
#   Scripts/build-app.sh                 # ad-hoc signed, for local use / testing
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=my-notary-profile Scripts/build-app.sh   # signed + notarized for public release
#
# NOTARY_PROFILE is a keychain profile created with:
#   xcrun notarytool store-credentials my-notary-profile --apple-id you@example.com --team-id TEAMID

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-$(date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="PDF Smasher"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Generating assets"
if [[ ! -f Resources/AppIcon.icns ]]; then
    swift Scripts/generate-assets.swift
fi

if [[ ! -x Resources/bin/qpdf ]]; then
    echo "▸ Building qpdf"
    Scripts/build-qpdf.sh
fi

echo "▸ Building release binaries"
swift build -c release --arch arm64 --arch x86_64 --product PDFSmasher
swift build -c release --arch arm64 --arch x86_64 --product pdfsmash
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
# SwiftPM records the deployment target as the SDK version, which makes macOS run the app
# in compatibility mode (old-style toolbar). Stamp the real SDK so it gets the current design.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/PDFSmasher" "$BIN/PDFSmasher"
cp "$BIN/pdfsmash" "$APP/Contents/Helpers/pdfsmash"
cp Resources/bin/qpdf "$APP/Contents/Helpers/qpdf"
cp -R Resources/ThirdParty "$APP/Contents/Resources/ThirdParty"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/ProfileIcon.icns "$APP/Contents/Resources/"
cp Resources/Assets/*.png "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "▸ Signing ($SIGN_IDENTITY)"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Helpers/qpdf"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Helpers/pdfsmash"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "▸ Creating DMG"
DMG="$DIST/PDF-Smasher-$VERSION.dmg"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "▸ Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "✓ $APP"
echo "✓ $DMG"
