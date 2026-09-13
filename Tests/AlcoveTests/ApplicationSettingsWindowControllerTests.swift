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
    func testSettingsWindowUsesGeneralAndAboutPreferenceCategories() throws {
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
