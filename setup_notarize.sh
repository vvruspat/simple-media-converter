#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# One-time setup: stores Apple credentials in Keychain.
# Run once before the first release.sh invocation.
# ─────────────────────────────────────────────────────────────────────────────

TEAM_ID="3WKK5AGY66"
PROFILE_NAME="SMC-notarize"   # arbitrary keychain profile name

echo "══════════════════════════════════════════════"
echo "  Notarization Setup"
echo "══════════════════════════════════════════════"
echo ""
echo "You will need:"
echo "  1. Apple ID (developer account email)"
echo "  2. App-specific password — create one at:"
echo "     https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
echo ""
echo "Team ID: $TEAM_ID  (already set)"
echo ""

read -r -p "Apple ID (email): " APPLE_ID

echo ""
echo "App-specific password (hidden input):"
xcrun notarytool store-credentials "$PROFILE_NAME" \
  --apple-id "$APPLE_ID" \
  --team-id  "$TEAM_ID"

echo ""
echo "✓ Credentials saved to Keychain under profile name: $PROFILE_NAME"
echo "  You can now run: ./release.sh"
