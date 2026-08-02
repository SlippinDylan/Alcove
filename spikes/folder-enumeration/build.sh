#!/bin/bash
set -euo pipefail

# build.sh — Alcove Spike 0.5C1 Background Directory Enumeration Bootstrap
# Deterministic command-line build using swiftc.
# Usage: bash build.sh [--run [directory]]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PROBE_BINARY="${BUILD_DIR}/folder-enumeration-probe"

if [[ $# -gt 2 || ($# -ge 1 && "$1" != "--run") ]]; then
    echo "Usage: bash build.sh [--run [directory]]" >&2
    exit 64
fi

SOURCES=(
    "${SCRIPT_DIR}/Sources/EnumerationError.swift"
    "${SCRIPT_DIR}/Sources/ChildEntry.swift"
    "${SCRIPT_DIR}/Sources/DirectorySnapshot.swift"
    "${SCRIPT_DIR}/Sources/DirectoryEnumerator.swift"
    "${SCRIPT_DIR}/Sources/WorkerQueue.swift"
    "${SCRIPT_DIR}/Sources/CancellationToken.swift"
    "${SCRIPT_DIR}/Sources/EnumerationRequestRunner.swift"
    "${SCRIPT_DIR}/Sources/Coordinator.swift"
    "${SCRIPT_DIR}/Sources/main.swift"
)

echo "=== Alcove Spike 0.5C1 — Build ==="
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
echo "Run:  ${PROBE_BINARY} <directory>"
echo "Or:   bash build.sh --run <directory>"

if [[ "${1:-}" == "--run" ]]; then
    shift
    DIR="${1:-/tmp}"
    echo ""
    echo "Running probe: ${PROBE_BINARY} ${DIR}"
    "${PROBE_BINARY}" "${DIR}"
fi
