#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Одноразовая настройка: сохраняет Apple credentials в Keychain.
# Запускать один раз перед первым release.sh.
# ─────────────────────────────────────────────────────────────────────────────

TEAM_ID="FX5AFVDXGK"
PROFILE_NAME="SMC-notarize"   # произвольное имя профиля в Keychain

echo "══════════════════════════════════════════════"
echo "  Notarization Setup"
echo "══════════════════════════════════════════════"
echo ""
echo "Нужно:"
echo "  1. Apple ID (email аккаунта разработчика)"
echo "  2. App-specific password — создай на:"
echo "     https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
echo ""
echo "Team ID: $TEAM_ID  (уже вписан)"
echo ""

read -r -p "Apple ID (email): " APPLE_ID

echo ""
echo "App-specific password (вводится скрыто):"
xcrun notarytool store-credentials "$PROFILE_NAME" \
  --apple-id "$APPLE_ID" \
  --team-id  "$TEAM_ID"

echo ""
echo "✓ Credentials сохранены в Keychain под именем: $PROFILE_NAME"
echo "  Теперь можно запускать: ./release.sh"
