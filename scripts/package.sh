#!/usr/bin/env bash
# Packages build/Portrero.app (from scripts/build.sh) for download:
#   build/Portrero-<version>.dmg   drag-to-Applications disk image
#   build/Portrero-<version>.zip   the bare app, for Homebrew-style installs
#
# Notarization: when NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD (an app-specific
# password) are set, and the app was signed with a Developer ID, the DMG is notarized and stapled.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Portrero.app"
[[ -d "$APP" ]] || { echo "Build the app first: scripts/build.sh" >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DMG="build/Portrero-$VERSION.dmg"
ZIP="build/Portrero-$VERSION.zip"
rm -f "$DMG" "$ZIP"

notarize() {
    [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]] || return 0
    echo "→ Notarizing $1"
    xcrun notarytool submit "$1" --wait \
        --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD"
    xcrun stapler staple "$1"
}

# Notarize the app itself first so the zip carries a stapled ticket too.
if [[ -n "${NOTARY_APPLE_ID:-}" ]]; then
    ditto -c -k --keepParent "$APP" build/notarize.zip
    notarize build/notarize.zip >/dev/null
    rm build/notarize.zip
    xcrun stapler staple "$APP"
fi

echo "→ Creating $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "→ Creating $DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Portrero" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
fi
notarize "$DMG"

(cd build && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > "Portrero-$VERSION.sha256")
echo "✓ Packaged $DMG and $ZIP"
