#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PROBE_BINARY="${BUILD_DIR}/observer-load-probe"
TEST_BINARY="${BUILD_DIR}/observer-load-tests"
REPO_ROOT="${SCRIPT_DIR}/../.."
DS_SRC="${REPO_ROOT}/spikes/folder-observation/Sources"
FSE_SRC="${REPO_ROOT}/spikes/folder-observation-fsevents/Sources"

if [[ $# -ne 0 ]]; then
    echo "Usage: bash test.sh" >&2
    exit 64
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

CANDIDATE_SOURCES=(
    "${DS_SRC}/FolderObservationRecord.swift"
    "${DS_SRC}/FolderObserverError.swift"
    "${DS_SRC}/DispatchSourceFolderObserver.swift"
    "${FSE_SRC}/FSEventError.swift"
    "${FSE_SRC}/FSEventRecord.swift"
    "${FSE_SRC}/FSEventsFolderObserver.swift"
)

SCAN_EXIT=0
grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|try\?|as!|fatalError|(^|[^[:alnum:]_])Any([^[:alnum:]_]|$)|(^|[^=!])([[:alnum:]_]+|\)|\]|>)!([^=]|$)' \
    "${SCRIPT_DIR}/Sources" "${SCRIPT_DIR}/Tests" "${DS_SRC}" "${FSE_SRC}" \
    2>/dev/null || SCAN_EXIT=$?
if [[ ${SCAN_EXIT} -eq 0 ]]; then
    echo "Prohibited source pattern found." >&2
    exit 1
elif [[ ${SCAN_EXIT} -ne 1 ]]; then
    echo "Source policy scan failed with exit ${SCAN_EXIT}." >&2
    exit 1
fi

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${PROBE_BINARY}" \
    "${CANDIDATE_SOURCES[@]}" \
    "${SCRIPT_DIR}/Sources/main.swift"

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${TEST_BINARY}" \
    "${SCRIPT_DIR}/Tests/main.swift"

"${TEST_BINARY}" "${PROBE_BINARY}"
