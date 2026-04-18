#!/bin/bash
set -e

# ─── Config ───────────────────────────────────────────────────────────────────
DEVELOPER_ID="Developer ID Application: Aleksandr Kolesov (FX5AFVDXGK)"
NOTARIZE_PROFILE="SMC-notarize"   # имя профиля из setup_notarize.sh
APP_NAME="SimpleMediaConverter"
BUNDLE="$APP_NAME.app"
VERSION="2.0"

# ─── Preflight checks ─────────────────────────────────────────────────────────
echo "▸ Проверяю окружение…"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo ""
  echo "❌  Developer ID Application certificate не найден в Keychain."
  echo ""
  echo "   Как получить:"
  echo "   1. Открой: https://developer.apple.com/account/resources/certificates/add"
  echo "   2. Выбери «Developer ID Application»"
  echo "   3. Скачай .cer и дважды кликни — он добавится в Keychain"
  echo "   4. Запусти этот скрипт снова"
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" &>/dev/null; then
  echo ""
  echo "❌  Notarization credentials не настроены."
  echo "   Запусти: ./setup_notarize.sh"
  exit 1
fi

echo "   ✓ Developer ID certificate найден"
echo "   ✓ Notarization profile '$NOTARIZE_PROFILE' найден"

# ─── 1. Build ────────────────────────────────────────────────────────────────
echo ""
./build.sh

# ─── 2. Sign with Developer ID + Hardened Runtime ────────────────────────────
echo "▸ Подписываю с Developer ID…"

# 2a. Dylibs — подписываем каждую отдельно (без --deep, порядок важен)
for dylib in "$BUNDLE/Contents/Frameworks/"*.dylib; do
  codesign --force \
    --sign "$DEVELOPER_ID" \
    --timestamp \
    "$dylib" 2>&1 | grep -v "already signed"
done

# 2b. ffmpeg binary — с hardened runtime
codesign --force \
  --options runtime \
  --entitlements entitlements.plist \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "$BUNDLE/Contents/MacOS/ffmpeg"

# 2c. Основной бинарник
codesign --force \
  --options runtime \
  --entitlements entitlements.plist \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "$BUNDLE/Contents/MacOS/$APP_NAME"

# 2d. Весь bundle (без --deep, компоненты уже подписаны)
codesign --force \
  --options runtime \
  --entitlements entitlements.plist \
  --sign "$DEVELOPER_ID" \
  --timestamp \
  "$BUNDLE"

# Проверка
codesign --verify --deep --strict --verbose=2 "$BUNDLE" 2>&1 | tail -3
echo "   ✓ Подпись валидна"

# ─── 3. Notarize ─────────────────────────────────────────────────────────────
echo "▸ Создаю zip для нотаризации…"
ZIP="$APP_NAME-$VERSION-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

echo "▸ Отправляю в Apple Notary Service (1–5 мин)…"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$NOTARIZE_PROFILE" \
  --wait \
  --timeout 10m

echo "▸ Прикрепляю ticket (staple)…"
xcrun stapler staple "$BUNDLE"
xcrun stapler validate "$BUNDLE"
echo "   ✓ Нотаризация завершена"

# ─── 4. Create DMG ───────────────────────────────────────────────────────────
echo "▸ Создаю DMG…"
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

# Проверяем что Gatekeeper пропустит
spctl --assess --type exec "$BUNDLE" && echo "   ✓ Gatekeeper: OK"

# ─── Done ─────────────────────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "$DMG" | cut -f1)
echo ""
echo "══════════════════════════════════════"
echo "  ✅  $DMG ($DMG_SIZE)"
echo "  Готов к распространению."
echo "  Пользователи открывают без предупреждений."
echo "══════════════════════════════════════"
open .
