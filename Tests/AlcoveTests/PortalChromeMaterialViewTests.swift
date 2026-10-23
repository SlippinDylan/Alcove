import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

final class PortalChromeMaterialViewTests: XCTestCase {
    @MainActor
    func testEveryStyleRendersItsBackgroundAcrossAppearancesAndOutputScales() throws {
        let expectedAlphas: [(PortalSurfaceStyle, CGFloat)] = [
            (.translucent, 0.72), (.matte, 1), (.smoke, 0.95),
            (.softTint, 1), (.gradient, 1), (.paper, 1), (.outline, 0.20),
        ]
        let surface = makeSurface(backgroundStyle: .lowTransparency)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            surface.appearance = NSAppearance(named: appearance)
            surface.viewDidChangeEffectiveAppearance()
            for outputScale: CGFloat in [1, 2] {
                for (style, alpha) in expectedAlphas {
                    surface.updateSurfaceStyle(style)
                    let raster = try PortalSurfaceRaster.render(surface, outputScale: outputScale)
                    let color = raster.color(x: raster.width / 2, y: raster.height / 2)
                    XCTAssertEqual(color.alphaComponent, alpha, accuracy: 0.001,
                                   "\(style) / \(appearance) / output \(outputScale)x")
                    if style == .matte {
                        XCTAssertEqual(color.redComponent, appearance == .aqua ? 0.955 : 0.105,
                                       accuracy: 0.001)
                    }
                }
            }
        }
    }

    @MainActor
    func testDecorationsRenderAndAreReplacedWhenReturningToTranslucency() throws {
        let surface = makeSurface(backgroundStyle: .standard)
        surface.appearance = NSAppearance(named: .darkAqua)
        surface.viewDidChangeEffectiveAppearance()
        surface.updateSurfaceStyle(.gradient)
        let gradient = try PortalSurfaceRaster.render(surface)
        let first = gradient.color(x: 32, y: 16)
        let second = gradient.color(x: 32, y: 48)
        XCTAssertGreaterThan(abs(first.redComponent - second.redComponent), 0.005)
        let resized = try PortalSurfaceRaster.render(surface, size: NSSize(width: 128, height: 128))
        XCTAssertEqual(resized.color(x: 64, y: 32).redComponent, first.redComponent, accuracy: 0.002)
        XCTAssertEqual(resized.color(x: 64, y: 96).redComponent, second.redComponent, accuracy: 0.002)

        surface.updateSurfaceStyle(.paper)
        let paper = try PortalSurfaceRaster.render(surface)
        let paperColors = (16..<48).flatMap { y in
            (16..<48).map { x in paper.color(x: x, y: y) }
        }
        XCTAssertTrue(paperColors.allSatisfy { abs($0.alphaComponent - 1) < 0.001 })
        let redComponents = paperColors.map(\.redComponent)
        XCTAssertGreaterThan(
            try XCTUnwrap(redComponents.max()) - XCTUnwrap(redComponents.min()), 0.002
        )

        for decoration in [PortalSurfaceStyle.gradient, .paper] {
            surface.updateSurfaceStyle(decoration)
            _ = try PortalSurfaceRaster.render(surface)
            surface.updateSurfaceStyle(.translucent)
            for _ in 0..<3 {
                surface.materialView?.needsDisplay = true
                let color = try surfaceColor(of: surface)
                XCTAssertEqual(color.alphaComponent, 0.62, accuracy: 0.001)
                XCTAssertEqual(color.redComponent, 0, accuracy: 0.001)
            }
        }
    }

    @MainActor
    func testSurfaceCornerRadiusUpdatesWithoutRebuilding() throws {
        let view = makeSurface()
        let rebuildCount = view.rebuildCount

        view.updateCornerRadius(8)

        XCTAssertEqual(view.layer?.cornerRadius, 8)
        XCTAssertEqual(try XCTUnwrap(view.materialView).layer?.cornerRadius, 8)
        XCTAssertEqual(view.rebuildCount, rebuildCount)
    }

    func testResolverUsesSelectedStyleUnlessReduceTransparencyRequiresOpaqueSurface() {
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(accessibility: .standard),
            .styled
        )
        XCTAssertEqual(
            PortalChromeMaterialResolver.resolve(accessibility: .reduced),
            .accessibilityOpaque
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
        XCTAssertEqual(host.materialPath, .accessibilityOpaque)
        XCTAssertTrue(content.isDescendant(of: try XCTUnwrap(host.materialView)))
        XCTAssertEqual(host.layer?.borderWidth, 2)
        XCTAssertTrue(host.accessibility.reduceMotion)

        options.value = .standard
        host.rebuildMaterial()

        XCTAssertEqual(host.materialPath, .styled)
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
        XCTAssertEqual(host.materialPath, .accessibilityOpaque)

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
        XCTAssertEqual(surface.materialPath, .styled)
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

            XCTAssertEqual(surface.materialPath, .accessibilityOpaque)
            XCTAssertEqual(surface.alphaValue, 1, accuracy: 0.001)
            XCTAssertFalse(surface.materialView is NSGlassEffectView)
            XCTAssertFalse(surface.materialView is NSVisualEffectView)
        }
    }

    @MainActor
    func testAllSurfaceChoicesUpdateInPlaceAndPreserveContent() throws {
        let content = NSView()
        let surface = PortalChromeMaterialView(
            contentView: content,
            accessibilityProvider: { .standard },
            notificationCenter: NotificationCenter()
        )
        let originalMaterial = try XCTUnwrap(surface.materialView)
        let originalParent = content.superview
        let originalRebuildCount = surface.rebuildCount
        let originalConstraintCount = originalMaterial.constraints.count

        for style in PortalSurfaceStyle.allCases {
            surface.updateSurfaceStyle(style)
            XCTAssertEqual(surface.surfaceStyle, style)
            XCTAssertTrue(surface.materialView === originalMaterial)
            XCTAssertTrue(content.superview === originalParent)
            XCTAssertEqual(originalMaterial.constraints.count, originalConstraintCount)
            XCTAssertEqual(surface.rebuildCount, originalRebuildCount)
            XCTAssertFalse(originalMaterial is NSGlassEffectView)
            XCTAssertFalse(originalMaterial is NSVisualEffectView)
            XCTAssertEqual(surface.layer?.borderWidth, style == .outline ? 1 : 0)
        }

        surface.updateSurfaceStyle(.translucent)
        XCTAssertEqual(try surfaceColor(of: surface).alphaComponent, 0.72, accuracy: 0.001)
        XCTAssertEqual(surface.layer?.borderWidth, 0)
    }

    @MainActor
    func testOpaqueChoicesIgnoreTransparencyWhileSmokeAndOutlineRespond() throws {
        let surface = makeSurface()
        for style in PortalSurfaceStyle.allCases {
            surface.updateSurfaceStyle(style)
            surface.updateBackgroundStyle(.highestTransparency)
            let transparent = try surfaceColor(of: surface)
            surface.updateBackgroundStyle(.lowTransparency)
            let solid = try surfaceColor(of: surface)
            if style.supportsTransparency {
                XCTAssertGreaterThan(solid.alphaComponent, transparent.alphaComponent)
            } else {
                XCTAssertEqual(transparent.alphaComponent, 1, accuracy: 0.001)
                XCTAssertEqual(solid.alphaComponent, 1, accuracy: 0.001)
            }
        }
    }

    @MainActor
    func testEveryStyleAdaptsToAppearance() throws {
        let surface = makeSurface()
        for style in PortalSurfaceStyle.allCases {
            surface.updateSurfaceStyle(style)
            surface.appearance = NSAppearance(named: .aqua)
            surface.viewDidChangeEffectiveAppearance()
            let light = try surfaceColor(of: surface)
            surface.appearance = NSAppearance(named: .darkAqua)
            surface.viewDidChangeEffectiveAppearance()
            let dark = try surfaceColor(of: surface)
            XCTAssertGreaterThan(light.redComponent, dark.redComponent)
            XCTAssertEqual(light.alphaComponent, dark.alphaComponent, accuracy: 0.001)
        }
    }

    @MainActor
    func testReduceTransparencyPreservesChoiceAndRestoresItWhenDisabled() throws {
        for style in PortalSurfaceStyle.allCases {
            let options = AccessibilityOptionsBox(.standard)
            let surface = PortalChromeMaterialView(
                contentView: NSView(),
                surfaceStyle: style,
                accessibilityProvider: { options.value },
                notificationCenter: NotificationCenter()
            )
            let originalColor = try surfaceColor(of: surface)
            options.value = .reduced
            surface.rebuildMaterial()
            XCTAssertEqual(surface.materialPath, .accessibilityOpaque)
            XCTAssertEqual(surface.surfaceStyle, style)
            XCTAssertTrue(try XCTUnwrap(surface.materialView).isOpaque)
            XCTAssertEqual(surface.layer?.borderWidth, 2)
            XCTAssertEqual(try surfaceColor(of: surface).alphaComponent, 1, accuracy: 0.001)

            surface.updateSurfaceStyle(.outline)
            XCTAssertEqual(surface.layer?.borderWidth, 2)
            surface.updateSurfaceStyle(style)
            options.value = .standard
            surface.rebuildMaterial()
            XCTAssertEqual(surface.surfaceStyle, style)
            XCTAssertEqual(try surfaceColor(of: surface), originalColor)
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
        let raster = try PortalSurfaceRaster.render(view)
        return raster.color(x: raster.width / 2, y: raster.height / 2)
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

/// Samples the actual AppKit drawing output without presenting a window or writing images.
@MainActor
struct PortalSurfaceRaster {
    let width: Int
    let height: Int
    private let components: [Float]

    func color(x: Int, y: Int) -> NSColor {
        let index = (y * width + x) * 4
        let alpha = CGFloat(components[index + 3])
        guard alpha > 0 else { return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0) }
        return NSColor(
            srgbRed: CGFloat(components[index]) / alpha,
            green: CGFloat(components[index + 1]) / alpha,
            blue: CGFloat(components[index + 2]) / alpha,
            alpha: alpha
        )
    }

    static func render(
        _ surface: PortalChromeMaterialView,
        rootView: NSView? = nil,
        size: NSSize = NSSize(width: 64, height: 64),
        outputScale: CGFloat = 1
    ) throws -> PortalSurfaceRaster {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = rootView ?? surface
        defer {
            window.contentView = nil
            window.close()
        }
        surface.layoutSubtreeIfNeeded()
        surface.displayIfNeeded()
        let material = try XCTUnwrap(surface.materialView)
        material.displayIfNeeded()
        let layer = try XCTUnwrap(material.layer)
        let width = Int(size.width * outputScale)
        let height = Int(size.height * outputScale)
        var components = [Float](repeating: 0, count: width * height * 4)
        try components.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 32,
                bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.scaleBy(x: outputScale, y: outputScale)
            layer.render(in: context)
        }
        return PortalSurfaceRaster(width: width, height: height, components: components)
    }
}
