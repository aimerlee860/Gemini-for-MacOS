#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Gemini"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE_NAME="Gemini"

echo "==> Compiling..."
mkdir -p "$BUILD_DIR"

# Collect all Swift source files (main.swift LAST)
SOURCES=(
    "$PROJECT_DIR/App/AppDelegate.swift"
    "$PROJECT_DIR/Coordinators/AppCoordinator.swift"
    "$PROJECT_DIR/Utils/UserDefaultsKeys.swift"
    "$PROJECT_DIR/Views/MainWindowView.swift"
    "$PROJECT_DIR/Views/SettingsView.swift"
    "$PROJECT_DIR/WebKit/GeminiWebView.swift"
    "$PROJECT_DIR/WebKit/UserScripts.swift"
    "$PROJECT_DIR/WebKit/WebViewModel.swift"
    "$PROJECT_DIR/App/main.swift"
)

swiftc \
    -o "$BUILD_DIR/$EXECUTABLE_NAME" \
    "${SOURCES[@]}" \
    -target x86_64-apple-macosx12.0 \
    -swift-version 5 \
    -O \
    -framework AppKit \
    -framework SwiftUI \
    -framework WebKit \
    -framework Combine \
    -framework Foundation \
    -framework CoreGraphics

echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Copy Assets
if [ -d "$PROJECT_DIR/Resources/Assets.xcassets" ]; then
    cp -R "$PROJECT_DIR/Resources/Assets.xcassets" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy icon
if [ -f "$PROJECT_DIR/Resources/Gemini.icns" ]; then
    cp "$PROJECT_DIR/Resources/Gemini.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo ""
echo "==> Done: $APP_BUNDLE"
echo "==> Run: open \"$APP_BUNDLE\""
