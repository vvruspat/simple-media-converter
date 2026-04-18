#!/bin/bash
APP="SimpleMediaConverter.app"
DEST="$HOME/Applications"

# Find the .app next to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/$APP"

if [ ! -d "$SRC" ]; then
    echo "❌  $APP not found next to this script."
    exit 1
fi

echo "▸ Removing quarantine..."
xattr -dr com.apple.quarantine "$SRC"

echo "▸ Copying to $DEST..."
mkdir -p "$DEST"
cp -R "$SRC" "$DEST/"

echo ""
echo "✅  Done! Launch from $DEST/$APP"
open "$DEST/$APP"
