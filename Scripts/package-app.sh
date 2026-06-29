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
TAR_GZ="$DIST/CodexRunway-macos-${ARCH}.app.tar.gz"
DMG="$DIST/CodexRunway-macos-${ARCH}.dmg"
DMG_ROOT="$DIST/dmg-${ARCH}"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

swift build -c release --package-path "$ROOT" --triple "$TRIPLE"
BIN_DIR="$(swift build -c release --package-path "$ROOT" --triple "$TRIPLE" --show-bin-path)"
cp "$BIN_DIR/CodexRunway" "$MACOS/CodexRunway"
if [[ -n "${EXPECTED_MACOS_SDK_MAJOR:-}" ]]; then
  SDK="$(otool -l "$MACOS/CodexRunway" | awk '$1 == "sdk" { print $2; exit }')"
  case "$SDK" in
    "${EXPECTED_MACOS_SDK_MAJOR}".*) ;;
    *)
      printf 'Expected macOS SDK %s.x, got %s\n' "$EXPECTED_MACOS_SDK_MAJOR" "${SDK:-unknown}" >&2
      exit 1
      ;;
  esac
fi
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
  ENTITLEMENTS="$(mktemp)"
  trap 'rm -f "$ENTITLEMENTS"' EXIT
  cat >"$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>
PLIST
  if [[ -d "$FRAMEWORKS/Sparkle.framework" ]]; then
    codesign --force --options runtime --sign - "$FRAMEWORKS/Sparkle.framework" >/dev/null
  fi
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP" >/dev/null
fi

mkdir -p "$DIST"
rm -rf "$DMG_ROOT"
rm -f "$ZIP" "$TAR_GZ" "$DMG"
(cd "$DIST" && /usr/bin/ditto -c -k --keepParent "CodexRunway.app" "$(basename "$ZIP")")
(cd "$DIST" && /usr/bin/tar -czf "$(basename "$TAR_GZ")" "CodexRunway.app")
mkdir -p "$DMG_ROOT"
/usr/bin/ditto "$APP" "$DMG_ROOT/CodexRunway.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "Codex Runway" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMG_ROOT"
printf '%s\n%s\n%s\n' "$ZIP" "$TAR_GZ" "$DMG"
