#!/bin/bash
APP="SimpleMediaConverter.app"
DEST="$HOME/Applications"

# Find the .app next to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/$APP"

if [ ! -d "$SRC" ]; then
    echo "❌  $APP не найден рядом со скриптом."
    exit 1
fi

echo "▸ Снимаю карантин…"
xattr -dr com.apple.quarantine "$SRC"

echo "▸ Копирую в $DEST…"
mkdir -p "$DEST"
cp -R "$SRC" "$DEST/"

echo ""
echo "✅  Готово! Запускай из $DEST/$APP"
open "$DEST/$APP"
