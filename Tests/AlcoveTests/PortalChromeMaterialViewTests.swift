import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

final class PortalChromeMaterialViewTests: XCTestCase {
    @MainActor
    func testSurfaceCornerRadiusUpdatesTheGlassWithoutRebuilding() throws {
        let view = PortalChromeMaterialView(
            contentView: NSView(),
            notificationCenter: NotificationCenter()
        )
        let rebuildCount = view.rebuildCount

        view.updateCornerRadius(8)

        let glass = try XCTUnwrap(view.materialView as? NSGlassEffectView)
        XCTAssertEqual(view.layer?.cornerRadius, 8)
        XCTAssertEqual(glass.cornerRadius, 8)
        XCTAssertEqual(view.rebuildCount, rebuildCount)
    }

    func testResolverUsesGlassUnlessReduceTransparencyRequiresOpaqueMaterial() {
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(accessibility: .standard),
            .glass
        )
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(accessibility: .reduced),
            .opaque
        )
    }

    @MainActor
    func testAccessibilityChangesRebuildBetweenGlassAndOpaqueMaterial() throws {
        let content = NSView()
        let options = AccessibilityOptionsBox(.standard)
        let host = PortalChromeMaterialView(
            contentView: content,
            backgroundStyle: .lowTransparency,
            accessibilityProvider: { options.value },
            notificationCenter: NotificationCenter()
        )
        let originalGlass = try XCTUnwrap(host.materialView as? NSGlassEffectView)
        let initialConstraintCount = host.constraints.count
        XCTAssertTrue(content.isDescendant(of: originalGlass))

        options.value = .reduced
        host.rebuildMaterial()

        XCTAssertNil(originalGlass.superview)
        XCTAssertEqual(host.constraints.count, initialConstraintCount)
        XCTAssertEqual(host.materialPath, .opaque)
        XCTAssertFalse(host.materialView is NSGlassEffectView)
        XCTAssertTrue(content.isDescendant(of: try XCTUnwrap(host.materialView)))
        XCTAssertEqual(host.layer?.borderWidth, 2)
        XCTAssertTrue(host.accessibility.reduceMotion)

        options.value = .standard
        host.rebuildMaterial()

        let restoredGlass = try XCTUnwrap(host.materialView as? NSGlassEffectView)
        XCTAssertEqual(host.materialPath, .glass)
        XCTAssertEqual(restoredGlass.style, .regular)
        XCTAssertEqual(try tintColor(of: restoredGlass).alphaComponent, 0.12, accuracy: 0.001)
    }

    @MainActor
    func testAccessibilityNotificationRebuildsAndStopRejectsQueuedDelivery() async {
        let center = NotificationCenter()
        let options = AccessibilityOptionsBox(.standard)
        let host = PortalChromeMaterialView(
            contentView: NSView(),
            accessibilityProvider: { options.value },
            notificationCenter: center
        )
        let initialCount = host.rebuildCount
        options.value = .reduced

        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        await Task.yield()

        XCTAssertEqual(host.rebuildCount, initialCount + 1)
        XCTAssertEqual(host.materialPath, .opaque)

        center.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        host.stopObserving()
        await Task.yield()
        XCTAssertEqual(host.rebuildCount, initialCount + 1)
    }

    @MainActor
    func testPortalSurfaceUsesUntintedNativeGlassByDefault() throws {
        let host = PortalChromeMaterialView(
            contentView: NSView(),
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )

        let glass = try XCTUnwrap(host.materialView as? NSGlassEffectView)
        XCTAssertEqual(host.materialPath, .glass)
        XCTAssertEqual(glass.style, .regular)
        XCTAssertNil(glass.tintColor)
        XCTAssertEqual(glass.cornerRadius, 24)
        XCTAssertEqual(host.alphaValue, 1, accuracy: 0.001)
    }

    @MainActor
    func testPortalGlassMapsEveryBackgroundStyleAndBuiltInTint() throws {
        let surface = PortalChromeMaterialView(
            contentView: NSView(),
            backgroundStyle: .maximumTransparency,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )
        let glass = try XCTUnwrap(surface.materialView as? NSGlassEffectView)

        XCTAssertEqual(glass.style, .clear)
        XCTAssertNil(glass.tintColor)
        surface.updateBackgroundStyle(.highTransparency)
        XCTAssertEqual(glass.style, .clear)
        XCTAssertEqual(try tintColor(of: glass).alphaComponent, 0.06, accuracy: 0.001)
        surface.updateBackgroundStyle(.standard)
        XCTAssertEqual(glass.style, .regular)
        XCTAssertNil(glass.tintColor)
        surface.updateBackgroundStyle(.lowTransparency)
        XCTAssertEqual(try tintColor(of: glass).alphaComponent, 0.12, accuracy: 0.001)
        surface.updateBackgroundStyle(.minimumTransparency)
        XCTAssertEqual(try tintColor(of: glass).alphaComponent, 0.20, accuracy: 0.001)

        surface.updatePortalTint(.blue)
        let blue = try tintColor(of: glass)
        XCTAssertEqual(blue.blueComponent, 1, accuracy: 0.001)
        XCTAssertEqual(blue.alphaComponent, 0.34, accuracy: 0.001)
    }

    @MainActor
    func testReduceTransparencyMakesEverySurfaceStyleOpaque() {
        for backgroundStyle in PortalBackgroundStyle.allCases {
            let surface = PortalChromeMaterialView(
                contentView: NSView(),
                backgroundStyle: backgroundStyle,
                accessibilityProvider: { .reduced },
                notificationCenter: NotificationCenter()
            )

            XCTAssertEqual(surface.materialPath, .opaque)
            XCTAssertEqual(surface.alphaValue, 1, accuracy: 0.001)
            XCTAssertFalse(surface.materialView is NSGlassEffectView)
        }
    }

    @MainActor
    func testSurfaceTintAdaptsBetweenNeutralLightAndDarkColors() throws {
        let surface = PortalChromeMaterialView(
            contentView: NSView(),
            backgroundStyle: .lowTransparency,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )
        let glass = try XCTUnwrap(surface.materialView as? NSGlassEffectView)
        surface.appearance = NSAppearance(named: .aqua)
        surface.viewDidChangeEffectiveAppearance()
        let light = try tintColor(of: glass)

        surface.appearance = NSAppearance(named: .darkAqua)
        surface.viewDidChangeEffectiveAppearance()
        let dark = try tintColor(of: glass)

        XCTAssertEqual(light.redComponent, 0.72, accuracy: 0.001)
        XCTAssertEqual(dark.redComponent, 0.18, accuracy: 0.001)
        XCTAssertEqual(light.alphaComponent, 0.12, accuracy: 0.001)
        XCTAssertEqual(dark.alphaComponent, 0.12, accuracy: 0.001)
    }

    @MainActor
    func testPortalTintChangesHueWithoutReplacingTheGlass() throws {
        let surface = PortalChromeMaterialView(
            contentView: NSView(),
            backgroundStyle: .lowTransparency,
            portalTint: .red,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )
        let material = surface.materialView
        let glass = try XCTUnwrap(material as? NSGlassEffectView)
        let red = try tintColor(of: glass)
        XCTAssertGreaterThan(red.redComponent, red.greenComponent)
        XCTAssertEqual(red.alphaComponent, 0.26, accuracy: 0.001)

        surface.updatePortalTint(.blue)

        let blue = try tintColor(of: glass)
        XCTAssertGreaterThan(blue.blueComponent, blue.redComponent)
        XCTAssertTrue(surface.materialView === material)
    }

    @MainActor
    private func tintColor(of glass: NSGlassEffectView) throws -> NSColor {
        let tint = try XCTUnwrap(glass.tintColor)
        return try XCTUnwrap(tint.usingColorSpace(.sRGB))
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
