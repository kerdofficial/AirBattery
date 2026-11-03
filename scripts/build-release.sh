#!/bin/bash
# Archives AirBattery, exports it with Developer ID signing, notarizes and staples it.
# Requires: ASC_KEY_PATH (App Store Connect API .p8), ASC_KEY_ID, ASC_ISSUER_ID.
# Output: build/AirBattery.app and build/AirBattery-<version>.zip
set -euo pipefail

: "${ASC_KEY_PATH:?set ASC_KEY_PATH}"
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/AirBattery.xcarchive"
EXPORT="$BUILD/export"
TEAM_ID="7LA5DMHTL9"

rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p "$BUILD"

xcodebuild -project "$ROOT/AirBattery.xcodeproj" -scheme AirBattery -configuration Release \
    -archivePath "$ARCHIVE" -derivedDataPath "$BUILD/DerivedData" archive

cat > "$BUILD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" \
    -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" -allowProvisioningUpdates

APP="$EXPORT/AirBattery.app"
IDENTITY="Developer ID Application: Daniel Kerekes ($TEAM_ID)"

# The bundled libimobiledevice tools are plain resources, so export does not sign them.
find "$APP/Contents/Resources/libimobiledevice" -type f \( -name '*.dylib' -o -perm -u+x \) -print0 |
    xargs -0 codesign --force --options runtime --timestamp --sign "$IDENTITY"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    --preserve-metadata=entitlements,requirements "$APP"
codesign --verify --deep --strict "$APP"

CHECKED=0
while IFS= read -r -d '' FILE; do
    file -b "$FILE" | grep -q "Mach-O" || continue
    INFO=$(codesign -dvvv "$FILE" 2>&1) || { echo "error: not signed: $FILE" >&2; exit 1; }
    grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$INFO" || { echo "error: wrong team: $FILE" >&2; exit 1; }
    grep -q "^CodeDirectory.*flags=.*runtime" <<<"$INFO" || { echo "error: hardened runtime missing: $FILE" >&2; exit 1; }
    CHECKED=$((CHECKED + 1))
done < <(find "$APP" -type f -print0)
echo "Verified team and hardened runtime on $CHECKED Mach-O files"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="$BUILD/AirBattery-$VERSION.zip"

ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
xcrun notarytool submit "$BUILD/notarize.zip" --wait \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

rm -rf "$BUILD/AirBattery.app" "$BUILD/notarize.zip"
ditto "$APP" "$BUILD/AirBattery.app"
ditto -c -k --keepParent "$BUILD/AirBattery.app" "$ZIP"
echo "Done: $BUILD/AirBattery.app, $ZIP"
