// main.swift
// Structural and non-visual integration tests for Alcove Spike 0.4A.

import AppKit
import CoreGraphics
import Foundation

@MainActor
final class AccessibilityOptionsBox {
    var value: AccessibilityDisplayOptions

    init(_ value: AccessibilityDisplayOptions) {
        self.value = value
    }
}

@MainActor
final class TestRunner {
    private var passed = 0
    private var failed = 0
    private var skipped = 0
    private var failureMessages: [String] = []

    func run() -> Int32 {
        testResolutionMatrix()
        testGlassConstruction()
        testVisualEffectConstruction()
        testOpaqueConstruction()
        testChromeCallbacksRemainStateless()
        testPreferenceRebuildAndDiagnostics()
        testAccessibilityObserverLifecycle()
        testCloseStopsObserver()
        testWindowLevels()
        testAppDelegateRecreateOwnership()

        failureMessages.forEach { Swift.print($0) }
        Swift.print("Assertions passed: \(passed)")
        Swift.print("Assertions failed: \(failed)")
        Swift.print("Tests skipped: \(skipped)")
        return failed == 0 ? 0 : 1
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            failureMessages.append("FAIL: \(message)")
        }
    }

    private func recordSkip(_ reason: String) {
        skipped += 1
        Swift.print("SKIP: \(reason)")
    }

    private func testResolutionMatrix() {
        let none = AccessibilityDisplayOptions(reduceTransparency: false, increaseContrast: false)
        let contrast = AccessibilityDisplayOptions(reduceTransparency: false, increaseContrast: true)
        let reduced = AccessibilityDisplayOptions(reduceTransparency: true, increaseContrast: false)
        let both = AccessibilityDisplayOptions(reduceTransparency: true, increaseContrast: true)

        expect(MaterialResolver.resolve(preference: .automatic, supportsGlass: true, accessibility: none) == .glass,
               "automatic mode should choose Glass when available")
        expect(MaterialResolver.resolve(preference: .automatic, supportsGlass: false, accessibility: none) == .visualEffect,
               "automatic mode should choose fallback when Glass is unavailable")
        expect(MaterialResolver.resolve(preference: .forceVisualEffectFallback, supportsGlass: true, accessibility: none) == .visualEffect,
               "forced fallback should ignore Glass availability")
        expect(MaterialResolver.resolve(preference: .forceVisualEffectFallback, supportsGlass: false, accessibility: none) == .visualEffect,
               "forced fallback should remain fallback without Glass")
        expect(MaterialResolver.resolve(preference: .automatic, supportsGlass: true, accessibility: reduced) == .opaqueAccessibility,
               "Reduce Transparency should choose the opaque path")
        expect(MaterialResolver.resolve(preference: .forceVisualEffectFallback, supportsGlass: false, accessibility: reduced) == .opaqueAccessibility,
               "Reduce Transparency should override forced fallback")
        expect(MaterialResolver.resolve(preference: .automatic, supportsGlass: true, accessibility: both) == .opaqueAccessibility,
               "Reduce Transparency should remain decisive when Increase Contrast is also enabled")
        expect(MaterialResolver.resolve(preference: .automatic, supportsGlass: true, accessibility: contrast) == .glass,
               "Increase Contrast alone should remain a diagnosed system option, not an unverified material switch")
        expect(contrast.increaseContrast, "Increase Contrast should be preserved in the input snapshot")
    }

    private func testGlassConstruction() {
        guard #available(macOS 26.0, *) else {
            recordSkip("Glass construction requires a macOS 26 runtime")
            return
        }
        let options = AccessibilityDisplayOptions(reduceTransparency: false, increaseContrast: false)
        let controller = MaterialWindowController(accessibilityProvider: { options })
        defer { controller.close() }

        guard let container = controller.materialContainer as? NSGlassEffectContainerView,
              let chrome = controller.chromeView,
              let canvas = controller.canvasView
        else {
            expect(false, "automatic macOS 26 construction should produce Glass container, chrome, and canvas")
            return
        }
        let glassViews = descendants(ofType: NSGlassEffectView.self, under: container)
        expect(controller.resolvedPath == .glass, "automatic runtime path should resolve to Glass")
        expect(glassViews.count == 2, "Glass container should group two real Glass effect descendants")
        expect(glassViews.allSatisfy { $0.contentView != nil }, "each Glass effect should own a content view")
        expect(chrome.segmentedControl.isDescendant(of: container), "tab controls should be inside the Glass container")
        expect(chrome.addButton.isDescendant(of: container), "button controls should be inside the Glass container")
        expect(!canvas.isDescendant(of: container), "file-content canvas should stay outside Glass")
        expect(chrome.groupContainers.allSatisfy { $0 is NSGlassEffectView },
               "each chrome control group should use a Glass wrapper")
        verifyEquivalentChromeLayout(controller)
    }

    private func testVisualEffectConstruction() {
        let options = AccessibilityDisplayOptions(reduceTransparency: false, increaseContrast: false)
        let controller = MaterialWindowController(
            preference: .forceVisualEffectFallback,
            accessibilityProvider: { options }
        )
        defer { controller.close() }

        guard let effect = controller.materialContainer as? NSVisualEffectView,
              let chrome = controller.chromeView,
              let canvas = controller.canvasView
        else {
            expect(false, "forced fallback should produce effect view, chrome, and canvas")
            return
        }
        expect(controller.resolvedPath == .visualEffect, "forced fallback should report the visual-effect path")
        expect(effect.material == .headerView, "fallback should use semantic header material")
        expect(effect.blendingMode == .behindWindow, "fallback should blend behind the window")
        expect(effect.state == .followsWindowActiveState, "fallback should follow window active state")
        expect(chrome.isDescendant(of: effect), "chrome should be inside the fallback effect")
        expect(!canvas.isDescendant(of: effect), "file-content canvas should stay outside fallback effect")
        expect(chrome.groupContainers.allSatisfy { !($0 is NSVisualEffectView) },
               "fallback should not stack an effect per control group")
        verifyEquivalentChromeLayout(controller)
    }

    private func testOpaqueConstruction() {
        let options = AccessibilityDisplayOptions(reduceTransparency: true, increaseContrast: true)
        let controller = MaterialWindowController(accessibilityProvider: { options })
        defer { controller.close() }

        expect(controller.materialContainer is OpaqueChromeBackgroundView,
               "Reduce Transparency should select the opaque background type")
        expect(!(controller.materialContainer is NSVisualEffectView),
               "opaque background should not be a visual-effect view")
        if #available(macOS 26.0, *) {
            expect(!(controller.materialContainer is NSGlassEffectContainerView),
                   "opaque background should not be a Glass container")
        }
        guard let opaque = controller.materialContainer as? OpaqueChromeBackgroundView,
              let chrome = controller.chromeView,
              let canvas = controller.canvasView
        else {
            expect(false, "Reduce Transparency should construct the explicit opaque path")
            return
        }
        opaque.updateLayer()
        expect(controller.resolvedPath == .opaqueAccessibility, "opaque controller should report accessibility path")
        expect(opaque.isOpaque, "accessibility background should explicitly report opaque")
        expect(opaque.layer?.backgroundColor != nil, "opaque background should resolve a dynamic layer color")
        expect(chrome.isDescendant(of: opaque), "chrome should remain inside the opaque background")
        expect(!canvas.isDescendant(of: opaque), "file-content canvas should stay outside opaque chrome")
        verifyEquivalentChromeLayout(controller)
    }

    private func testChromeCallbacksRemainStateless() {
        let chrome = MaterialChromeView()
        var addRequests = 0
        var closeRequests = 0
        chrome.onAddRequested = { addRequests += 1 }
        chrome.onCloseRequested = { closeRequests += 1 }
        chrome.addButton.performClick(nil)
        chrome.closeButton.performClick(nil)

        expect(addRequests == 1, "representative add control should emit one request")
        expect(closeRequests == 1, "representative close control should emit one request")
        expect(chrome.tabCount == 3, "material spike controls should not implement tab state")
    }

    private func testPreferenceRebuildAndDiagnostics() {
        let options = AccessibilityDisplayOptions(reduceTransparency: false, increaseContrast: true)
        let controller = MaterialWindowController(accessibilityProvider: { options })
        defer { controller.close() }
        guard let contentView = controller.window?.contentView,
              let originalMaterial = controller.materialContainer
        else {
            expect(false, "controller should have root and material views")
            return
        }
        let originalSubviewCount = contentView.subviews.count
        let observerWasActive = controller.isAccessibilityObserverActive
        controller.setPreference(.forceVisualEffectFallback)

        expect(originalMaterial.superview == nil, "preference rebuild should detach the old material view")
        expect(contentView.subviews.count == originalSubviewCount, "preference rebuild should not stack root views")
        expect(controller.materialContainer is NSVisualEffectView, "preference rebuild should construct fallback")
        expect(controller.isAccessibilityObserverActive == observerWasActive,
               "material rebuild should not duplicate or stop the observer")
        expect(controller.diagnosticsText.contains("Increase Contrast: true"),
               "diagnostics should expose Increase Contrast")
        expect(controller.diagnosticsText.contains("Preference: Force Visual Effect Fallback"),
               "diagnostics should expose current preference")
    }

    private func testAccessibilityObserverLifecycle() {
        let options = AccessibilityOptionsBox(
            AccessibilityDisplayOptions(reduceTransparency: false, increaseContrast: false)
        )
        let controller = MaterialWindowController(accessibilityProvider: { options.value })
        defer { controller.close() }
        var callbackWasOnMainThread = false
        controller.onAccessibilityChange = { callbackWasOnMainThread = Thread.isMainThread }

        controller.startAccessibilityObserver()
        expect(controller.isAccessibilityObserverActive, "observer start should be synchronous and idempotent")
        options.value = AccessibilityDisplayOptions(reduceTransparency: true, increaseContrast: false)
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        runMainLoop()
        expect(controller.accessibilityChangeCount == 1, "one workspace notification should deliver exactly once")
        expect(callbackWasOnMainThread, "accessibility callback should be delivered on MainActor/main thread")
        expect(controller.resolvedPath == .opaqueAccessibility, "notification should rebuild with updated options")

        controller.stopAccessibilityObserver()
        controller.stopAccessibilityObserver()
        expect(!controller.isAccessibilityObserverActive, "observer stop should be synchronous and idempotent")
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        runMainLoop()
        expect(controller.accessibilityChangeCount == 1, "stopped observer should not receive later notifications")

        controller.startAccessibilityObserver()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        controller.stopAccessibilityObserver()
        runMainLoop()
        expect(controller.accessibilityChangeCount == 1, "stop should invalidate a callback already queued for MainActor")
    }

    private func testCloseStopsObserver() {
        let controller = MaterialWindowController()
        expect(controller.isAccessibilityObserverActive, "new controller should own an active observation")
        controller.close()
        expect(!controller.isAccessibilityObserverActive, "explicit close should synchronously cancel observation")
    }

    private func testWindowLevels() {
        let expectedDesktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        expect(WindowLevelCandidate.normal.windowLevel == .normal, "normal candidate should use normal level")
        expect(WindowLevelCandidate.desktopCandidate.windowLevel.rawValue == expectedDesktopLevel,
               "desktop candidate should use desktop-icon level plus one")
        let controller = MaterialWindowController(levelCandidate: .normal)
        defer { controller.close() }
        expect(controller.window?.level == .normal, "controller should apply its initial normal level")
        controller.setLevelCandidate(.desktopCandidate)
        expect(controller.window?.level.rawValue == expectedDesktopLevel, "controller should apply switched desktop level")
        expect(controller.diagnosticsText.contains("Window Level: \(expectedDesktopLevel)"),
               "diagnostics should expose actual configured level")
    }

    private func testAppDelegateRecreateOwnership() {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.setMaterialPreference(.forceVisualEffectFallback)
        delegate.setWindowLevel(.normal)
        delegate.createWindow()
        guard delegate.controller != nil else {
            expect(false, "app delegate should strongly own its created controller")
            return
        }
        var firstController = delegate.controller
        let firstIdentity = firstController.map(ObjectIdentifier.init)
        delegate.createWindow()

        expect(delegate.controller.map(ObjectIdentifier.init) != firstIdentity,
               "recreate should replace the window controller")
        expect(delegate.controller?.preference == .forceVisualEffectFallback,
               "recreate should preserve selected material preference")
        expect(delegate.controller?.levelCandidate == .normal,
               "recreate should preserve selected window level")
        expect(firstController?.window == nil, "recreate should detach the previous controller from its window")
        expect(firstController?.isAccessibilityObserverActive == false,
               "recreate should stop the previous controller's observer")
        firstController = nil
        runMainLoop()

        delegate.controller?.close()
        runMainLoop()
        expect(delegate.controller == nil, "window close callback should clear app delegate ownership")
    }

    private func verifyEquivalentChromeLayout(_ controller: MaterialWindowController) {
        guard let chrome = controller.chromeView,
              let material = controller.materialContainer,
              let contentView = controller.window?.contentView
        else {
            expect(false, "equivalent-layout check requires chrome, material, and root")
            return
        }
        contentView.layoutSubtreeIfNeeded()
        expect(chrome.segmentedControl.segmentCount == 3, "each path should preserve representative tab roles")
        expect(chrome.addButton.title == "+" && chrome.closeButton.title == "–",
               "each path should preserve add and close control roles")
        expect(chrome.groupContainers.count == 2, "each path should preserve two chrome control groups")
        let hasHeightAnchor = material.constraints.contains { constraint in
            (constraint.firstItem as? NSView) === material
                && constraint.firstAttribute == .height
                && constraint.constant == 50
        }
        expect(hasHeightAnchor, "each material path should retain the same chrome height anchor")
    }

    private func descendants<T: NSView>(ofType type: T.Type, under root: NSView) -> [T] {
        root.subviews.flatMap { child -> [T] in
            let current = (child as? T).map { [$0] } ?? []
            return current + descendants(ofType: type, under: child)
        }
    }

    private func runMainLoop() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}

_ = NSApplication.shared
let exitCode = MainActor.assumeIsolated {
    TestRunner().run()
}
exit(exitCode)
