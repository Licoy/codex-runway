#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-$(uname -m)}"
if [[ "${1:-}" == "--arch" ]]; then
  ARCH="${2:-}"
fi

case "$ARCH" in
  arm64|x86_64) ;;
  *)
    printf 'Unsupported ARCH: %s\n' "$ARCH" >&2
    printf 'Usage: ARCH=arm64|x86_64 %s or %s --arch arm64|x86_64\n' "$0" "$0" >&2
    exit 2
    ;;
esac

TRIPLE="${ARCH}-apple-macosx12.0"
DIST="$ROOT/dist"
APP="$DIST/CodexRunway.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
ZIP="$DIST/CodexRunway-macos-${ARCH}.zip"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

swift build -c release --package-path "$ROOT" --triple "$TRIPLE"
BIN_DIR="$(swift build -c release --package-path "$ROOT" --triple "$TRIPLE" --show-bin-path)"
cp "$BIN_DIR/CodexRunway" "$MACOS/CodexRunway"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.svg" "$RESOURCES/AppIcon.svg"
cp "$ROOT/Resources/AppIcon.png" "$RESOURCES/AppIcon.png"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${SPARKLE_PUBLIC_KEY}" "$CONTENTS/Info.plist"
fi
if [[ -d "$BIN_DIR/Sparkle.framework" ]]; then
  /usr/bin/ditto "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/CodexRunway" 2>/dev/null || true
fi

if command -v codesign >/dev/null 2>&1; then
  if [[ -d "$FRAMEWORKS/Sparkle.framework" ]]; then
    codesign --force --sign - "$FRAMEWORKS/Sparkle.framework" >/dev/null
  fi
  codesign --force --deep --sign - "$APP" >/dev/null
fi

mkdir -p "$DIST"
rm -f "$ZIP"
(cd "$DIST" && /usr/bin/ditto -c -k --keepParent "CodexRunway.app" "$(basename "$ZIP")")
printf '%s\n' "$ZIP"
