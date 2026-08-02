// StrategyPresetTests.swift
// Alcove Spike 0.1C — Structural strategy and window-class model tests.
// Compiles with WindowStrategy.swift, WindowClassCandidate.swift, and subclasses
// to verify model invariants without GUI.
//
// This test executable verifies structural properties of the strategy model
// and the window-class comparison model. It does NOT test GUI behavior, Spaces,
// Show Desktop, key-window activation, or any system-level transitions — those
// require manual verification.

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

// MARK: - Strategy Preset Tests (Phase 0.1B — preserved)

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
    for preset in StrategyPreset.allCases where preset != .normalBaseline {
        assertEqual(
            preset.windowLevel, desktopIconWindowLevel,
            "\(preset.identifier): non-normal preset must use desktopIconWindow + 1"
        )
    }
}

@MainActor func testAllDesktopPresetsHaveIgnoresCycle() {
    for preset in StrategyPreset.allCases where preset != .normalBaseline {
        assert(
            preset.collectionBehavior.contains(.ignoresCycle),
            "\(preset.identifier): desktop preset must have .ignoresCycle"
        )
    }
}

// MARK: - Phase 0.1B Window Subclass Tests (preserved)

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
    assert(eligibleWindow.canBecomeKey, "Key-eligible NSWindow must report canBecomeKey")
    assert(!ineligibleWindow.canBecomeKey, "Key-ineligible NSWindow must reject canBecomeKey")
}

@MainActor func testControllerSignalsWindowClose() {
    _ = NSApplication.shared
    let controller = ExperimentWindowController(preset: .normalBaseline, windowClass: .nsWindow)
    var closeCallbackCount = 0
    controller.onWindowWillClose = {
        closeCallbackCount += 1
    }
    controller.close()
    assertEqual(
        closeCallbackCount,
        1,
        "NSWindow controller must notify its owner exactly once when the window closes"
    )
}

// MARK: - Phase 0.1C Window Class Candidate Tests

func expectedRuntimeTypeName(for candidate: WindowClassCandidate) -> String {
    switch candidate {
    case .nsWindow: return "AlcoveSpikeWindow"
    case .nsPanel: return "AlcoveSpikePanel"
    }
}

@MainActor
func runtimeClassMatches(
    _ window: NSWindow?,
    candidate: WindowClassCandidate
) -> Bool {
    switch candidate {
    case .nsWindow: return window is AlcoveSpikeWindow
    case .nsPanel: return window is AlcoveSpikePanel
    }
}

@MainActor func testExactlyTwoClassCandidatesExist() {
    assertEqual(
        WindowClassCandidate.allCases.count, 2,
        "Exactly two window class candidates must exist"
    )
}

@MainActor func testClassCandidateIdentifiersAreUnique() {
    let identifiers = WindowClassCandidate.allCases.map { $0.identifier }
    let unique = Set(identifiers)
    assertEqual(
        identifiers.count, unique.count,
        "Window class candidate identifiers must be unique"
    )
}

@MainActor func testClassCandidateDisplayNamesAreUnique() {
    let names = WindowClassCandidate.allCases.map { $0.displayName }
    let unique = Set(names)
    assertEqual(
        names.count, unique.count,
        "Window class candidate display names must be unique"
    )
}

@MainActor func testFactoryCreatesCorrectRuntimeClass() {
    let expectedStyleMask: NSWindow.StyleMask = [
        .resizable, .titled, .closable, .miniaturizable,
    ]
    for windowClass in WindowClassCandidate.allCases {
        let controller = ExperimentWindowController(
            preset: .normalBaseline,
            windowClass: windowClass
        )
        assert(
            runtimeClassMatches(controller.window, candidate: windowClass),
            "Factory must create the concrete runtime type requested by \(windowClass.displayName)"
        )
        assertEqual(
            controller.window?.styleMask,
            expectedStyleMask,
            "Both class candidates must use the same reviewed style mask"
        )
        controller.close()
    }
}

@MainActor func testPanelSubclassReportsConfiguredKeyEligibility() {
    let contentRect = NSRect(x: 0, y: 0, width: 100, height: 100)
    let eligiblePanel = AlcoveSpikePanel(
        contentRect: contentRect,
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
        isKeyEligible: true
    )
    let ineligiblePanel = AlcoveSpikePanel(
        contentRect: contentRect,
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
        isKeyEligible: false
    )
    assert(eligiblePanel.canBecomeKey, "Key-eligible NSPanel must report canBecomeKey")
    assert(!ineligiblePanel.canBecomeKey, "Key-ineligible NSPanel must reject canBecomeKey")
}

@MainActor func testDiagnosticsLabelsComeFromClassCandidateNotStrategyLabel() {
    for windowClass in WindowClassCandidate.allCases {
        let controller = ExperimentWindowController(
            preset: .desktopCandidate,
            windowClass: windowClass
        )
        let diagnostics = DiagnosticsView()
        diagnostics.refresh(
            preset: controller.preset,
            windowClass: controller.windowClass,
            window: controller.window,
            actualCanBecomeKey: controller.window?.canBecomeKey ?? false,
            activationPolicy: NSApp.activationPolicy()
        )
        let output = diagnostics.attributedStringValue.string
        assert(
            output.contains("Window Class: \(windowClass.displayName)"),
            "Diagnostics must render the configured typed class label"
        )
        assert(
            output.contains("Window Type: \(expectedRuntimeTypeName(for: windowClass))"),
            "Diagnostics must render the actual concrete runtime type"
        )
        controller.close()
    }
}

