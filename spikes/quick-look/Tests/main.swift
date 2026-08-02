// main.swift
// Structural and non-visual integration tests for Alcove Spike 0.3A.

import AppKit
import Foundation
import Quartz

@MainActor
final class AlternatePanelParticipant: NSObject,
    @MainActor QLPreviewPanelDataSource,
    @MainActor QLPreviewPanelDelegate
{
    private let item = UnavailablePreviewItem()

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem {
        item
    }
}

@MainActor
final class TestRunner {
    private var passed = 0
    private var failed = 0
    private var failureMessages: [String] = []

    func run() -> (exitCode: Int32, report: String) {
        testFixtureStoreLifecycle()
        testFixtureStoreRejectsUnsafeNames()
        testOrderedSelectionProjection()
        testPreviewDataSourceBounds()
        testSpacePolicy()
        testSpaceKeyNoSelection()
        testWindowStrategies()
        testResponderChainInstallation()
        testPanelControllerIntegration()
        testPanelReferenceCleanupPreservesOtherOwner()

        let summary = failureMessages + ["Tests passed: \(passed)", "Tests failed: \(failed)"]
        summary.forEach { Swift.print($0) }
        return (failed == 0 ? 0 : 1, summary.joined(separator: "\n") + "\n")
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            failureMessages.append("FAIL: \(message)")
        }
    }

    private func makeStore(_ names: [String] = ["a.txt", "b.md", "c.rtf"]) -> PreviewFixtureStore? {
        do {
            return try PreviewFixtureStore.create(names.map { ($0, "fixture: \($0)") })
        } catch {
            failed += 1
            failureMessages.append("FAIL: fixture setup failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func testFixtureStoreLifecycle() {
        guard let store = makeStore() else { return }
        expect(store.fixtures.count == 3, "store should create every requested fixture")
        expect(store.fixtures.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) },
               "all fixture files should exist")
        let directory = store.fixtures[0].url.deletingLastPathComponent()

        do {
            try store.cleanup()
            expect(!FileManager.default.fileExists(atPath: directory.path),
                   "cleanup should remove the session directory")
            try store.cleanup()
            expect(true, "cleanup should be idempotent")
        } catch {
            failed += 1
            failureMessages.append("FAIL: fixture cleanup failed: \(error.localizedDescription)")
        }
    }

    private func testFixtureStoreRejectsUnsafeNames() {
        do {
            _ = try PreviewFixtureStore.create([("../escape.txt", "unsafe")])
            expect(false, "fixture store should reject path traversal")
        } catch PreviewFixtureStoreError.invalidFileName {
            expect(true, "fixture store rejects path traversal")
        } catch {
            expect(false, "fixture store returned the wrong validation error")
        }
    }

    private func testOrderedSelectionProjection() {
        guard let store = makeStore() else { return }
        defer { cleanup(store) }
        let responder = QuickLookResponder()
        responder.setFixtures(store.fixtures)

        responder.setSelectedIndices([])
        expect(responder.selectedPreviewItems.isEmpty, "empty selection should project no items")

        responder.setSelectedIndices([2, 0, 2, -1, 99])
        expect(responder.selectedIndices == [0, 2], "selection should be unique visual index order")
        expect(responder.selectedPreviewItems.map(\.fixtureTitle) == ["a.txt", "c.rtf"],
               "preview items should follow collection order")

        responder.setFixtures([])
        expect(responder.selectedIndices.isEmpty, "fixture replacement should clear selection")
        expect(responder.selectedPreviewItems.isEmpty, "fixture replacement should clear preview snapshot")
    }

    private func testPreviewDataSourceBounds() {
        guard let store = makeStore(["only.txt"]) else { return }
        defer { cleanup(store) }
        let responder = QuickLookResponder()
        responder.setFixtures(store.fixtures)
        responder.setSelectedIndices([0])

        expect(responder.numberOfPreviewItems(in: nil) == 1, "data source count should match selection")
        let valid = responder.previewPanel(nil, previewItemAt: 0)
        expect(valid.previewItemURL == store.fixtures[0].url, "valid preview index should map to fixture URL")
        let invalid = responder.previewPanel(nil, previewItemAt: 7)
        expect(invalid.previewItemURL == nil, "out-of-range preview index should return safe placeholder")
    }

    private func testSpacePolicy() {
        guard let store = makeStore(["only.txt"]) else { return }
        defer { cleanup(store) }
        let responder = QuickLookResponder()
        expect(responder.spaceAction(panelIsVisible: false) == .noOp,
               "Space without selection should be a no-op")

        responder.setFixtures(store.fixtures)
        responder.setSelectedIndices([0])
        expect(responder.spaceAction(panelIsVisible: false) == .present,
               "Space with selection and hidden panel should present")
        expect(responder.spaceAction(panelIsVisible: true) == .dismiss,
               "Space with selection and visible panel should dismiss")
    }

    private func testSpaceKeyNoSelection() {
        let responder = QuickLookResponder()
        let controller = CollectionViewController(quickLookResponder: responder)
        _ = controller.view
        guard let collectionView = controller.collectionView else {
            expect(false, "collection view should be created")
            return
        }
        var presentationRequests = 0
        responder.onPresentationRequested = { presentationRequests += 1 }

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ) else {
            expect(false, "Space key event should be constructible")
            return
        }
        collectionView.keyDown(with: event)
        expect(presentationRequests == 0, "Space event without selection should not request presentation")
    }

    private func testWindowStrategies() {
        expect(PreviewWindowLevelStrategy.normal.level == .normal,
               "normal strategy should use normal level")
        let expected = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        expect(PreviewWindowLevelStrategy.desktopCandidate.level.rawValue == expected,
               "desktop candidate should be desktop-icon level plus one")
    }

    private func testResponderChainInstallation() {
        _ = NSApplication.shared
        let window = makeWindow()
        let original = window.nextResponder
        let expectedNextResponder = original ?? NSApp
        let responder = QuickLookResponder()
        window.installQuickLookResponder(responder)

        expect(window.nextResponder === responder, "window should point to installed Quick Look responder")
        expect(responder.nextResponder === expectedNextResponder,
               "responder should preserve or establish the application link")
        expect(chainContainsExactlyOnce(responder, startingAt: window),
               "responder chain should contain Quick Look responder exactly once without a cycle")
        expect(chainReachesApplication(startingAt: window), "responder chain should reach NSApplication")

        window.uninstallQuickLookResponder()
        expect(window.nextResponder === expectedNextResponder,
               "uninstall should restore the effective original responder")
        expect(responder.nextResponder == nil, "uninstall should detach responder")
        window.close()
    }

    private func testPanelControllerIntegration() {
        guard let store = makeStore() else { return }
        defer { cleanup(store) }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let window = makeWindow()
        let responder = QuickLookResponder()
        responder.setFixtures(store.fixtures)
        responder.setSelectedIndices([0, 2])
        let contentController = CollectionViewController(quickLookResponder: responder)
        window.contentViewController = contentController
        window.installQuickLookResponder(responder)
        application.activate()
        window.makeKeyAndOrderFront(nil)
        contentController.focusCollection(in: window)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        expect(window.isKeyWindow, "integration window should become key before Quick Look presentation")

        guard let panel = QLPreviewPanel.shared() else {
            expect(false, "shared preview panel should exist")
            window.close()
            return
        }
        responder.requestPresentation()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        expect(panel.isVisible, "presentation request should make the shared panel visible")
        panel.updateController()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        if let firstResponder = window.firstResponder {
            expect(chainContainsExactlyOnce(responder, startingAt: firstResponder),
                   "real first-responder chain should contain Quick Look responder")
            expect(chainReachesApplication(startingAt: firstResponder),
                   "real first-responder chain should reach NSApplication")
        } else {
            expect(false, "integration window should have a first responder")
        }
        expect(panel.currentController as AnyObject === responder,
               "system panel update should discover responder from the key window")
        expect(panel.dataSource === responder, "system begin-control callback should assign data source")
        expect(panel.delegate === responder, "system begin-control callback should assign delegate")
        expect(responder.controlledPanel === panel, "responder should track the panel it controls")

        panel.currentPreviewItemIndex = 1
        responder.setSelectedIndices([1])
        expect(responder.selectedPreviewItems.map(\.fixtureTitle) == ["b.md"],
               "selection replacement should update the data-source snapshot")
        expect(panel.currentPreviewItemIndex == 0,
               "selection replacement should repair an out-of-range current index")

        window.uninstallQuickLookResponder()
        panel.updateController()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        responder.teardownPanelState()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        expect(panel.dataSource == nil, "normal end-control should clear the assigned data source")
        expect(panel.delegate == nil, "normal end-control should clear the assigned delegate")
        responder.teardownPanelState()
        expect(responder.selectedPreviewItems.isEmpty, "panel teardown should be idempotent")
        window.close()
    }

    private func testPanelReferenceCleanupPreservesOtherOwner() {
        guard let panel = QLPreviewPanel.shared() else {
            expect(false, "shared preview panel should exist for reference cleanup test")
            return
        }
        let responder = QuickLookResponder()
        let alternate = AlternatePanelParticipant()
        panel.dataSource = alternate
        panel.delegate = alternate
        responder.releasePanelReferencesIfOwned(panel)

        expect(panel.dataSource === alternate,
               "reference cleanup must not clear a data source replaced by another owner")
        expect(panel.delegate === alternate,
               "reference cleanup must not clear a delegate replaced by another owner")
        panel.dataSource = nil
        panel.delegate = nil
    }

    private func makeWindow() -> SpikeWindow {
        SpikeWindow(
            contentRect: NSRect(x: 40, y: 40, width: 240, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }

    private func cleanup(_ store: PreviewFixtureStore) {
        do {
            try store.cleanup()
        } catch {
            failed += 1
            failureMessages.append("FAIL: fixture cleanup failed: \(error.localizedDescription)")
        }
    }

    private func chainContainsExactlyOnce(_ target: NSResponder, startingAt start: NSResponder) -> Bool {
        var current: NSResponder? = start
        var visited = Set<ObjectIdentifier>()
        var count = 0
        while let responder = current {
            let identifier = ObjectIdentifier(responder)
            guard visited.insert(identifier).inserted else { return false }
            if responder === target { count += 1 }
            current = responder.nextResponder
        }
        return count == 1
    }

    private func chainReachesApplication(startingAt start: NSResponder) -> Bool {
        var current: NSResponder? = start
        var visited = Set<ObjectIdentifier>()
        while let responder = current {
            let identifier = ObjectIdentifier(responder)
            guard visited.insert(identifier).inserted else { return false }
            if responder === NSApp { return true }
            current = responder.nextResponder
        }
        return false
    }
}

_ = NSApplication.shared
let result = MainActor.assumeIsolated {
    TestRunner().run()
}
let arguments = CommandLine.arguments
if let resultFlagIndex = arguments.firstIndex(of: "--result"),
   arguments.indices.contains(resultFlagIndex + 1)
{
    let resultURL = URL(fileURLWithPath: arguments[resultFlagIndex + 1])
    do {
        try "exit_code=\(result.exitCode)\n\(result.report)".write(
            to: resultURL,
            atomically: true,
            encoding: .utf8
        )
    } catch {
        Swift.print("Unable to write test result: \(error.localizedDescription)")
        exit(2)
    }
}
exit(result.exitCode)
