import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

final class PortalChromeMaterialViewTests: XCTestCase {
    @MainActor
    func testSurfaceCornerRadiusUpdatesWithoutRebuilding() throws {
        let view = makeSurface()
        let rebuildCount = view.rebuildCount

        view.updateCornerRadius(8)

        XCTAssertEqual(view.layer?.cornerRadius, 8)
        XCTAssertEqual(try XCTUnwrap(view.materialView).layer?.cornerRadius, 8)
        XCTAssertEqual(view.rebuildCount, rebuildCount)
    }

    func testResolverUsesStaticTranslucencyUnlessReduceTransparencyRequiresOpaqueSurface() {
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(accessibility: .standard),
            .translucent
        )
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(accessibility: .reduced),
            .opaque
        )
    }

    @MainActor
    func testAccessibilityChangesRebuildBetweenTranslucentAndOpaqueSurfaces() throws {
        let content = NSView()
        let options = AccessibilityOptionsBox(.standard)
        let host = PortalChromeMaterialView(
            contentView: content,
            backgroundStyle: .lowTransparency,
            accessibilityProvider: { options.value },
            notificationCenter: NotificationCenter()
        )
        let originalSurface = try XCTUnwrap(host.materialView)
        let initialConstraintCount = host.constraints.count
        XCTAssertTrue(content.isDescendant(of: originalSurface))

        options.value = .reduced
        host.rebuildMaterial()

        XCTAssertNil(originalSurface.superview)
        XCTAssertEqual(host.constraints.count, initialConstraintCount)
        XCTAssertEqual(host.materialPath, .opaque)
        XCTAssertTrue(content.isDescendant(of: try XCTUnwrap(host.materialView)))
        XCTAssertEqual(host.layer?.borderWidth, 2)
        XCTAssertTrue(host.accessibility.reduceMotion)

        options.value = .standard
        host.rebuildMaterial()

        XCTAssertEqual(host.materialPath, .translucent)
        XCTAssertEqual(try surfaceColor(of: host).alphaComponent, 0.72, accuracy: 0.001)
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
    func testDefaultSurfaceIsStaticTranslucentAndContainsContent() throws {
        let content = NSView()
        let surface = PortalChromeMaterialView(
            contentView: content,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )
        surface.appearance = NSAppearance(named: .aqua)
        surface.viewDidChangeEffectiveAppearance()

        let material = try XCTUnwrap(surface.materialView)
        let color = try surfaceColor(of: surface)
        XCTAssertEqual(surface.materialPath, .translucent)
        XCTAssertFalse(material is NSGlassEffectView)
        XCTAssertFalse(material is NSVisualEffectView)
        XCTAssertTrue(content.isDescendant(of: material))
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 0.72, accuracy: 0.001)
    }

    @MainActor
    func testEveryTransparencyLevelUpdatesStaticSurfaceInPlace() throws {
        let surface = makeSurface(backgroundStyle: .maximumTransparency)
        let material = surface.materialView
        let expectedAlphas: [CGFloat] = [0.32, 0.42, 0.52, 0.62, 0.72, 0.72]

        for (style, expectedAlpha) in zip(PortalBackgroundStyle.allCases, expectedAlphas) {
            surface.updateBackgroundStyle(style)
            XCTAssertEqual(
                try surfaceColor(of: surface).alphaComponent,
                expectedAlpha,
                accuracy: 0.001
            )
            XCTAssertTrue(surface.materialView === material)
        }
    }

    @MainActor
    func testPortalTintChangesSubtleHueWithoutReplacingSurface() throws {
        let surface = makeSurface(backgroundStyle: .standard, portalTint: .red)
        let material = surface.materialView
        var color = try surfaceColor(of: surface)
        XCTAssertGreaterThan(color.redComponent, color.blueComponent)
        XCTAssertLessThan(color.redComponent - color.blueComponent, 0.25)
        XCTAssertEqual(color.alphaComponent, 0.62, accuracy: 0.001)

        surface.updatePortalTint(.blue)

        color = try surfaceColor(of: surface)
        XCTAssertGreaterThan(color.blueComponent, color.redComponent)
        XCTAssertTrue(surface.materialView === material)
    }

    @MainActor
    func testNeutralStaticSurfaceAdaptsBetweenLightAndDarkAppearances() throws {
        let surface = makeSurface(backgroundStyle: .standard)

        surface.appearance = NSAppearance(named: .aqua)
        surface.viewDidChangeEffectiveAppearance()
        let light = try surfaceColor(of: surface)

        surface.appearance = NSAppearance(named: .darkAqua)
        surface.viewDidChangeEffectiveAppearance()
        let dark = try surfaceColor(of: surface)

        XCTAssertEqual(light.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(dark.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(light.alphaComponent, 0.62, accuracy: 0.001)
        XCTAssertEqual(dark.alphaComponent, 0.62, accuracy: 0.001)
    }

    @MainActor
    func testReduceTransparencyMakesEverySurfaceStyleOpaque() {
        for backgroundStyle in PortalBackgroundStyle.allCases {
            let surface = makeSurface(
                backgroundStyle: backgroundStyle,
                accessibility: .reduced
            )

            XCTAssertEqual(surface.materialPath, .opaque)
            XCTAssertEqual(surface.alphaValue, 1, accuracy: 0.001)
            XCTAssertFalse(surface.materialView is NSGlassEffectView)
            XCTAssertFalse(surface.materialView is NSVisualEffectView)
        }
    }

    @MainActor
    private func makeSurface(
        backgroundStyle: PortalBackgroundStyle = .standard,
        portalTint: PortalTint = .default,
        accessibility: PortalAccessibilityOptions = .standard
    ) -> PortalChromeMaterialView {
        PortalChromeMaterialView(
            contentView: NSView(),
            backgroundStyle: backgroundStyle,
            portalTint: portalTint,
            accessibilityProvider: { accessibility },
            notificationCenter: NotificationCenter()
        )
    }

    @MainActor
    private func surfaceColor(of view: PortalChromeMaterialView) throws -> NSColor {
        let color = try XCTUnwrap(view.materialView?.layer?.backgroundColor)
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
