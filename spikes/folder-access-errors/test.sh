#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PROBE_BINARY="${BUILD_DIR}/folder-access-probe"
TEST_BINARY="${BUILD_DIR}/folder-access-tests"

if [[ $# -ne 0 ]]; then
    echo "Usage: bash test.sh" >&2
    exit 64
fi

SCAN_EXIT=0
grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|try\?|as!|fatalError|(^|[^[:alnum:]_])Any([^[:alnum:]_]|$)|(^|[^=!])([[:alnum:]_]+|\)|\]|>)!([^=]|$)' \
    "${SCRIPT_DIR}/Sources" "${SCRIPT_DIR}/Tests" 2>/dev/null || SCAN_EXIT=$?
if [[ ${SCAN_EXIT} -eq 0 ]]; then
    echo "Prohibited source pattern found." >&2
    exit 1
elif [[ ${SCAN_EXIT} -ne 1 ]]; then
    echo "Source policy scan failed with exit ${SCAN_EXIT}." >&2
    exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

COMMON_SOURCES=(
    "${SCRIPT_DIR}/Sources/FolderAccessError.swift"
    "${SCRIPT_DIR}/Sources/ProbeTypes.swift"
    "${SCRIPT_DIR}/Sources/FixtureValidator.swift"
)

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${PROBE_BINARY}" \
    "${COMMON_SOURCES[@]}" \
    "${SCRIPT_DIR}/Sources/main.swift"

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${TEST_BINARY}" \
    "${COMMON_SOURCES[@]}" \
    "${SCRIPT_DIR}/Tests/main.swift"

"${TEST_BINARY}" "${PROBE_BINARY}"
