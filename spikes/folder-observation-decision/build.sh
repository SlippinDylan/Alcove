#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PROBE_BINARY="${BUILD_DIR}/fsevents-recovery-probe"
FSEVENT_RECORD="${SCRIPT_DIR}/../folder-observation-fsevents/Sources/FSEventRecord.swift"

if [[ $# -ne 0 ]]; then
    echo "Usage: bash build.sh" >&2
    exit 64
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${PROBE_BINARY}" \
    "${FSEVENT_RECORD}" \
    "${SCRIPT_DIR}/Sources/FSEventsRecoveryPolicy.swift" \
    "${SCRIPT_DIR}/Sources/main.swift"

echo "Built ${PROBE_BINARY}"
