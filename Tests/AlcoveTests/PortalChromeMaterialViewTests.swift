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
            PortalChromeMaterialResolver.resolve(
                backgroundType: .liquidGlass,
                accessibility: .standard
            ),
            .glass
        )
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(
                backgroundType: .frostedGlass,
                accessibility: .standard
            ),
            .frosted
        )
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(
                backgroundType: .frostedGlass,
                accessibility: .reduced
            ),
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
    func testFrostedSurfaceUsesOneActiveBehindWindowMaterialBelowContent() throws {
        let content = NSView()
        let surface = PortalChromeMaterialView(
            contentView: content,
            backgroundType: .frostedGlass,
            backgroundStyle: .standard,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )

        let effect = try XCTUnwrap(surface.materialView as? NSVisualEffectView)
        let tint = try XCTUnwrap(surface.surfaceTintView)
        XCTAssertEqual(surface.materialPath, .frosted)
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(effect.blendingMode, .behindWindow)
        XCTAssertEqual(effect.state, .active)
        XCTAssertTrue(content.isDescendant(of: effect))
        XCTAssertNil(tint.hitTest(NSPoint(x: 4, y: 4)))
        XCTAssertLessThan(
            try XCTUnwrap(effect.subviews.firstIndex(of: tint)),
            try XCTUnwrap(effect.subviews.firstIndex(of: content))
        )
        let tintColor = try XCTUnwrap(tint.layer?.backgroundColor)
        XCTAssertEqual(tintColor.alpha, 0.36, accuracy: 0.001)
    }

    @MainActor
    func testDefaultFrostedTintUsesCleanAppearanceAdaptiveNeutrals() throws {
        let surface = PortalChromeMaterialView(
            contentView: NSView(),
            backgroundType: .frostedGlass,
            backgroundStyle: .standard,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )
        let tintView = try XCTUnwrap(surface.surfaceTintView)

        surface.appearance = NSAppearance(named: .aqua)
        var color = try frostedTintColor(of: tintView)
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 0.36, accuracy: 0.001)

        surface.appearance = NSAppearance(named: .darkAqua)
        color = try frostedTintColor(of: tintView)
        XCTAssertEqual(color.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 0.36, accuracy: 0.001)
    }

    @MainActor
    func testChangingBackgroundTypeReplacesMaterialWithoutChangingContent() throws {
        let content = NSView()
        let surface = PortalChromeMaterialView(
            contentView: content,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )
        let originalGlass = try XCTUnwrap(surface.materialView as? NSGlassEffectView)

        surface.updateBackgroundType(.frostedGlass)

        XCTAssertNil(originalGlass.superview)
        XCTAssertEqual(surface.materialPath, .frosted)
        XCTAssertTrue(content.isDescendant(
            of: try XCTUnwrap(surface.materialView as? NSVisualEffectView)
        ))
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
        for backgroundType in PortalBackgroundType.allCases {
            for backgroundStyle in PortalBackgroundStyle.allCases {
                let surface = PortalChromeMaterialView(
                    contentView: NSView(),
                    backgroundType: backgroundType,
                    backgroundStyle: backgroundStyle,
                    accessibilityProvider: { .reduced },
                    notificationCenter: NotificationCenter()
                )

                XCTAssertEqual(surface.materialPath, .opaque)
                XCTAssertEqual(surface.alphaValue, 1, accuracy: 0.001)
                XCTAssertFalse(surface.materialView is NSGlassEffectView)
                XCTAssertFalse(surface.materialView is NSVisualEffectView)
            }
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
    func testPortalTintAndMaterialStrengthUpdateFrostedOverlayInPlace() throws {
        let surface = PortalChromeMaterialView(
            contentView: NSView(),
            backgroundType: .frostedGlass,
            backgroundStyle: .standard,
            portalTint: .red,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )
        let material = surface.materialView
        let tintView = try XCTUnwrap(surface.surfaceTintView)
        var color = try frostedTintColor(of: tintView)
        XCTAssertGreaterThan(color.redComponent, color.blueComponent)
        XCTAssertEqual(color.alphaComponent, 0.16, accuracy: 0.001)

        surface.updatePortalTint(.blue)
        surface.updateBackgroundStyle(.lowTransparency)

        color = try frostedTintColor(of: tintView)
        XCTAssertGreaterThan(color.blueComponent, color.redComponent)
        XCTAssertEqual(color.alphaComponent, 0.26, accuracy: 0.001)
        XCTAssertTrue(surface.materialView === material)
    }

    @MainActor
    private func tintColor(of glass: NSGlassEffectView) throws -> NSColor {
        let tint = try XCTUnwrap(glass.tintColor)
        return try XCTUnwrap(tint.usingColorSpace(.sRGB))
    }

    @MainActor
    private func frostedTintColor(of view: NSView) throws -> NSColor {
        let color = try XCTUnwrap(view.layer?.backgroundColor)
        return try XCTUnwrap(NSColor(cgColor: color)?.usingColorSpace(.sRGB))
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
