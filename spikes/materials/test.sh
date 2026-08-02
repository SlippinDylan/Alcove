#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
TEST_BINARY="${BUILD_DIR}/MaterialBoundaryTests"

if [[ $# -ne 0 ]]; then
    echo "Usage: bash test.sh" >&2
    exit 64
fi

echo "=== Alcove Spike 0.4A — Material Boundary Tests ==="
echo "Checking prohibited source patterns (conservative text scan)..."
if grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|try\?|as!|fatalError|setValue\(|value\(forKey|isInteractive|NSGlassEffectView[^[:cntrl:]]*\.state|(^|[^[:alnum:]_])Any([^[:alnum:]_]|$)|(^|[^=!])([[:alnum:]_]+|\)|\]|>)!([^=]|$)' \
    "${SCRIPT_DIR}/Sources" "${SCRIPT_DIR}/Tests"; then
    echo "Prohibited source pattern found."
    exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -framework AppKit \
    -framework CoreGraphics \
    -framework Foundation \
    -o "${TEST_BINARY}" \
    "${SCRIPT_DIR}/Sources/MaterialModel.swift" \
    "${SCRIPT_DIR}/Sources/MaterialChromeView.swift" \
    "${SCRIPT_DIR}/Sources/MaterialWindowController.swift" \
    "${SCRIPT_DIR}/Sources/AppDelegate.swift" \
    "${SCRIPT_DIR}/Tests/main.swift"

echo "Compile succeeded."
"${TEST_BINARY}"
