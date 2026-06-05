#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_DIR="$PROJECT_ROOT/.build/Modex.app"

cd "$PROJECT_ROOT"
swift build

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_ROOT/.build/debug/modex" "$APP_DIR/Contents/MacOS/Modex"
cp "$PROJECT_ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
for bundle in "$PROJECT_ROOT"/.build/debug/modex_*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
chmod +x "$APP_DIR/Contents/MacOS/Modex"

echo "$APP_DIR"
