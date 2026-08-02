#!/bin/bash
set -euo pipefail

# build.sh — Alcove Spike 0.1 Desktop Window Experiment
# Deterministic .app bundle build using swiftc.
# Usage: bash build.sh [--run]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AlcoveSpike"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
CONTENTS_DIR="${APP_BUNDLE}/Contents"

SOURCES=(
    "${SCRIPT_DIR}/Sources/WindowStrategy.swift"
    "${SCRIPT_DIR}/Sources/AlcoveSpikeWindow.swift"
    "${SCRIPT_DIR}/Sources/DiagnosticsView.swift"
    "${SCRIPT_DIR}/Sources/ExperimentWindowController.swift"
    "${SCRIPT_DIR}/Sources/AppDelegate.swift"
    "${SCRIPT_DIR}/Sources/main.swift"
)

echo "=== Alcove Spike 0.1 — Build ==="
echo "Sources: ${#SOURCES[@]} files"

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}"

# Compile
echo "Compiling..."
xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -framework AppKit \
    -framework CoreGraphics \
    -framework Foundation \
    -o "${MACOS_DIR}/${APP_NAME}" \
    "${SOURCES[@]}"

echo "Compile succeeded (exit code 0)."

# Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AlcoveSpike</string>
    <key>CFBundleDisplayName</key>
    <string>Alcove Spike</string>
    <key>CFBundleIdentifier</key>
    <string>com.alcove.spike.desktop-window</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AlcoveSpike</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
PLIST

# PkgInfo
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Code sign (ad-hoc)
echo "Code signing (ad-hoc)..."
xcrun codesign --force --sign - "${APP_BUNDLE}" 2>&1

echo ""
echo "=== Build Complete ==="
echo "App bundle: ${APP_BUNDLE}"
echo ""
echo "Run:  open \"${APP_BUNDLE}\""
echo "Or:   bash build.sh --run"

if [[ "${1:-}" == "--run" ]]; then
    echo ""
    echo "Launching..."
    open "${APP_BUNDLE}"
fi
