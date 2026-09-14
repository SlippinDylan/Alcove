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

@MainActor
private final class ApplicationLayoutBackupControllerSpy: ApplicationLayoutBackupControlling {
    private(set) var importCount = 0
    private(set) var exportCount = 0

    func beginImport(from window: NSWindow) {
        importCount += 1
    }

    func beginExport(from window: NSWindow) {
        exportCount += 1
    }
}

@MainActor
private final class PanelPositionRepairerSpy: PanelPositionRepairing {
    private(set) var repairCount = 0
    var onRepair: (() -> Void)?

    func repairPanelPositions() async throws -> Int {
        repairCount += 1
        onRepair?()
        return 0
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
    func testImportedAppearancePersistsWithoutCallingChangeCallback() throws {
        let suiteName = "ApplicationSettingsWindowControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = ApplicationPreferencesController(userDefaults: defaults)
        var callbackCount = 0
        controller.onPortalAppearanceChanged = { _ in
            callbackCount += 1
            return false
        }
        let imported = PortalAppearancePreferences(
            iconSize: .large,
            backgroundStyle: .minimumTransparency,
            cornerRadius: .small,
            spacing: .maximum,
            shadowEnabled: false
        )

        controller.replacePortalAppearanceFromImport(imported)

        XCTAssertEqual(callbackCount, 0)
        XCTAssertEqual(controller.portalAppearance, imported)
        XCTAssertEqual(
            ApplicationPreferencesController(userDefaults: defaults).portalAppearance,
            imported
        )
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
        XCTAssertEqual(
            descendants(of: controller.settingsViewController.view).filter {
                $0.identifier?.rawValue == "application-settings.row-separator"
            }.count,
            4
        )
        controller.close()
    }

    @MainActor
    func testAdvancedSettingsExposeLayoutImportAndExportActions() throws {
        let backupController = ApplicationLayoutBackupControllerSpy()
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            layoutBackupController: backupController,
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128))
        )
        controller.selectCategory(.advanced)
        let views = descendants(of: controller.settingsViewController.view)
        let card = try XCTUnwrap(views.first {
            $0.identifier?.rawValue == "application-settings.backup.card"
        })
        XCTAssertNotNil(views.first {
            $0.identifier?.rawValue == "application-settings.position-repair.card"
        })
        XCTAssertNotNil(views.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "application-settings.position-repair.action"
        })
        let importButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "application-settings.backup.import"
        })
        let exportButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "application-settings.backup.export"
        })

        XCTAssertNotNil(card.layer)
        XCTAssertEqual(
            descendants(of: card).filter {
                $0.identifier?.rawValue == "application-settings.row-separator"
            }.count,
            1
        )
        importButton.performClick(nil)
        exportButton.performClick(nil)
        XCTAssertEqual(backupController.importCount, 1)
        XCTAssertEqual(backupController.exportCount, 1)
        controller.close()
    }

    @MainActor
    func testAdvancedPositionRepairButtonInvokesRepairer() async throws {
        let repairer = PanelPositionRepairerSpy()
        let invoked = expectation(description: "Position repair invoked")
        repairer.onRepair = { invoked.fulfill() }
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            panelPositionRepairer: repairer,
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128))
        )
        controller.selectCategory(.advanced)
        let button = try XCTUnwrap(
            descendants(of: controller.settingsViewController.view)
                .compactMap { $0 as? NSButton }
                .first {
                    $0.identifier?.rawValue == "application-settings.position-repair.action"
                }
        )

        button.performClick(nil)
        await fulfillment(of: [invoked], timeout: 1)
        await Task.yield()

        XCTAssertEqual(repairer.repairCount, 1)
        if let sheet = controller.window?.attachedSheet {
            controller.window?.endSheet(sheet)
        }
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
    func testSettingsWindowUsesAllPreferenceCategories() throws {
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
