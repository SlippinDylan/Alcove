// StrategyPresetTests.swift
// Alcove Spike 0.1B — Structural strategy model tests.
// Compiles with WindowStrategy.swift to verify model invariants without GUI.
//
// This test executable verifies structural properties of the strategy model.
// It does NOT test GUI behavior, Spaces, Show Desktop, key-window activation,
// or any system-level transitions — those require manual verification.

import AppKit
import CoreGraphics

// MARK: - Test Harness

var passed = 0
var failed = 0

@MainActor
func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(message) (\(file):\(line))")
    }
}

@MainActor
func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(message) — expected \(b), got \(a) (\(file):\(line))")
    }
}

// MARK: - Desktop Icon Window Level Helper

let desktopIconWindowLevel = NSWindow.Level(
    rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
)

// MARK: - Tests

@MainActor func testPresetIdentifiersAreUnique() {
    let identifiers = StrategyPreset.allCases.map { $0.identifier }
    let unique = Set(identifiers)
    assert(
        identifiers.count == unique.count,
        "Preset identifiers must be unique; found \(identifiers.count) presets, \(unique.count) unique identifiers"
    )
}

@MainActor func testPresetNamesAreUnique() {
    let names = StrategyPreset.allCases.map { $0.description }
    let unique = Set(names)
    assert(
        names.count == unique.count,
        "Preset names must be unique; found \(names.count) presets, \(unique.count) unique names"
    )
}

@MainActor func testNormalBaselineHasNormalLevelAndMinimalBehavior() {
    let config = StrategyPreset.normalBaseline.configuration
    assertEqual(
        config.windowLevel, .normal,
        "Normal Baseline must have .normal window level"
    )
    assert(
        config.collectionBehavior.isEmpty,
        "Normal Baseline must have empty (minimal) collection behavior"
    )
    assert(
        config.isKeyEligible,
        "Normal Baseline must be key-eligible"
    )
}

@MainActor func testDesktopCandidateRetainsPhase01AProperties() {
    let config = StrategyPreset.desktopCandidate.configuration
    assertEqual(
        config.windowLevel, desktopIconWindowLevel,
        "Desktop Candidate must have desktopIconWindow + 1 level"
    )
    assert(
        config.collectionBehavior.contains(.canJoinAllSpaces),
        "Desktop Candidate must have .canJoinAllSpaces"
    )
    assert(
        config.collectionBehavior.contains(.stationary),
        "Desktop Candidate must have .stationary"
    )
    assert(
        config.collectionBehavior.contains(.ignoresCycle),
        "Desktop Candidate must have .ignoresCycle"
    )
    assert(
        config.isKeyEligible,
        "Desktop Candidate must be key-eligible"
    )
}

@MainActor func testCollectionBehaviorMatchesTypedConfiguration() {
    // Verify that every preset's collectionBehavior matches its typed
    // configuration — no flags are added or lost in the property accessor.
    for preset in StrategyPreset.allCases {
        assertEqual(
            preset.collectionBehavior,
            preset.configuration.collectionBehavior,
            "\(preset.identifier): collectionBehavior accessor must match configuration"
        )
    }
}

@MainActor func testWindowLevelMatchesTypedConfiguration() {
    for preset in StrategyPreset.allCases {
        assertEqual(
            preset.windowLevel,
            preset.configuration.windowLevel,
            "\(preset.identifier): windowLevel accessor must match configuration"
        )
    }
}

@MainActor func testKeyEligibilityMatchesTypedConfiguration() {
    for preset in StrategyPreset.allCases {
        assert(
            preset.isKeyEligible == preset.configuration.isKeyEligible,
            "\(preset.identifier): isKeyEligible accessor must match configuration"
        )
    }
}

@MainActor func testPresetsCoverStationaryDimension() {
    let hasStationary = StrategyPreset.allCases.contains {
        $0.collectionBehavior.contains(.stationary)
    }
    assert(hasStationary, "At least one preset must include .stationary")
}

@MainActor func testPresetsCoverMoveToActiveSpaceDimension() {
    let hasMoveToActiveSpace = StrategyPreset.allCases.contains {
        $0.collectionBehavior.contains(.moveToActiveSpace)
    }
    assert(hasMoveToActiveSpace, "At least one preset must include .moveToActiveSpace")
}

@MainActor func testPresetsCoverFullScreenAuxiliaryDimension() {
    let hasFullScreenAux = StrategyPreset.allCases.contains {
        $0.collectionBehavior.contains(.fullScreenAuxiliary)
    }
    assert(hasFullScreenAux, "At least one preset must include .fullScreenAuxiliary")
}

@MainActor func testPresetsCoverCanJoinAllSpacesPresent() {
    let hasJoinAll = StrategyPreset.allCases.contains {
        $0.collectionBehavior.contains(.canJoinAllSpaces)
    }
    assert(hasJoinAll, "At least one preset must include .canJoinAllSpaces")
}

@MainActor func testPresetsCoverCanJoinAllSpacesAbsent() {
    let hasNoJoinAll = StrategyPreset.allCases.contains {
        !$0.collectionBehavior.contains(.canJoinAllSpaces)
    }
    assert(hasNoJoinAll, "At least one preset must omit .canJoinAllSpaces")
}

@MainActor func testPresetsCoverKeyEligible() {
    let hasKeyEligible = StrategyPreset.allCases.contains { $0.isKeyEligible }
    assert(hasKeyEligible, "At least one preset must be key-eligible")
}

