#!/bin/bash
set -eo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
DEVELOPER_ID="Developer ID Application: Aleksandr  Kolesov (3WKK5AGY66)"
NOTARIZE_PROFILE="SMC-notarize"   # keychain profile name from setup_notarize.sh
APP_NAME="SimpleMediaConverter"
BUNDLE="$APP_NAME.app"
VERSION="2.1"

# ─── Preflight checks ─────────────────────────────────────────────────────────
echo "▸ Checking environment..."

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo ""
  echo "❌  Developer ID Application certificate not found in Keychain."
  echo ""
  echo "   How to get one:"
  echo "   1. Go to: https://developer.apple.com/account/resources/certificates/add"
  echo "   2. Choose 'Developer ID Application'"
  echo "   3. Download the .cer and double-click to add it to Keychain"
  echo "   4. Run this script again"
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" &>/dev/null; then
  echo ""
  echo "❌  Notarization credentials not configured."
  echo "   Run: ./setup_notarize.sh"
  exit 1
fi

echo "   ✓ Developer ID certificate found"
echo "   ✓ Notarization profile '$NOTARIZE_PROFILE' found"

# ─── 1. Build ────────────────────────────────────────────────────────────────
echo ""
./build.sh

# ─── 2. Sign with Developer ID + Hardened Runtime ────────────────────────────
echo "▸ Signing with Developer ID..."

# 2a. All dylibs (recursive, real files only — not symlinks)
while IFS= read -r -d '' dylib; do
  echo "   signing: $(basename "$dylib")"
  codesign --force \
    --sign "$DEVELOPER_ID" \
    --timestamp \
    "$dylib"
done < <(find "$BUNDLE/Contents/Frameworks/" -name "*.dylib" -not -type l -print0)

# 2b. ffmpeg binary — with hardened runtime
codesign --force \
  --options runtime \
  --entitlements entitlements.plist \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "$BUNDLE/Contents/MacOS/ffmpeg"

# 2c. Main binary
codesign --force \
  --options runtime \
  --entitlements entitlements.plist \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "$BUNDLE/Contents/MacOS/$APP_NAME"

# 2d. Whole bundle (no --deep, components already signed)
codesign --force \
  --options runtime \
  --entitlements entitlements.plist \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "$BUNDLE"

# Verify
codesign --verify --deep --strict --verbose=2 "$BUNDLE" 2>&1 | tail -3
echo "   ✓ Signature valid"

# ─── 3. Notarize ─────────────────────────────────────────────────────────────
echo "▸ Creating zip for notarization..."
ZIP="$APP_NAME-$VERSION-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

echo "▸ Submitting to Apple Notary Service (1–5 min)..."
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$NOTARIZE_PROFILE" \
  --wait \
  --timeout 10m

echo "▸ Stapling ticket..."
xcrun stapler staple "$BUNDLE"
xcrun stapler validate "$BUNDLE"
echo "   ✓ Notarization complete"

# ─── 4. Create DMG ───────────────────────────────────────────────────────────
echo "▸ Creating DMG..."
DMG="$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

TMP_DIR=$(mktemp -d)
cp -R "$BUNDLE" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$TMP_DIR" \
  -ov -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG" 2>&1 | tail -2

rm -rf "$TMP_DIR" "$ZIP"

# Verify Gatekeeper
spctl --assess --type exec "$BUNDLE" && echo "   ✓ Gatekeeper: OK"

# ─── Done ─────────────────────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "$DMG" | cut -f1)
echo ""
echo "══════════════════════════════════════"
echo "  ✅  $DMG ($DMG_SIZE)"
echo "  Ready for distribution."
echo "  Users can open without any warnings."
echo "══════════════════════════════════════"
open .
