#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_DIR="$PROJECT_ROOT/.build/Modex.app"
BUILD_CONFIGURATION=${MODEX_BUILD_CONFIGURATION:-release}

cd "$PROJECT_ROOT"
swift build -c "$BUILD_CONFIGURATION"

BINARY="$PROJECT_ROOT/.build/$BUILD_CONFIGURATION/modex"
APP_VERSION=$("$BINARY" --version-number)
APP_BUILD=$("$BINARY" --build-number)

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/Modex"
cp "$PROJECT_ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP_DIR/Contents/Info.plist"
for bundle in "$PROJECT_ROOT"/.build/"$BUILD_CONFIGURATION"/modex_*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
chmod +x "$APP_DIR/Contents/MacOS/Modex"

echo "$APP_DIR"
