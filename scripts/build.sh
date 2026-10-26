#!/usr/bin/env bash
# Builds Portrero.app into ./build.
#   scripts/build.sh                    release build for this Mac
#   scripts/build.sh --debug            debug build (adds the scripts/debug.swift hooks)
#   scripts/build.sh --universal        release build for both Apple silicon and Intel
#   scripts/build.sh --version 1.2.0    stamp a version into Info.plist
#   scripts/build.sh --install          copy to /Applications and launch
#
# Signing: ad-hoc by default, which is enough to run locally. Set CODESIGN_IDENTITY to a
# "Developer ID Application: …" identity to sign for distribution (hardened runtime + timestamp).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CONFIG=release
INSTALL=false
VERSION=""
UNIVERSAL=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG=debug ;;
        --install) INSTALL=true ;;
        --universal) UNIVERSAL=true ;;
        --version) VERSION="${2:?--version needs a value}"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

APP="$ROOT/build/Portrero.app"
ICON="$ROOT/Support/AppIcon.icns"

if [[ ! -f "$ICON" ]]; then
    echo "→ Rendering app icon"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    swift scripts/make-icon.swift "$ICONSET" >/dev/null
    iconutil -c icns "$ICONSET" -o "$ICON"
fi

if $UNIVERSAL; then
    # One build per architecture, merged with lipo (works without Xcode's build system).
    SLICES=()
    for ARCH in arm64 x86_64; do
        echo "→ Compiling ($CONFIG, $ARCH)"
        TRIPLE="$ARCH-apple-macosx14.0"
        swift build -c "$CONFIG" --triple "$TRIPLE"
        SLICES+=("$(swift build -c "$CONFIG" --triple "$TRIPLE" --show-bin-path)/Portrero")
    done
    BIN="$ROOT/build/Portrero-universal"
    mkdir -p build
    lipo -create "${SLICES[@]}" -output "$BIN"
else
    echo "→ Compiling ($CONFIG)"
    swift build -c "$CONFIG"
    BIN="$(swift build -c "$CONFIG" --show-bin-path)/Portrero"
fi

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Portrero"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "$VERSION" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
    # Build number: commit count, so every release is higher than the last.
    BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "→ Signing as $CODESIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
    codesign --force --sign - --timestamp=none "$APP" >/dev/null
fi

if $INSTALL; then
    DEST="/Applications/Portrero.app"
    echo "→ Installing to $DEST"
    pkill -x Portrero 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    APP="$DEST"
fi

# Make sure Launch Services knows about this copy (needed to be offered as default browser).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "✓ Built $APP"
if $INSTALL; then open "$APP"; fi
