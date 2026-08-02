#!/bin/bash
set -euo pipefail

# test.sh — Alcove Spike 0.5C1 Background Directory Enumeration Tests
# Compiles and runs the automated test harness.
# Usage: bash test.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
TEST_BINARY="${BUILD_DIR}/folder-enumeration-tests"

if [[ $# -ne 0 ]]; then
    echo "Usage: bash test.sh" >&2
    exit 64
fi

echo "=== Alcove Spike 0.5C1 — Background Directory Enumeration Tests ==="
echo ""

echo "Checking prohibited source patterns (conservative text scan)..."
if grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|try\?|as!|fatalError|(^|[^[:alnum:]_])Any([^[:alnum:]_]|$)|(^|[^=!])([[:alnum:]_]+|\)|\]|>)!([^=]|$)' \
    "${SCRIPT_DIR}/Sources" "${SCRIPT_DIR}/Tests"; then
    echo "Prohibited source pattern found."
    exit 1
elif [[ $? -ne 1 ]]; then
    echo "Source policy scan failed to execute."
    exit 1
fi
echo "Source policy checks passed."
echo ""

# Compile test executable with all source files so tests have internal access.
echo "Compiling tests..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${TEST_BINARY}" \
    "${SCRIPT_DIR}/Sources/EnumerationError.swift" \
    "${SCRIPT_DIR}/Sources/ChildEntry.swift" \
    "${SCRIPT_DIR}/Sources/DirectorySnapshot.swift" \
    "${SCRIPT_DIR}/Sources/DirectoryEnumerator.swift" \
    "${SCRIPT_DIR}/Sources/WorkerQueue.swift" \
    "${SCRIPT_DIR}/Sources/CancellationToken.swift" \
    "${SCRIPT_DIR}/Sources/EnumerationRequestRunner.swift" \
    "${SCRIPT_DIR}/Sources/Coordinator.swift" \
    "${SCRIPT_DIR}/Tests/main.swift"

echo "Compile succeeded (exit code 0)."
echo ""

# Run tests
echo "Running tests..."
echo "---"
TEST_EXIT=0
"${TEST_BINARY}" || TEST_EXIT=$?
echo "---"
echo ""
echo "Test exit code: ${TEST_EXIT}"

exit ${TEST_EXIT}
