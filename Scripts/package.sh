#!/usr/bin/env bash
#
# Build Alexandria as a distributable, ad-hoc-signed .app and wrap it in a .dmg.
#
# Usage:
#   Scripts/package.sh [version]      # build build/Alexandria-<version>.dmg
#   Scripts/package.sh                # version taken from MARKETING_VERSION
#
# The app is ad-hoc signed ("-") — good enough to RUN (Apple Silicon requires at
# least an ad-hoc signature) but NOT notarized, so first-time users must
# right-click → Open (or: xattr -dr com.apple.quarantine /Applications/Alexandria.app).
# See DISTRIBUTING.md.
set -euo pipefail

SCHEME="Alexandria"
APP="Alexandria"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$APP.xcarchive"

# Use the system-selected Xcode when it's a full Xcode (e.g. CI); fall back to
# /Applications/Xcode.app when the local xcode-select points at CommandLineTools.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  if ! xcrun --find xcodebuild >/dev/null 2>&1 || xcode-select -p 2>/dev/null | grep -q CommandLineTools; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

# --- Resolve version (arg wins, else MARKETING_VERSION), strip a leading "v" ---
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(xcodebuild -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')"
fi
VERSION="${VERSION#v}"
: "${VERSION:=0.0.0}"

echo "▸ Packaging $APP $VERSION"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- 1. Archive (Release, ad-hoc signed, no team required) ---
echo "▸ Archiving…"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  archive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  | grep -E "error:|warning: .*error|ARCHIVE (SUCCEEDED|FAILED)" || true

APP_PATH="$ARCHIVE/Products/Applications/$APP.app"
if [ ! -d "$APP_PATH" ]; then
  echo "✗ Archive did not produce $APP.app" >&2
  exit 1
fi

# --- 2. Stage the DMG contents: the app + an /Applications shortcut ---
echo "▸ Building DMG…"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$BUILD_DIR/$APP-$VERSION.dmg"
hdiutil create \
  -volname "$APP $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

rm -rf "$STAGING"
echo "✓ $DMG"

# --- 3. Sparkle appcast: sign the DMG and emit appcast.xml ---------------------
# Sparkle's tools live inside the resolved SPM artifact. The EdDSA private key
# is read from the login Keychain (created once with generate_keys); in CI it
# can instead come from the SPARKLE_ED_PRIVATE_KEY env var (add it as a repo
# secret exported from `generate_keys -x`). If neither is available the DMG is
# still produced — it just won't auto-update, and a warning is printed.
echo "▸ Signing update for Sparkle…"
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*artifacts*sparkle*" -name sign_update -print -quit 2>/dev/null | xargs dirname 2>/dev/null || true)"
if [ -z "$SPARKLE_BIN" ]; then
  echo "⚠ Sparkle tools not found (resolve packages first: xcodebuild -resolvePackageDependencies)."
  echo "  Skipping appcast generation — this build will NOT be offered as an auto-update."
else
  if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    SIG_LINE="$(echo "$SPARKLE_ED_PRIVATE_KEY" | "$SPARKLE_BIN/sign_update" --ed-key-file - "$DMG")"
  else
    SIG_LINE="$("$SPARKLE_BIN/sign_update" "$DMG")"
  fi
  # sign_update prints: sparkle:edSignature="…" length="…"
  PUB_DATE="$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"
  cat > "$BUILD_DIR/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Alexandria</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <link>https://github.com/ahamedzoha/alexandria/releases</link>
      <enclosure
        url="https://github.com/ahamedzoha/alexandria/releases/download/v$VERSION/$APP-$VERSION.dmg"
        $SIG_LINE
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST
  echo "✓ $BUILD_DIR/appcast.xml"
  echo "  Upload BOTH the DMG and appcast.xml as assets of release v$VERSION."
fi
