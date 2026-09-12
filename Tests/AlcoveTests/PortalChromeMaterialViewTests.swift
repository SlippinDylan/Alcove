import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

final class PortalChromeMaterialViewTests: XCTestCase {
    func testResolverPrioritizesReduceTransparencyAndSelectsVersionFallback() {
        let standard = PortalAccessibilityOptions(
            reduceTransparency: false,
            increaseContrast: false,
            reduceMotion: false
        )
        let reduced = PortalAccessibilityOptions(
            reduceTransparency: true,
            increaseContrast: true,
            reduceMotion: true
        )

        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(
                role: .controlGroup,
                supportsGlass: true,
                accessibility: standard
            ),
            .glass
        )
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(
                role: .controlGroup,
                supportsGlass: false,
                accessibility: standard
            ),
            .visualEffect
        )
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(
                role: .controlGroup,
                supportsGlass: true,
                accessibility: reduced
            ),
            .opaque
        )
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(
                role: .surface,
                supportsGlass: true,
                accessibility: standard
            ),
            .visualEffect
        )
    }

    @MainActor
    func testFallbackAndOpaquePathsKeepContentInsideChromeBoundary() throws {
        let content = NSView()
        let options = AccessibilityOptionsBox(.standard)
        let host = PortalChromeMaterialView(
            contentView: content,
            accessibilityProvider: { options.value },
            supportsGlass: false,
            notificationCenter: NotificationCenter()
        )

        let effect = try XCTUnwrap(host.materialView as? NSVisualEffectView)
        let initialConstraintCount = host.constraints.count
        XCTAssertEqual(effect.material, .popover)
        XCTAssertEqual(effect.blendingMode, .behindWindow)
        XCTAssertEqual(effect.state, .active)
        XCTAssertTrue(content.isDescendant(of: effect))

        options.value = .reduced
        host.rebuildMaterial()

        XCTAssertNil(effect.superview)
        XCTAssertEqual(host.constraints.count, initialConstraintCount)
        XCTAssertEqual(host.materialPath, .opaque)
        XCTAssertFalse(host.materialView is NSVisualEffectView)
        XCTAssertTrue(content.isDescendant(of: try XCTUnwrap(host.materialView)))
        XCTAssertEqual(host.layer?.borderWidth, 2)
        XCTAssertTrue(host.accessibility.reduceMotion)
    }

    @MainActor
    func testAccessibilityNotificationRebuildsAndStopRejectsQueuedDelivery() async {
        let center = NotificationCenter()
        let options = AccessibilityOptionsBox(.standard)
        let host = PortalChromeMaterialView(
            contentView: NSView(),
            role: .surface,
            backgroundStyle: .lowTransparency,
            accessibilityProvider: { options.value },
            supportsGlass: false,
            notificationCenter: center
        )
        let initialCount = host.rebuildCount
        XCTAssertEqual(host.alphaValue, 0.78, accuracy: 0.001)
        options.value = .reduced

        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        await Task.yield()

        XCTAssertEqual(host.rebuildCount, initialCount + 1)
        XCTAssertEqual(host.materialPath, .opaque)
        XCTAssertEqual(host.alphaValue, 1, accuracy: 0.001)

        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        host.stopObserving()
        await Task.yield()
        XCTAssertEqual(host.rebuildCount, initialCount + 1)
    }

    @MainActor
    func testGlassPathUsesPublicGlassViewWhenRuntimeSupportsIt() throws {
        guard #available(macOS 26.0, *) else { return }
        let content = NSView()
        let host = PortalChromeMaterialView(
            contentView: content,
            accessibilityProvider: { .standard },
            supportsGlass: true,
            notificationCenter: NotificationCenter()
        )

        let glass = try XCTUnwrap(host.materialView as? NSGlassEffectView)
        XCTAssertTrue(content.isDescendant(of: glass))
        XCTAssertEqual(glass.cornerRadius, 999)
        XCTAssertEqual(glass.style, .regular)
    }

    @MainActor
    func testPortalSurfaceUsesAlwaysActiveBackgroundMaterial() throws {
        let host = PortalChromeMaterialView(
            contentView: NSView(),
            role: .surface,
            accessibilityProvider: { .standard },
            supportsGlass: true,
            notificationCenter: NotificationCenter()
        )

        let effect = try XCTUnwrap(host.materialView as? NSVisualEffectView)
        XCTAssertEqual(host.materialPath, .visualEffect)
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(effect.state, .active)
        XCTAssertEqual(effect.layer?.cornerRadius, 24)
        XCTAssertEqual(host.alphaValue, 0.55, accuracy: 0.001)
    }

    @MainActor
    func testPortalSurfaceMapsEveryBackgroundStyleWithoutDimmingControls() throws {
        let surface = PortalChromeMaterialView(
            contentView: NSView(),
            role: .surface,
            backgroundStyle: .highTransparency,
            accessibilityProvider: { .standard },
            supportsGlass: false,
            notificationCenter: NotificationCenter()
        )
        let controls = PortalChromeMaterialView(
            contentView: NSView(),
            role: .controlGroup,
            backgroundStyle: .highTransparency,
            accessibilityProvider: { .standard },
            supportsGlass: false,
            notificationCenter: NotificationCenter()
        )
        let effect = try XCTUnwrap(surface.materialView as? NSVisualEffectView)

        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(surface.alphaValue, 0.35, accuracy: 0.001)
        surface.updateBackgroundStyle(.standard)
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(surface.alphaValue, 0.55, accuracy: 0.001)
        surface.updateBackgroundStyle(.lowTransparency)
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(surface.alphaValue, 0.78, accuracy: 0.001)
        XCTAssertEqual(controls.alphaValue, 1, accuracy: 0.001)
    }

    @MainActor
    func testReduceTransparencyMakesEverySurfaceStyleOpaque() {
        for backgroundStyle in PortalBackgroundStyle.allCases {
            let surface = PortalChromeMaterialView(
                contentView: NSView(),
                role: .surface,
                backgroundStyle: backgroundStyle,
                accessibilityProvider: { .reduced },
                supportsGlass: false,
                notificationCenter: NotificationCenter()
            )

            XCTAssertEqual(surface.materialPath, .opaque)
            XCTAssertEqual(surface.alphaValue, 1, accuracy: 0.001)
        }
    }

    @MainActor
    func testSavedSurfaceStyleResumesAfterReduceTransparencyTurnsOff() throws {
        let options = AccessibilityOptionsBox(.reduced)
        let surface = PortalChromeMaterialView(
            contentView: NSView(),
            role: .surface,
            backgroundStyle: .lowTransparency,
            accessibilityProvider: { options.value },
            supportsGlass: false,
            notificationCenter: NotificationCenter()
        )
        XCTAssertEqual(surface.alphaValue, 1, accuracy: 0.001)

        options.value = .standard
        surface.rebuildMaterial()

        let effect = try XCTUnwrap(surface.materialView as? NSVisualEffectView)
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(surface.alphaValue, 0.78, accuracy: 0.001)
    }
}

@MainActor
private final class AccessibilityOptionsBox {
    var value: PortalAccessibilityOptions

    init(_ value: PortalAccessibilityOptions) {
        self.value = value
    }
}

private extension PortalAccessibilityOptions {
    static let standard = PortalAccessibilityOptions(
        reduceTransparency: false,
        increaseContrast: false,
        reduceMotion: false
    )

    static let reduced = PortalAccessibilityOptions(
        reduceTransparency: true,
        increaseContrast: true,
        reduceMotion: true
    )
}
