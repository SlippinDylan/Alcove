#!/bin/bash
set -euo pipefail

# build.sh — Phase 0.5C2 observer comparison build
# Compiles the probe binary from candidate sources directly.
# Usage: bash build.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PROBE_BINARY="${BUILD_DIR}/observer-comparison-probe"

REPO_ROOT="${SCRIPT_DIR}/../.."
DS_SRC="${REPO_ROOT}/spikes/folder-observation/Sources"
FSE_SRC="${REPO_ROOT}/spikes/folder-observation-fsevents/Sources"

if [[ $# -ne 0 ]]; then
    echo "Usage: bash build.sh" >&2
    exit 64
fi

SOURCES=(
    "${DS_SRC}/FolderObservationRecord.swift"
    "${DS_SRC}/FolderObserverError.swift"
    "${DS_SRC}/DispatchSourceFolderObserver.swift"
    "${FSE_SRC}/FSEventError.swift"
    "${FSE_SRC}/FSEventRecord.swift"
    "${FSE_SRC}/FSEventsFolderObserver.swift"
    "${SCRIPT_DIR}/Sources/main.swift"
)

echo "=== Phase 0.5C2 — Observer Comparison Build ==="
echo "Sources: ${#SOURCES[@]} files"

# Verify source files exist.
for src in "${SOURCES[@]}"; do
    if [[ ! -f "${src}" ]]; then
        echo "Error: source file not found: ${src}" >&2
        exit 1
    fi
done

# Clean previous build.
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Check prohibited source patterns in our own sources.
echo "Checking prohibited source patterns..."
SCAN_EXIT=0
grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|try\?|as!|fatalError|(^|[^[:alnum:]_])Any([^[:alnum:]_]|$)|(^|[^=!])([[:alnum:]_]+|\)|\]|>)!([^=]|$)' \
    "${SCRIPT_DIR}/Sources" 2>/dev/null || SCAN_EXIT=$?
if [[ ${SCAN_EXIT} -eq 0 ]]; then
    echo "Prohibited source pattern found."
    exit 1
elif [[ ${SCAN_EXIT} -ne 1 ]]; then
    echo "Source policy scan failed with exit ${SCAN_EXIT}." >&2
    exit 1
fi
echo "Source policy checks passed."

# Compile.
echo "Compiling probe..."
xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${PROBE_BINARY}" \
    "${SOURCES[@]}"

echo "Compile succeeded."

# Verify binary.
echo ""
echo "=== Build Complete ==="
echo "Probe binary: ${PROBE_BINARY}"
echo ""
echo "Architecture:"
lipo -info "${PROBE_BINARY}" 2>/dev/null || file "${PROBE_BINARY}"
echo ""
echo "Dependencies:"
otool -L "${PROBE_BINARY}" | head -10
echo ""
echo "Minimum deployment target:"
otool -l "${PROBE_BINARY}" | grep -A2 LC_BUILD_VERSION | head -5 || echo "(inspection via otool)"
