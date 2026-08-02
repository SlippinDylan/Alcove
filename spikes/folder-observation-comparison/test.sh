#!/bin/bash
set -euo pipefail

# test.sh — Phase 0.5C2 observer comparison tests
# Builds probe and test harness, runs tests.
# Usage: bash test.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PROBE_BINARY="${BUILD_DIR}/observer-comparison-probe"
TEST_BINARY="${BUILD_DIR}/comparison-tests"

REPO_ROOT="${SCRIPT_DIR}/../.."
DS_SRC="${REPO_ROOT}/spikes/folder-observation/Sources"
FSE_SRC="${REPO_ROOT}/spikes/folder-observation-fsevents/Sources"

if [[ $# -ne 0 ]]; then
    echo "Usage: bash test.sh" >&2
    exit 64
fi

echo "=== Phase 0.5C2 — Observer Comparison Tests ==="
echo ""

# Clean and build.
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

PROBE_SOURCES=(
    "${DS_SRC}/FolderObservationRecord.swift"
    "${DS_SRC}/FolderObserverError.swift"
    "${DS_SRC}/DispatchSourceFolderObserver.swift"
    "${FSE_SRC}/FSEventError.swift"
    "${FSE_SRC}/FSEventRecord.swift"
    "${FSE_SRC}/FSEventsFolderObserver.swift"
    "${SCRIPT_DIR}/Sources/main.swift"
)

TEST_SOURCES=(
    "${DS_SRC}/FolderObservationRecord.swift"
    "${DS_SRC}/FolderObserverError.swift"
    "${DS_SRC}/DispatchSourceFolderObserver.swift"
    "${FSE_SRC}/FSEventError.swift"
    "${FSE_SRC}/FSEventRecord.swift"
    "${FSE_SRC}/FSEventsFolderObserver.swift"
    "${SCRIPT_DIR}/Tests/main.swift"
)

echo "Checking prohibited source patterns..."
SCAN_EXIT=0
grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|try\?|as!|fatalError|(^|[^[:alnum:]_])Any([^[:alnum:]_]|$)|(^|[^=!])([[:alnum:]_]+|\)|\]|>)!([^=]|$)' \
    "${SCRIPT_DIR}/Sources" "${SCRIPT_DIR}/Tests" 2>/dev/null || SCAN_EXIT=$?
if [[ ${SCAN_EXIT} -eq 0 ]]; then
    echo "Prohibited source pattern found."
    exit 1
elif [[ ${SCAN_EXIT} -ne 1 ]]; then
    echo "Source policy scan failed with exit ${SCAN_EXIT}." >&2
    exit 1
fi
echo "Source policy checks passed."
echo ""

echo "Compiling probe..."
xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${PROBE_BINARY}" \
    "${PROBE_SOURCES[@]}"
echo "Probe compiled."

echo "Compiling tests..."
xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${TEST_BINARY}" \
    "${TEST_SOURCES[@]}"
echo "Tests compiled."
echo ""

echo "Running tests..."
echo "---"
TEST_EXIT=0
"${TEST_BINARY}" "${PROBE_BINARY}" || TEST_EXIT=$?
echo "---"
echo ""
echo "Test exit code: ${TEST_EXIT}"

exit ${TEST_EXIT}
