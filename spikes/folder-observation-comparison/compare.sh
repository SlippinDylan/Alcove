#!/bin/bash
set -euo pipefail

# compare.sh — Phase 0.5C2 observer comparison matrix runner
# Builds the probe, runs 3 repetitions for each candidate at 500/1000/5000 items
# (18 total probe processes), saves raw JSON lines, and produces an aggregate summary.
# Usage: bash compare.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
RAW_DIR="${BUILD_DIR}/raw"
SUMMARY_DIR="${BUILD_DIR}/summary"
PROBE_BINARY="${BUILD_DIR}/observer-comparison-probe"

REPO_ROOT="${SCRIPT_DIR}/../.."
DS_SRC="${REPO_ROOT}/spikes/folder-observation/Sources"
FSE_SRC="${REPO_ROOT}/spikes/folder-observation-fsevents/Sources"

REPETITIONS=3
ITEM_COUNTS=(500 1000 5000)
CANDIDATES=(dispatch fsevents)

if [[ $# -ne 0 ]]; then
    echo "Usage: bash compare.sh" >&2
    exit 64
fi

PYTHON_BIN="$(command -v python3 || true)"
if [[ -z "${PYTHON_BIN}" ]]; then
    echo "Error: python3 is required for deterministic JSON validation and aggregation." >&2
    exit 1
fi

run_probe_bounded() {
    local label="$1"
    local candidate="$2"
    local items="$3"
    local event_timeout="$4"
    local raw_file="$5"
    local stderr_file="$6"
    local overall_timeout=$((event_timeout + 10))
    local run_dir
    run_dir="$(mktemp -d "${BUILD_DIR}/run-${label}.XXXXXX")"
    local timeout_flag="${run_dir}/timed-out"

    TMPDIR="${run_dir}/" "${PROBE_BINARY}" \
        --candidate "${candidate}" --items "${items}" --timeout "${event_timeout}" \
        > "${raw_file}" 2> "${stderr_file}" &
    local probe_pid=$!

    (
        sleep "${overall_timeout}"
        if kill -0 "${probe_pid}" 2>/dev/null; then
            touch "${timeout_flag}"
            kill -TERM "${probe_pid}" 2>/dev/null || true
            sleep 1
            kill -KILL "${probe_pid}" 2>/dev/null || true
        fi
    ) &
    local watchdog_pid=$!

    local probe_exit=0
    wait "${probe_pid}" || probe_exit=$?
    if kill -0 "${watchdog_pid}" 2>/dev/null; then
        kill -TERM "${watchdog_pid}" 2>/dev/null || true
    fi
    wait "${watchdog_pid}" 2>/dev/null || true

    if [[ -f "${timeout_flag}" ]]; then
        probe_exit=124
        echo "Probe exceeded ${overall_timeout}s overall timeout." >> "${stderr_file}"
    fi
    rm -rf "${run_dir}"
    return "${probe_exit}"
}

echo "=== Phase 0.5C2 — Observer Comparison Matrix ==="
echo ""

# Build.
echo "Building probe..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${RAW_DIR}" "${SUMMARY_DIR}"

echo "Checking prohibited source patterns..."
if grep -REn \
    'nonisolated\(unsafe\)|@preconcurrency|try!|try\?|as!|fatalError|(^|[^[:alnum:]_])Any([^[:alnum:]_]|$)|(^|[^=!])([[:alnum:]_]+|\)|\]|>)!([^=]|$)' \
    "${SCRIPT_DIR}/Sources" 2>/dev/null; then
    echo "Prohibited source pattern found." >&2
    exit 1
elif [[ $? -ne 1 ]]; then
    echo "Source policy scan failed." >&2
    exit 1
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

xcrun swiftc \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -target arm64-apple-macosx26.0 \
    -o "${PROBE_BINARY}" \
    "${SOURCES[@]}"

echo "Probe compiled: ${PROBE_BINARY}"
echo ""

TOTAL_PROBES=$(( ${#CANDIDATES[@]} * ${#ITEM_COUNTS[@]} * REPETITIONS ))
echo "Matrix: ${#CANDIDATES[@]} candidates x ${#ITEM_COUNTS[@]} item counts x ${REPETITIONS} reps = ${TOTAL_PROBES} probes"
echo ""

# Run matrix.
PROBE_INDEX=0
FAILED=0

for candidate in "${CANDIDATES[@]}"; do
    for items in "${ITEM_COUNTS[@]}"; do
        # Timeout scales with item count.
        timeout=15
        if [[ ${items} -ge 1000 ]]; then
            timeout=20
        fi
        if [[ ${items} -ge 5000 ]]; then
            timeout=30
        fi

        for rep in $(seq 1 ${REPETITIONS}); do
            PROBE_INDEX=$((PROBE_INDEX + 1))
            LABEL="${candidate}-${items}-rep${rep}"
            RAW_FILE="${RAW_DIR}/${LABEL}.json"
            STDERR_FILE="${RAW_DIR}/${LABEL}.stderr"

            echo "[${PROBE_INDEX}/${TOTAL_PROBES}] ${LABEL} (items=${items}, timeout=${timeout}s)"

            PROBE_EXIT=0
            run_probe_bounded "${LABEL}" "${candidate}" "${items}" "${timeout}" \
                "${RAW_FILE}" "${STDERR_FILE}" || PROBE_EXIT=$?

            if [[ ${PROBE_EXIT} -ne 0 ]]; then
                echo "  FAILED (exit ${PROBE_EXIT})"
                FAILED=$((FAILED + 1))
            else
                # Validate JSON.
                if "${PYTHON_BIN}" - "${RAW_FILE}" "${candidate}" "${items}" "${timeout}" <<'PYEOF'
import json, math, sys

path = sys.argv[1]
expected_candidate = sys.argv[2]
expected_items = int(sys.argv[3])
expected_timeout = float(sys.argv[4])
with open(path) as stream:
    sample = json.load(stream)

def require(condition, message):
    if not condition:
        raise ValueError(message)

def number(name, nonnegative=True):
    value = sample.get(name)
    require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{name} must be numeric")
    require(math.isfinite(value), f"{name} must be finite")
    if nonnegative:
        require(value >= 0, f"{name} must be non-negative")
    return value

def integer(name, nonnegative=True):
    value = sample.get(name)
    require(isinstance(value, int) and not isinstance(value, bool), f"{name} must be an integer")
    if nonnegative:
        require(value >= 0, f"{name} must be non-negative")
    return value

require(sample.get("candidate") == expected_candidate, "candidate mismatch")
require(sample.get("itemCount") == expected_items, "itemCount mismatch")
require(number("timeoutSeconds") == expected_timeout, "timeoutSeconds mismatch")
for name in ("markerCreated", "firstEventReceived", "cleanupOK"):
    require(sample.get(name) is True, f"{name} must be true")
require(sample.get("timeoutExpired") is False, "timeoutExpired must be false")
require(sample.get("teardownState") == "stopped", "teardownState must be stopped")
for name in (
    "setupDurationSeconds", "observerStartDurationSeconds", "firstEventLatencySeconds",
    "descriptorSettleDurationSeconds", "teardownDurationSeconds",
):
    number(name)
for name in (
    "preStartDescriptorCount", "runningDescriptorCount", "postStopDescriptorCount",
    "postTeardownDescriptorCount", "callbackCount", "recordCount",
    "preStartMaxRSSBytes", "runningMaxRSSBytes", "postStopMaxRSSBytes",
):
    integer(name)
delta = integer("descriptorDeltaFromPreStart", nonnegative=False)
require(delta == sample["postTeardownDescriptorCount"] - sample["preStartDescriptorCount"],
        "descriptor delta mismatch")
require(sample.get("descriptorReturnedToBaseline") is (delta == 0),
        "descriptor baseline flag mismatch")
require(sample["firstEventLatencySeconds"] <= sample["timeoutSeconds"],
        "first event latency exceeds timeout")
require(sample["callbackCount"] >= 1 and sample["recordCount"] >= 1,
        "successful sample must contain an event count")
cpu_snapshots = []
for name in ("preStartCPU", "runningCPU", "postStopCPU"):
    cpu = sample.get(name)
    require(isinstance(cpu, dict), f"{name} must be an object")
    snapshot = []
    for component in ("userSec", "systemSec"):
        value = cpu.get(component)
        require(isinstance(value, (int, float)) and not isinstance(value, bool),
                f"{name}.{component} must be numeric")
        require(math.isfinite(value), f"{name}.{component} must be finite")
        require(value >= 0, f"{name}.{component} must be non-negative")
        snapshot.append(value)
    cpu_snapshots.append(snapshot)
for component in range(2):
    require(cpu_snapshots[0][component] <= cpu_snapshots[1][component] <= cpu_snapshots[2][component],
            "CPU snapshots must be monotonic")
require(sample["preStartMaxRSSBytes"] <= sample["runningMaxRSSBytes"] <= sample["postStopMaxRSSBytes"],
        "max RSS snapshots must be monotonic")
if expected_candidate == "fsevents":
    require(sample.get("bridgeFailureCount") == 0, "FSEvents bridge failures must be zero")
    require(isinstance(sample.get("callbackBatchCount"), int)
            and not isinstance(sample.get("callbackBatchCount"), bool)
            and sample["callbackBatchCount"] >= 1,
            "FSEvents callbackBatchCount must be a positive integer")
    require(sample.get("callbackBatchCount") == sample.get("callbackCount"),
            "FSEvents callback batch count mismatch")
    require(sample["recordCount"] >= sample["callbackCount"],
            "FSEvents record count must be >= callback count")
else:
    require(sample.get("bridgeFailureCount") is None, "Dispatch bridgeFailureCount must be null")
    require(sample.get("callbackBatchCount") is None, "Dispatch callbackBatchCount must be null")
    require(sample["callbackCount"] == sample["recordCount"],
            "Dispatch callback and mirrored record counts must match")
PYEOF
                then
                    FIRST_EVENT=$("${PYTHON_BIN}" -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('firstEventReceived', 'N/A'))" "${RAW_FILE}")
                    LATENCY=$("${PYTHON_BIN}" -c "import json, sys; d=json.load(open(sys.argv[1])); l=d.get('firstEventLatencySeconds'); print(f'{l:.6f}' if l is not None else 'N/A')" "${RAW_FILE}")
                    echo "  OK (event=${FIRST_EVENT}, latency=${LATENCY}s)"
                else
                    echo "  FAILED (invalid JSON)"
                    FAILED=$((FAILED + 1))
                fi
            fi
        done
    done
done

echo ""
echo "=== Matrix Complete ==="
echo "Total probes: ${TOTAL_PROBES}"
echo "Failed: ${FAILED}"
echo ""

if [[ ${FAILED} -gt 0 ]]; then
    echo "ERROR: ${FAILED} probe(s) failed. See raw JSON files in ${RAW_DIR}/"
    exit 1
fi

# Aggregate.
echo "=== Aggregate Summary ==="
echo ""

AGG_FILE="${SUMMARY_DIR}/aggregate.txt"
{
    echo "Phase 0.5C2 — Observer Comparison Aggregate"
    echo "Repetitions per combination: ${REPETITIONS}"
    echo ""

    for candidate in "${CANDIDATES[@]}"; do
        echo "=== Candidate: ${candidate} ==="
        echo ""

        for items in "${ITEM_COUNTS[@]}"; do
            echo "--- Items: ${items} ---"

            # Collect raw JSON files for this combination.
            FILES=()
            for rep in $(seq 1 ${REPETITIONS}); do
                F="${RAW_DIR}/${candidate}-${items}-rep${rep}.json"
                if [[ -f "${F}" ]]; then
                    FILES+=("${F}")
                fi
            done

            if [[ ${#FILES[@]} -ne ${REPETITIONS} ]]; then
                echo "Error: expected ${REPETITIONS} samples, found ${#FILES[@]}." >&2
                exit 1
            fi

            echo "  Samples: ${#FILES[@]}"

            # Aggregate using python3.
            "${PYTHON_BIN}" - "${FILES[@]}" <<'PYEOF'
import json, sys, statistics

files = sys.argv[1:]
samples = []
for f in files:
    try:
        with open(f) as fh:
            samples.append(json.load(fh))
    except Exception as e:
        print(f"  Error: could not parse {f}: {e}", file=sys.stderr)
        sys.exit(1)

if not samples:
    print("  No valid samples.", file=sys.stderr)
    sys.exit(1)

if len(samples) != 3:
    print(f"  Error: expected 3 valid samples, found {len(samples)}.", file=sys.stderr)
    sys.exit(1)

def safe_stats(values, label):
    if len(values) != len(samples) or any(not isinstance(v, (int, float)) or isinstance(v, bool) for v in values):
        print(f"  Error: {label} is missing or non-numeric.", file=sys.stderr)
        sys.exit(1)
    values.sort()
    n = len(values)
    mn = values[0]
    mx = values[-1]
    med = statistics.median(values)
    print(f"  {label}: min={mn:.6f}, median={med:.6f}, max={mx:.6f} (n={n})")

def safe_stats_int(values, label):
    if len(values) != len(samples) or any(not isinstance(v, int) or isinstance(v, bool) for v in values):
        print(f"  Error: {label} is missing or non-integer.", file=sys.stderr)
        sys.exit(1)
    values.sort()
    n = len(values)
    mn = values[0]
    mx = values[-1]
    med = statistics.median(values)
    print(f"  {label}: min={mn}, median={med}, max={mx} (n={n})")

# Setup duration
safe_stats([s.get("setupDurationSeconds") for s in samples], "Setup duration (s)")

# Observer start duration
safe_stats([s.get("observerStartDurationSeconds") for s in samples], "Observer start duration (s)")

# First event latency
safe_stats([s.get("firstEventLatencySeconds") for s in samples], "First event latency (s)")

# Callback count
safe_stats_int([s.get("callbackCount") for s in samples], "Callback count")

# Record count
safe_stats_int([s.get("recordCount") for s in samples], "Record count")

# Callback batch count (FSEvents only)
batches = [s.get("callbackBatchCount") for s in samples if s.get("callbackBatchCount") is not None]
if batches:
    safe_stats_int(batches, "Callback batch count")

# Teardown duration
safe_stats([s.get("teardownDurationSeconds") for s in samples], "Teardown duration (s)")

# CPU user delta
cpu_user_deltas = []
for s in samples:
    pre = s.get("preStartCPU", {})
    post = s.get("postStopCPU", {})
    if "userSec" in pre and "userSec" in post:
        cpu_user_deltas.append(post["userSec"] - pre["userSec"])
safe_stats(cpu_user_deltas, "CPU user delta (s)")

# CPU system delta
cpu_sys_deltas = []
for s in samples:
    pre = s.get("preStartCPU", {})
    post = s.get("postStopCPU", {})
    if "systemSec" in pre and "systemSec" in post:
        cpu_sys_deltas.append(post["systemSec"] - pre["systemSec"])
safe_stats(cpu_sys_deltas, "CPU system delta (s)")

# Max RSS
rss_values = [s.get("postStopMaxRSSBytes") for s in samples if s.get("postStopMaxRSSBytes") is not None]
safe_stats_int(rss_values, "Post-stop max RSS (bytes)")

# Descriptor deltas
desc_deltas = [s.get("descriptorDeltaFromPreStart") for s in samples]
safe_stats_int(desc_deltas, "Descriptor delta (post-teardown vs pre-start)")

safe_stats([s.get("descriptorSettleDurationSeconds") for s in samples], "Descriptor settle duration (s)")
returned = [s.get("descriptorReturnedToBaseline") for s in samples]
if any(not isinstance(value, bool) for value in returned):
    print("  Error: descriptor baseline flags are missing or non-boolean.", file=sys.stderr)
    sys.exit(1)
print(f"  Descriptor returned to baseline: {sum(returned)}/{len(returned)} samples")

# Bridge failure count (FSEvents only)
bridges = [s.get("bridgeFailureCount") for s in samples if s.get("bridgeFailureCount") is not None]
if bridges:
    safe_stats_int(bridges, "Bridge failure count")

print()
PYEOF

            echo ""
        done
    done

    echo "=== Limitations ==="
    echo "- 3 samples per combination; do not claim statistical significance."
    echo "- Local single-machine measurement; not a platform guarantee."
    echo "- FSEvents latency includes its configurable 0.3s latency parameter."
    echo "- DispatchSource events are directory-level invalidation signals."
    echo "- FSEvents events are item-level records with flags."
    echo "- Do not compare one DispatchSource callback directly with one FSEvents record."
    echo "- Descriptor delta may include runtime-internal descriptors."
    echo ""
    echo "=== Raw Data ==="
    echo "Raw JSON lines: ${RAW_DIR}/"
    echo "Each file contains one complete probe result."
} | tee "${AGG_FILE}"

echo ""
echo "Aggregate saved to: ${AGG_FILE}"
echo ""
echo "=== Compare Complete ==="
