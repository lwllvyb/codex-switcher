#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/multi-codex-limit-viewer.xcodeproj"
SCHEME="${SCHEME:-multi-codex-limit-viewer}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUNDLE_ID="${BUNDLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APP_NAME="${APP_NAME:-Codex Switcher}"
DISPLAY_NAME="${DISPLAY_NAME:-Codex Switcher}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/direct}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData}"
ARCHIVE_PATH="$BUILD_ROOT/$DISPLAY_NAME.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
DMG_ROOT="$BUILD_ROOT/dmg-root"
DMG_PATH="$BUILD_ROOT/${DISPLAY_NAME// /-}.dmg"
EXPORT_OPTIONS_PLIST="$BUILD_ROOT/ExportOptions.plist"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-1}"
ALLOW_UNNOTARIZED="${ALLOW_UNNOTARIZED:-0}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  local value="$2"
  local example="$3"

  if [[ -n "$value" ]]; then
    return
  fi

  echo "Missing required environment variable: $name" >&2
  echo "Example: $example" >&2
  exit 1
}

resolve_dmg_sign_identity() {
  if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
    return
  fi

  DMG_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Developer ID Application/ { print $2; exit }'
  )"

  if [[ -z "$DMG_SIGN_IDENTITY" ]]; then
    echo "Could not find a Developer ID Application certificate in the keychain." >&2
    echo "Set DMG_SIGN_IDENTITY to the full certificate name and run again." >&2
    exit 1
  fi
}

require_command xcodebuild
require_command hdiutil
require_command codesign
require_command security
require_command spctl

require_env \
  BUNDLE_ID \
  "$BUNDLE_ID" \
  'BUNDLE_ID="com.example.codex.switcher" TEAM_ID="ABCDE12345" NOTARY_PROFILE="notary-profile" ./scripts/package_direct_dmg.sh'
require_env \
  TEAM_ID \
  "$TEAM_ID" \
  'BUNDLE_ID="com.example.codex.switcher" TEAM_ID="ABCDE12345" NOTARY_PROFILE="notary-profile" ./scripts/package_direct_dmg.sh'

XCODE_PROVISIONING_FLAGS=()
if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
  XCODE_PROVISIONING_FLAGS+=(-allowProvisioningUpdates)
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

cat >"$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
</dict>
</plist>
PLIST

echo "==> Archiving app"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  "${XCODE_PROVISIONING_FLAGS[@]}"

echo "==> Exporting Developer ID app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  "${XCODE_PROVISIONING_FLAGS[@]}"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle was not found: $APP_PATH" >&2
  exit 1
fi

resolve_dmg_sign_identity

echo "==> Verifying exported app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
# A Developer ID app exported here has not been notarized yet, so Gatekeeper
# will reject it until the final distribution container is notarized.

echo "==> Creating DMG staging folder"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

echo "==> Building DMG"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Signing DMG with: $DMG_SIGN_IDENTITY"
codesign --force --sign "$DMG_SIGN_IDENTITY" --timestamp "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  require_command xcrun

  echo "==> Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "==> Stapling notarization ticket to DMG"
  xcrun stapler staple "$DMG_PATH"

  echo "==> Validating stapled DMG"
  xcrun stapler validate "$DMG_PATH"
else
  if [[ "$ALLOW_UNNOTARIZED" != "1" ]]; then
    cat <<EOF >&2
==> Notarization is required for release DMGs, but NOTARY_PROFILE is empty.
This DMG will be blocked by Gatekeeper and may show as "已损坏" on user machines.
Create a profile first:
  xcrun notarytool store-credentials "notary-profile" --apple-id "<APPLE_ID>" --team-id "$TEAM_ID" --password "<APP_SPECIFIC_PASSWORD>"
Then rerun:
  BUNDLE_ID="$BUNDLE_ID" TEAM_ID="$TEAM_ID" NOTARY_PROFILE=notary-profile ./scripts/package_direct_dmg.sh
If you only want a local test build, run:
  BUNDLE_ID="$BUNDLE_ID" TEAM_ID="$TEAM_ID" ALLOW_UNNOTARIZED=1 ./scripts/package_direct_dmg.sh
EOF
    exit 1
  fi

  cat <<EOF
==> Skipped notarization because NOTARY_PROFILE is empty.
This local-only DMG will be blocked by Gatekeeper and may show as "已损坏".
Do not send it to users.
EOF
fi

echo "==> Verifying DMG"
# Disk image assessment needs an explicit context on the build machine,
# otherwise spctl can reject a valid notarized DMG with "Insufficient Context".
if spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"; then
  :
elif [[ -n "$NOTARY_PROFILE" ]]; then
  echo "Gatekeeper verification failed for notarized DMG." >&2
  exit 1
else
  echo "Gatekeeper rejected the DMG because notarization was skipped." >&2
fi

cat <<EOF

Done.
App bundle: $APP_PATH
DMG: $DMG_PATH
EOF
