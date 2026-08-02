#!/bin/bash
set -euo pipefail

# test.sh — Alcove Spike 0.3A Quick Look Responder Bootstrap Tests
# Compiles and runs structural and non-visual integration tests.
# Usage: bash test.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
TEST_BUNDLE="${BUILD_DIR}/QuickLookTests.app"
TEST_CONTENTS="${TEST_BUNDLE}/Contents"
TEST_BINARY="${TEST_CONTENTS}/MacOS/QuickLookTests"
RESULT_FILE="${BUILD_DIR}/quick-look-test-result.txt"

if [[ $# -ne 0 ]]; then
    echo "Usage: bash test.sh" >&2
    exit 64
fi

echo "=== Alcove Spike 0.3A — Quick Look Responder Bootstrap Tests ==="
echo ""

echo "Checking prohibited source patterns..."
if grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|as!|fatalError|QLPreviewPanel\.shared\(\).*toggle' \
    "${SCRIPT_DIR}/Sources" "${SCRIPT_DIR}/Tests"; then
    echo "Prohibited source pattern found."
    exit 1
fi
echo "Source policy checks passed."
echo ""

# Compile test executable with all source files so tests have internal access.
echo "Compiling tests..."
rm -rf "${BUILD_DIR}"
mkdir -p "${TEST_CONTENTS}/MacOS"

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -framework AppKit \
    -framework CoreGraphics \
    -framework Foundation \
    -framework Quartz \
    -o "${TEST_BINARY}" \
    "${SCRIPT_DIR}/Sources/PreviewFixture.swift" \
    "${SCRIPT_DIR}/Sources/QuickLookController.swift" \
    "${SCRIPT_DIR}/Sources/SpikeWindow.swift" \
    "${SCRIPT_DIR}/Sources/CollectionViewController.swift" \
    "${SCRIPT_DIR}/Tests/main.swift"

echo "Compile succeeded (exit code 0)."
echo ""

cat > "${TEST_CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>QuickLookTests</string>
    <key>CFBundleIdentifier</key>
    <string>com.alcove.spike.quick-look-tests</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>QuickLookTests</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
</dict>
</plist>
PLIST
xcrun codesign --force --sign - "${TEST_BUNDLE}" >/dev/null

# Run tests
echo "Running tests..."
echo "---"
open -W "${TEST_BUNDLE}" --args --result "${RESULT_FILE}"
if [[ ! -f "${RESULT_FILE}" ]]; then
    echo "Test app did not produce a result file."
    exit 1
fi
cat "${RESULT_FILE}"
if grep -q '^exit_code=0$' "${RESULT_FILE}"; then
    TEST_EXIT=0
else
    TEST_EXIT=1
fi
echo "---"
echo ""
echo "Test exit code: ${TEST_EXIT}"

exit ${TEST_EXIT}
