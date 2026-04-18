#!/bin/bash
set -e

APP_NAME="SimpleMediaConverter"
BUNDLE="$APP_NAME.app"
BREW="/opt/homebrew/bin/brew"

# ── 1. Build Swift app ──────────────────────────────────────────────────────
echo "▸ Building Swift app…"
swift build -c release 2>&1

# ── 2. Generate app icon ────────────────────────────────────────────────────
echo "▸ Генерирую иконку…"
swift generate_icon.swift 2>&1 | grep -v "^$"
iconutil -c icns AppIcon.iconset -o AppIcon.icns

# ── 3. Ensure ffmpeg is installed ───────────────────────────────────────────
if ! "$BREW" list --formula ffmpeg &>/dev/null; then
    echo "▸ Устанавливаю ffmpeg (один раз)…"
    "$BREW" install ffmpeg
fi
FFMPEG_BIN="$("$BREW" --prefix ffmpeg)/bin/ffmpeg"

# ── 4. Ensure dylibbundler is installed ─────────────────────────────────────
if ! command -v dylibbundler &>/dev/null; then
    echo "▸ Устанавливаю dylibbundler…"
    "$BREW" install dylibbundler
fi

# ── 5. Create .app bundle skeleton ──────────────────────────────────────────
echo "▸ Создаю $BUNDLE…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Frameworks"
mkdir -p "$BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/"
cp AppIcon.icns "$BUNDLE/Contents/Resources/"

cat > "$BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>         <string>SimpleMediaConverter</string>
    <key>CFBundleIdentifier</key>         <string>com.vvruspat.simple-media-converter</string>
    <key>CFBundleName</key>               <string>SimpleMediaConverter</string>
    <key>CFBundleDisplayName</key>        <string>WAV → MP3</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundleVersion</key>            <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>NSPrincipalClass</key>           <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# ── 6. Bundle ffmpeg + all its .dylib dependencies ──────────────────────────
echo "▸ Встраиваю ffmpeg и зависимости…"
cp "$FFMPEG_BIN" "$BUNDLE/Contents/MacOS/ffmpeg"
chmod +x "$BUNDLE/Contents/MacOS/ffmpeg"

dylibbundler \
    --overwrite-dir \
    --bundle-deps \
    --fix-file "$BUNDLE/Contents/MacOS/ffmpeg" \
    --dest-dir "$BUNDLE/Contents/Frameworks/" \
    --install-path "@executable_path/../Frameworks/" \
    2>&1 | grep -v "^$"

# ── 7. Ad-hoc sign ──────────────────────────────────────────────────────────
echo "▸ Подписываю…"
codesign --force --deep --sign - "$BUNDLE" 2>&1

echo ""
echo "✓ Готово: $BUNDLE"
open "$BUNDLE"
