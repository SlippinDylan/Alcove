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
    private var failureMessages: [String] = []

    func run() -> Int32 {
        testResolutionMatrix()
        testGlassConstruction()
        testFrostedConstruction()
        testOpaqueConstruction()
        testChromeCallbacksRemainStateless()
        testAccessibilityObserverLifecycle()
        testCloseStopsObserver()
        testWindowLevels()
        testAppDelegateRecreateOwnership()

        failureMessages.forEach { Swift.print($0) }
        Swift.print("Assertions passed: \(passed)")
        Swift.print("Assertions failed: \(failed)")
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

    private func testResolutionMatrix() {
        let standard = AccessibilityDisplayOptions(
            reduceTransparency: false,
            increaseContrast: false
        )
        let contrast = AccessibilityDisplayOptions(
            reduceTransparency: false,
            increaseContrast: true
        )
        let reduced = AccessibilityDisplayOptions(
            reduceTransparency: true,
            increaseContrast: false
        )

        expect(
            MaterialResolver.resolve(
                backgroundType: .liquidGlass,
                accessibility: standard
            ) == .glass,
            "macOS 26+ should use Glass by default"
        )
        expect(
            MaterialResolver.resolve(
                backgroundType: .frostedGlass,
                accessibility: standard
            ) == .frosted,
            "Frosted Glass should select the standard material path"
        )
        expect(
            MaterialResolver.resolve(
                backgroundType: .liquidGlass,
                accessibility: contrast
            ) == .glass,
            "Increase Contrast should retain the Glass path"
        )
        expect(
            MaterialResolver.resolve(
                backgroundType: .frostedGlass,
                accessibility: reduced
            ) == .opaqueAccessibility,
            "Reduce Transparency should select the opaque accessibility path"
        )
    }

    private func testFrostedConstruction() {
        let options = AccessibilityDisplayOptions(
            reduceTransparency: false,
            increaseContrast: false
        )
        let controller = MaterialWindowController(
            backgroundType: .frostedGlass,
            accessibilityProvider: { options }
        )
        defer { controller.close() }

        guard let effect = controller.materialContainer as? NSVisualEffectView,
              let chrome = controller.chromeView,
              let canvas = controller.canvasView else {
            expect(false, "Frosted Glass should construct a visual effect and canvas")
            return
        }
        expect(controller.resolvedPath == .frosted, "Frosted path should be reported")
        expect(effect.material == .underWindowBackground, "Frosted path should use window material")
        expect(effect.blendingMode == .behindWindow, "Frosted path should sample behind the window")
        expect(effect.state == .active, "Frosted path should remain active on the desktop")
        expect(chrome.isDescendant(of: effect), "chrome should remain inside the frosted material")
        expect(!canvas.isDescendant(of: effect), "file canvas should stay outside spike chrome")
    }

    private func testGlassConstruction() {
        let options = AccessibilityDisplayOptions(
            reduceTransparency: false,
            increaseContrast: false
        )
        let controller = MaterialWindowController(accessibilityProvider: { options })
        defer { controller.close() }

        guard let container = controller.materialContainer as? NSGlassEffectContainerView,
              let chrome = controller.chromeView,
              let canvas = controller.canvasView else {
            expect(false, "standard construction should produce Glass chrome and canvas")
            return
        }
        let glassViews = descendants(ofType: NSGlassEffectView.self, under: container)
        expect(controller.resolvedPath == .glass, "standard path should resolve to Glass")
        expect(glassViews.count == 2, "Glass container should group two effect descendants")
        expect(chrome.segmentedControl.isDescendant(of: container), "tabs should remain in Glass")
        expect(chrome.addButton.isDescendant(of: container), "buttons should remain in Glass")
        expect(!canvas.isDescendant(of: container), "file canvas should stay outside Glass")
        expect(
            chrome.groupContainers.allSatisfy { $0 is NSGlassEffectView },
            "each control group should use Glass"
        )
    }

    private func testOpaqueConstruction() {
        let options = AccessibilityDisplayOptions(
            reduceTransparency: true,
            increaseContrast: true
        )
        let controller = MaterialWindowController(accessibilityProvider: { options })
        defer { controller.close() }

        guard let opaque = controller.materialContainer as? OpaqueChromeBackgroundView,
              let chrome = controller.chromeView,
              let canvas = controller.canvasView else {
            expect(false, "Reduce Transparency should construct the opaque path")
            return
        }
        opaque.updateLayer()
        expect(controller.resolvedPath == .opaqueAccessibility, "opaque path should be reported")
        expect(opaque.isOpaque, "accessibility background should report opaque")
        expect(opaque.layer?.backgroundColor != nil, "opaque background should resolve a color")
        expect(chrome.isDescendant(of: opaque), "chrome should remain inside opaque background")
        expect(!canvas.isDescendant(of: opaque), "file canvas should stay outside opaque chrome")
    }

    private func testChromeCallbacksRemainStateless() {
        let chrome = MaterialChromeView()
        var addRequests = 0
        var closeRequests = 0
        chrome.onAddRequested = { addRequests += 1 }
        chrome.onCloseRequested = { closeRequests += 1 }
        chrome.addButton.performClick(nil)
        chrome.closeButton.performClick(nil)

        expect(addRequests == 1, "add control should emit one request")
        expect(closeRequests == 1, "close control should emit one request")
        expect(chrome.tabCount == 3, "material controls should not own tab state")
    }

    private func testAccessibilityObserverLifecycle() {
        let options = AccessibilityOptionsBox(AccessibilityDisplayOptions(
            reduceTransparency: false,
            increaseContrast: false
        ))
        let controller = MaterialWindowController(accessibilityProvider: { options.value })
        defer { controller.close() }
        var callbackWasOnMainThread = false
        controller.onAccessibilityChange = { callbackWasOnMainThread = Thread.isMainThread }

        options.value = AccessibilityDisplayOptions(
            reduceTransparency: true,
            increaseContrast: false
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        runMainLoop()
        expect(controller.accessibilityChangeCount == 1, "notification should deliver once")
        expect(callbackWasOnMainThread, "accessibility callback should run on the main thread")
        expect(controller.resolvedPath == .opaqueAccessibility, "notification should rebuild material")

        controller.stopAccessibilityObserver()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        runMainLoop()
        expect(controller.accessibilityChangeCount == 1, "stopped observer should reject delivery")
    }

    private func testCloseStopsObserver() {
        let controller = MaterialWindowController()
        expect(controller.isAccessibilityObserverActive, "new controller should own observation")
        controller.close()
        expect(!controller.isAccessibilityObserverActive, "close should cancel observation")
    }

    private func testWindowLevels() {
        let expectedDesktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        let controller = MaterialWindowController(levelCandidate: .normal)
        defer { controller.close() }
        expect(controller.window?.level == .normal, "controller should apply normal level")
        controller.setLevelCandidate(.desktopCandidate)
        expect(
            controller.window?.level.rawValue == expectedDesktopLevel,
            "controller should apply desktop candidate level"
        )
    }

    private func testAppDelegateRecreateOwnership() {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        delegate.setWindowLevel(.normal)
        delegate.setBackgroundType(.frostedGlass)
        delegate.createWindow()
        var firstController = delegate.controller
        let firstIdentity = firstController.map(ObjectIdentifier.init)
        delegate.createWindow()

        expect(
            delegate.controller.map(ObjectIdentifier.init) != firstIdentity,
            "recreate should replace the window controller"
        )
        expect(delegate.controller?.levelCandidate == .normal, "recreate should preserve level")
        expect(
            delegate.controller?.backgroundType == .frostedGlass,
            "recreate should preserve background type"
        )
        expect(firstController?.window == nil, "recreate should detach the old window")
        expect(
            firstController?.isAccessibilityObserverActive == false,
            "recreate should stop the old observer"
        )
        firstController = nil
        runMainLoop()

        delegate.controller?.close()
        runMainLoop()
        expect(delegate.controller == nil, "window close should clear delegate ownership")
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
