import AppKit
import XCTest
@testable import Alcove

@MainActor
private final class LaunchAtLoginControllerSpy: LaunchAtLoginControlling {
    var isEnabled = false
    private(set) var requestedValues: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        isEnabled = enabled
    }
}

final class ApplicationSettingsWindowControllerTests: XCTestCase {
    @MainActor
    func testPortalAppearancePreferencesUseDefaultsAndPersistFiveStepValues() throws {
        let suiteName = "ApplicationSettingsWindowControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = ApplicationPreferencesController(userDefaults: defaults)

        XCTAssertEqual(controller.portalAppearance, .defaults)
        XCTAssertEqual(PortalCornerRadius.allCases.map(\.points), [0, 8, 14, 20, 24])
        XCTAssertEqual(PortalSpacing.allCases.map(\.points), [4, 8, 12, 16, 20])

        var changes: [PortalAppearancePreferences] = []
        controller.onPortalAppearanceChanged = {
            changes.append($0)
            return true
        }
        controller.setPortalCornerRadius(.small)
        controller.setPortalSpacing(.maximum)
        controller.setPortalIconSize(.large)
        controller.setPortalBackgroundStyle(.highTransparency)
        controller.setPortalShadowEnabled(false)
        controller.setPortalShadowEnabled(false)

        XCTAssertEqual(changes.count, 5)
        let restored = ApplicationPreferencesController(userDefaults: defaults)
        XCTAssertEqual(restored.portalAppearance.iconSize, .large)
        XCTAssertEqual(restored.portalAppearance.backgroundStyle, .highTransparency)
        XCTAssertEqual(restored.portalAppearance.cornerRadius, .small)
        XCTAssertEqual(restored.portalAppearance.spacing, .maximum)
        XCTAssertFalse(restored.portalAppearance.shadowEnabled)
    }

    @MainActor
    func testRejectedAppearanceChangeDoesNotMutateOrPersistThePreference() throws {
        let suiteName = "ApplicationSettingsWindowControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = ApplicationPreferencesController(userDefaults: defaults)
        controller.onPortalAppearanceChanged = { _ in false }

        XCTAssertFalse(controller.setPortalSpacing(.maximum))

        XCTAssertEqual(controller.portalAppearance.spacing, .medium)
        let restored = ApplicationPreferencesController(userDefaults: defaults)
        XCTAssertEqual(restored.portalAppearance.spacing, .medium)
    }

    @MainActor
    func testStyleSettingsExposeGlobalContentAndAppearanceControls() throws {
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128))
        )
        controller.selectCategory(.style)
        let sliders = descendants(of: controller.settingsViewController.view)
            .compactMap { $0 as? NSSlider }

        let radius = try XCTUnwrap(sliders.first {
            $0.identifier?.rawValue == "application-settings.corner-radius"
        })
        let spacing = try XCTUnwrap(sliders.first {
            $0.identifier?.rawValue == "application-settings.spacing"
        })
        let contentSize = try XCTUnwrap(sliders.first {
            $0.identifier?.rawValue == "application-settings.content-size"
        })
        let transparency = try XCTUnwrap(sliders.first {
            $0.identifier?.rawValue == "application-settings.transparency"
        })
        XCTAssertEqual(radius.numberOfTickMarks, 5)
        XCTAssertEqual(spacing.numberOfTickMarks, 5)
        XCTAssertTrue(radius.allowsTickMarkValuesOnly)
        XCTAssertTrue(spacing.allowsTickMarkValuesOnly)
        XCTAssertEqual(contentSize.numberOfTickMarks, 3)
        XCTAssertEqual(transparency.numberOfTickMarks, 5)
        XCTAssertTrue(contentSize.allowsTickMarkValuesOnly)
        XCTAssertTrue(transparency.allowsTickMarkValuesOnly)
        controller.close()
    }

    func testApplicationMetadataReadsBundleValues() {
        let metadata = ApplicationMetadata(infoDictionary: [
            "CFBundleName": "Alcove",
            "CFBundleShortVersionString": "2.3.0",
            "CFBundleVersion": "443",
            "NSHumanReadableCopyright": "Copyright",
        ])

        XCTAssertEqual(metadata.name, "Alcove")
        XCTAssertEqual(metadata.versionAndBuild, "2.3.0 (443)")
        XCTAssertEqual(metadata.copyright, "Copyright")
    }

    @MainActor
    func testSettingsWindowUsesGeneralStyleAndAboutPreferenceCategories() throws {
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128))
        )

        XCTAssertEqual(controller.window?.contentView?.bounds.size, NSSize(width: 400, height: 450))
        XCTAssertEqual(controller.window?.toolbarStyle, .preference)
        XCTAssertEqual(controller.window?.toolbar?.displayMode, .iconAndLabel)
        XCTAssertEqual(Set(controller.categoryItems.keys), Set(ApplicationSettingsViewController.Category.allCases))
        XCTAssertEqual(
            controller.window?.toolbar?.selectedItemIdentifier,
            ApplicationSettingsViewController.Category.general.toolbarItemIdentifier
        )

        controller.selectCategory(.about)
        controller.settingsViewController.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.settingsViewController.selectedCategory, .about)
        XCTAssertEqual(
            controller.window?.toolbar?.selectedItemIdentifier,
            ApplicationSettingsViewController.Category.about.toolbarItemIdentifier
        )
        let versionBadge = try XCTUnwrap(
            descendants(of: controller.settingsViewController.view)
                .first { $0.identifier?.rawValue == "application-settings.version-badge" }
        )
        let versionLabel = try XCTUnwrap(
            versionBadge.subviews.compactMap { $0 as? NSTextField }.first
        )
        XCTAssertEqual(versionLabel.frame.midY, versionBadge.bounds.midY, accuracy: 0.5)
        controller.close()
    }

    @MainActor
    func testLaunchAtLoginSwitchReflectsAndUpdatesService() throws {
        let service = LaunchAtLoginControllerSpy()
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: service,
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128))
        )
        let root = controller.settingsViewController.view
        root.layoutSubtreeIfNeeded()
        let toggle = try XCTUnwrap(
            descendants(of: root)
                .compactMap { $0 as? NSSwitch }
                .first { $0.identifier?.rawValue == "application-settings.launch-at-login" }
        )
        XCTAssertEqual(toggle.state, .off)
        let toggleFrame = root.convert(toggle.bounds, from: toggle)
        XCTAssertLessThan(root.bounds.maxY - toggleFrame.midY, 120)

        toggle.performClick(nil)

        XCTAssertEqual(service.requestedValues, [true])
        XCTAssertEqual(toggle.state, .on)
        controller.close()
    }

    @MainActor
    private func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
