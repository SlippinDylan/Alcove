#!/bin/bash
set -euo pipefail

# test.sh — Alcove Spike 0.1B Strategy Model Tests
# Compiles and runs the structural strategy model tests.
# Usage: bash test.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
TEST_BINARY="${BUILD_DIR}/StrategyPresetTests"

echo "=== Alcove Spike 0.1B — Strategy Model Tests ==="
echo ""

# Compile test executable with the model source
echo "Compiling tests..."
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
    "${SCRIPT_DIR}/Sources/WindowStrategy.swift" \
    "${SCRIPT_DIR}/Sources/AlcoveSpikeWindow.swift" \
    "${SCRIPT_DIR}/Sources/DiagnosticsView.swift" \
    "${SCRIPT_DIR}/Sources/ExperimentWindowController.swift" \
    "${SCRIPT_DIR}/Tests/main.swift"

echo "Compile succeeded (exit code 0)."
echo ""

# Run tests
echo "Running tests..."
echo "---"
"${TEST_BINARY}"
TEST_EXIT=$?
echo "---"
echo ""
echo "Test exit code: ${TEST_EXIT}"

exit ${TEST_EXIT}
