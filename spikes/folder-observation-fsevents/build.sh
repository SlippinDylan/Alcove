#!/bin/bash
set -euo pipefail

# build.sh — Alcove Spike 0.5B FSEvents Folder Observer Bootstrap
# Deterministic command-line build using swiftc.
# Usage: bash build.sh [--run [directory] [duration]]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PROBE_BINARY="${BUILD_DIR}/folder-observer-fsevents-probe"

if [[ $# -gt 3 || ($# -ge 1 && "$1" != "--run") ]]; then
    echo "Usage: bash build.sh [--run [directory] [duration]]" >&2
    exit 64
fi

SOURCES=(
    "${SCRIPT_DIR}/Sources/FSEventError.swift"
    "${SCRIPT_DIR}/Sources/FSEventRecord.swift"
    "${SCRIPT_DIR}/Sources/FSEventsFolderObserver.swift"
    "${SCRIPT_DIR}/Sources/main.swift"
)

echo "=== Alcove Spike 0.5B — FSEvents Build ==="
echo "Sources: ${#SOURCES[@]} files"

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Check prohibited source patterns
echo "Checking prohibited source patterns (conservative text scan)..."
if grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|try\?|as!|fatalError|(^|[^[:alnum:]_])Any([^[:alnum:]_]|$)|(^|[^=!])([[:alnum:]_]+|\)|\]|>)!([^=]|$)' \
    "${SCRIPT_DIR}/Sources"; then
    echo "Prohibited source pattern found."
    exit 1
elif [[ $? -ne 1 ]]; then
    echo "Source policy scan failed to execute."
    exit 1
fi
echo "Source policy checks passed."

# Compile
echo "Compiling..."
xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -o "${PROBE_BINARY}" \
    "${SOURCES[@]}"

echo "Compile succeeded (exit code 0)."

echo ""
echo "=== Build Complete ==="
echo "Probe binary: ${PROBE_BINARY}"
echo ""
echo "Run:  ${PROBE_BINARY} <directory> [duration]"
echo "Or:   bash build.sh --run <directory> [duration]"

if [[ "${1:-}" == "--run" ]]; then
    shift
    DIR="${1:-/tmp}"
    DURATION="${2:-5}"
    echo ""
    echo "Running probe: ${PROBE_BINARY} ${DIR} ${DURATION}"
    "${PROBE_BINARY}" "${DIR}" "${DURATION}"
fi
