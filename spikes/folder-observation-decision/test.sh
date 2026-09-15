#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
TEST_BINARY="${BUILD_DIR}/fsevents-recovery-tests"
FSEVENT_RECORD="${SCRIPT_DIR}/../folder-observation-fsevents/Sources/FSEventRecord.swift"

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

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx26.0 \
    -o "${TEST_BINARY}" \
    "${FSEVENT_RECORD}" \
    "${SCRIPT_DIR}/Sources/FSEventsRecoveryPolicy.swift" \
    "${SCRIPT_DIR}/Tests/main.swift"

"${TEST_BINARY}"