@MainActor func testAllSixPresetsAvailableWithBothClasses() {
    // Every strategy preset must be constructible with either window class.
    // This verifies the enum cases cover the required set.
    assertEqual(
        StrategyPreset.allCases.count, 6,
        "All six strategy presets must remain available"
    )
    for windowClass in WindowClassCandidate.allCases {
        for preset in StrategyPreset.allCases {
            let controller = ExperimentWindowController(
                preset: preset, windowClass: windowClass
            )
            assert(
                controller.preset == preset,
                "\(windowClass.displayName) + \(preset.identifier): preset must be preserved"
            )
            assert(
                controller.windowClass == windowClass,
                "\(windowClass.displayName) + \(preset.identifier): window class must be preserved"
            )
            assert(
                runtimeClassMatches(controller.window, candidate: windowClass),
                "\(windowClass.displayName) + \(preset.identifier): factory runtime class must match"
            )
            controller.close()
        }
    }
}

@MainActor func testPanelExperimentalPropertiesAreApplied() {
    let controller = ExperimentWindowController(
        preset: .desktopCandidate,
        windowClass: .nsPanel
    )
    defer { controller.close() }
    guard let panel = controller.window as? AlcoveSpikePanel else {
        assert(false, "Panel candidate factory must return AlcoveSpikePanel")
        return
    }
    assert(!panel.isFloatingPanel, "Panel candidate must disable the floating-panel flag")
    assert(!panel.hidesOnDeactivate, "Panel candidate must request visibility on deactivation")
}

@MainActor func testBothClassesWithNormalBaseline() {
    _ = NSApplication.shared
    for windowClass in WindowClassCandidate.allCases {
        let controller = ExperimentWindowController(
            preset: .normalBaseline, windowClass: windowClass
        )
        let window = controller.window
        assertEqual(
            window?.level, .normal,
            "\(windowClass.displayName) + Normal Baseline: level must be .normal"
        )
        assert(
            window?.collectionBehavior.isEmpty == true,
            "\(windowClass.displayName) + Normal Baseline: collection behavior must be empty"
        )
        controller.close()
    }
}

@MainActor func testBothClassesWithDesktopCandidate() {
    _ = NSApplication.shared
    for windowClass in WindowClassCandidate.allCases {
        let controller = ExperimentWindowController(
            preset: .desktopCandidate, windowClass: windowClass
        )
        let window = controller.window
        assertEqual(
            window?.level, desktopIconWindowLevel,
            "\(windowClass.displayName) + Desktop Candidate: level must be desktopIconWindow + 1"
        )
        assert(
            window?.collectionBehavior.contains(.canJoinAllSpaces) == true,
            "\(windowClass.displayName) + Desktop Candidate: must have .canJoinAllSpaces"
        )
        assert(
            window?.collectionBehavior.contains(.stationary) == true,
            "\(windowClass.displayName) + Desktop Candidate: must have .stationary"
        )
        assert(
            window?.collectionBehavior.contains(.ignoresCycle) == true,
            "\(windowClass.displayName) + Desktop Candidate: must have .ignoresCycle"
        )
        controller.close()
    }
}

@MainActor func testBothClassesWithNoKeyPreset() {
    _ = NSApplication.shared
    for windowClass in WindowClassCandidate.allCases {
        let controller = ExperimentWindowController(
            preset: .desktopNoKey, windowClass: windowClass
        )
        let window = controller.window
        assert(
            window?.canBecomeKey == false,
            "\(windowClass.displayName) + Desktop (No Key): canBecomeKey must be false"
        )
        assertEqual(
            window?.level, desktopIconWindowLevel,
            "\(windowClass.displayName) + Desktop (No Key): level must be desktopIconWindow + 1"
        )
        assert(
            window?.collectionBehavior.contains(.canJoinAllSpaces) == true,
            "\(windowClass.displayName) + Desktop (No Key): must have .canJoinAllSpaces"
        )
        assert(
            window?.collectionBehavior.contains(.stationary) == true,
            "\(windowClass.displayName) + Desktop (No Key): must have .stationary"
        )
        controller.close()
    }
}

@MainActor func testControllerCloseFiresOnceForBothClasses() {
    _ = NSApplication.shared
    for windowClass in WindowClassCandidate.allCases {
        let controller = ExperimentWindowController(
            preset: .desktopCandidate, windowClass: windowClass
        )
        var closeCount = 0
        controller.onWindowWillClose = { closeCount += 1 }
        controller.close()
        assertEqual(
            closeCount, 1,
            "\(windowClass.displayName): close callback must fire exactly once"
        )
    }
}

// MARK: - Run All Tests

print("=== Alcove Spike 0.1C — Strategy & Window Class Model Tests ===")
print("")

// Phase 0.1B strategy preset tests (preserved)
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

// Phase 0.1B window subclass tests (preserved)
testWindowSubclassReportsConfiguredKeyEligibility()
testControllerSignalsWindowClose()

// Phase 0.1C window class candidate tests
testExactlyTwoClassCandidatesExist()
testClassCandidateIdentifiersAreUnique()
testClassCandidateDisplayNamesAreUnique()
testFactoryCreatesCorrectRuntimeClass()
testPanelSubclassReportsConfiguredKeyEligibility()
testDiagnosticsLabelsComeFromClassCandidateNotStrategyLabel()
testAllSixPresetsAvailableWithBothClasses()
testPanelExperimentalPropertiesAreApplied()
testBothClassesWithNormalBaseline()
testBothClassesWithDesktopCandidate()
testBothClassesWithNoKeyPreset()
testControllerCloseFiresOnceForBothClasses()

print("")
print("=== Results: \(passed) passed, \(failed) failed ===")

if failed > 0 {
    print("TESTS FAILED")
    exit(1)
} else {
    print("ALL TESTS PASSED")
    exit(0)
}