@MainActor func testPresetsCoverKeyIneligible() {
    let hasKeyIneligible = StrategyPreset.allCases.contains { !$0.isKeyEligible }
    assert(hasKeyIneligible, "At least one preset must be key-ineligible")
}

@MainActor func testNoPresetCombinesStationaryAndMoveToActiveSpace() {
    for preset in StrategyPreset.allCases {
        let hasStationary = preset.collectionBehavior.contains(.stationary)
        let hasMoveToActive = preset.collectionBehavior.contains(.moveToActiveSpace)
        assert(
            !(hasStationary && hasMoveToActive),
            "\(preset.identifier): must not combine .stationary and .moveToActiveSpace"
        )
    }
}

@MainActor func testNoPresetCombinesJoinAllSpacesAndMoveToActiveSpace() {
    for preset in StrategyPreset.allCases {
        let behavior = preset.collectionBehavior
        assert(
            !(behavior.contains(.canJoinAllSpaces) && behavior.contains(.moveToActiveSpace)),
            "\(preset.identifier): must not combine .canJoinAllSpaces and .moveToActiveSpace"
        )
    }
}

@MainActor func testPresetBehaviorsMatchExpectedFlags() {
    let expected: [StrategyPreset: NSWindow.CollectionBehavior] = [
        .normalBaseline: [],
        .desktopCandidate: [.canJoinAllSpaces, .stationary, .ignoresCycle],
        .desktopCandidateNoJoinAllSpaces: [.stationary, .ignoresCycle],
        .desktopMoveToActiveSpace: [.moveToActiveSpace, .ignoresCycle],
        .desktopNoKey: [.canJoinAllSpaces, .stationary, .ignoresCycle],
        .desktopFullScreenAuxiliary: [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ],
    ]
    for preset in StrategyPreset.allCases {
        guard let expectedBehavior = expected[preset] else {
            assert(false, "\(preset.identifier): missing expected behavior")
            continue
        }
        assertEqual(
            preset.collectionBehavior,
            expectedBehavior,
            "\(preset.identifier): emitted behavior must match its reviewed preset contract"
        )
    }
}

@MainActor func testAllDesktopPresetsUseDesktopIconWindowPlusOne() {
    // Every non-normal preset should use the desktop candidate level.
    for preset in StrategyPreset.allCases where preset != .normalBaseline {
        assertEqual(
            preset.windowLevel, desktopIconWindowLevel,
            "\(preset.identifier): non-normal preset must use desktopIconWindow + 1"
        )
    }
}

@MainActor func testAllDesktopPresetsHaveIgnoresCycle() {
    // Every non-normal desktop preset should have .ignoresCycle.
    for preset in StrategyPreset.allCases where preset != .normalBaseline {
        assert(
            preset.collectionBehavior.contains(.ignoresCycle),
            "\(preset.identifier): desktop preset must have .ignoresCycle"
        )
    }
}

@MainActor func testWindowSubclassReportsConfiguredKeyEligibility() {
    let contentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
    let eligibleWindow = AlcoveSpikeWindow(
        contentRect: contentRect,
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
        isKeyEligible: true
    )
    let ineligibleWindow = AlcoveSpikeWindow(
        contentRect: contentRect,
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
        isKeyEligible: false
    )
    assert(eligibleWindow.canBecomeKey, "Key-eligible window must report canBecomeKey")
    assert(!ineligibleWindow.canBecomeKey, "Key-ineligible window must reject canBecomeKey")
}

@MainActor func testControllerSignalsWindowClose() {
    _ = NSApplication.shared
    let controller = ExperimentWindowController(preset: .normalBaseline)
    var closeCallbackCount = 0
    controller.onWindowWillClose = {
        closeCallbackCount += 1
    }
    controller.close()
    assertEqual(
        closeCallbackCount,
        1,
        "Controller must notify its owner exactly once when the window closes"
    )
}

// MARK: - Run All Tests

print("=== Alcove Spike 0.1B — Strategy Model Tests ===")
print("")

testPresetIdentifiersAreUnique()
testPresetNamesAreUnique()
testNormalBaselineHasNormalLevelAndMinimalBehavior()
testDesktopCandidateRetainsPhase01AProperties()
testCollectionBehaviorMatchesTypedConfiguration()
testWindowLevelMatchesTypedConfiguration()
testKeyEligibilityMatchesTypedConfiguration()
testPresetsCoverStationaryDimension()
testPresetsCoverMoveToActiveSpaceDimension()
testPresetsCoverFullScreenAuxiliaryDimension()
testPresetsCoverCanJoinAllSpacesPresent()
testPresetsCoverCanJoinAllSpacesAbsent()
testPresetsCoverKeyEligible()
testPresetsCoverKeyIneligible()
testNoPresetCombinesStationaryAndMoveToActiveSpace()
testNoPresetCombinesJoinAllSpacesAndMoveToActiveSpace()
testPresetBehaviorsMatchExpectedFlags()
testAllDesktopPresetsUseDesktopIconWindowPlusOne()
testAllDesktopPresetsHaveIgnoresCycle()
testWindowSubclassReportsConfiguredKeyEligibility()
testControllerSignalsWindowClose()

print("")
print("=== Results: \(passed) passed, \(failed) failed ===")

if failed > 0 {
    print("TESTS FAILED")
    exit(1)
} else {
    print("ALL TESTS PASSED")
    exit(0)
}
