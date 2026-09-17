import AlcoveCore
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

@MainActor
private final class ApplicationRelauncherSpy: ApplicationRelaunching {
    private(set) var requestCount = 0
    private(set) var relaunchCount = 0

    func requestRelaunch() {
        requestCount += 1
    }

    func relaunchIfRequested() {
        relaunchCount += 1
    }
}

final class ApplicationSettingsWindowControllerTests: XCTestCase {
    @MainActor
    func testApplicationLanguagePreferencePersistsOverridesAndRestoresSystemDefault() throws {
        let suiteName = "ApplicationLanguageControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = ApplicationLanguageController(userDefaults: defaults)

        XCTAssertEqual(controller.selectedLanguage, .system)
        XCTAssertTrue(controller.setSelectedLanguage(.english))
        XCTAssertEqual(controller.selectedLanguage, .english)
        XCTAssertEqual(defaults.string(forKey: "application.language"), "en")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        XCTAssertFalse(controller.setSelectedLanguage(.english))

        XCTAssertTrue(controller.setSelectedLanguage(.simplifiedChinese))
        XCTAssertEqual(controller.selectedLanguage, .simplifiedChinese)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])

        XCTAssertTrue(controller.setSelectedLanguage(.traditionalChinese))
        XCTAssertEqual(controller.selectedLanguage, .traditionalChinese)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hant"])

        XCTAssertTrue(controller.setSelectedLanguage(.system))
        XCTAssertEqual(controller.selectedLanguage, .system)
        XCTAssertEqual(defaults.string(forKey: "application.language"), "system")
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
    }

    @MainActor
    func testPortalAppearancePreferencesUseDefaultsAndPersistSelectableValues() throws {
        let suiteName = "ApplicationSettingsWindowControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = ApplicationPreferencesController(userDefaults: defaults)

        XCTAssertEqual(controller.portalAppearance, .defaults)
        XCTAssertEqual(controller.portalAppearance.iconSize, .medium)
        XCTAssertEqual(controller.portalAppearance.backgroundStyle, .lowTransparency)
        XCTAssertEqual(controller.portalAppearance.cornerRadius, .medium)
        XCTAssertEqual(controller.portalAppearance.spacing, .small)
        XCTAssertFalse(controller.portalAppearance.shadowEnabled)
        XCTAssertEqual(PortalCornerRadius.allCases.map(\.points), [0, 8, 14, 20, 24])
        XCTAssertEqual(PortalSpacing.selectableCases.map(\.points), [2, 4, 6, 8])
        XCTAssertEqual(PortalBackgroundStyle.selectableCases, [
            .highestTransparency,
            .maximumTransparency,
            .highTransparency,
            .standard,
            .lowTransparency,
        ])

        var changes: [PortalAppearancePreferences] = []
        controller.onPortalAppearanceChanged = {
            changes.append($0)
            return true
        }
        controller.setPortalCornerRadius(.small)
        controller.setPortalSpacing(.large)
        controller.setPortalIconSize(.large)
        controller.setPortalBackgroundStyle(.highTransparency)
        controller.setPortalShadowEnabled(true)
        controller.setPortalShadowEnabled(true)

        XCTAssertEqual(changes.count, 5)
        let restored = ApplicationPreferencesController(userDefaults: defaults)
        XCTAssertEqual(restored.portalAppearance.iconSize, .large)
        XCTAssertEqual(restored.portalAppearance.backgroundStyle, .highTransparency)
        XCTAssertEqual(restored.portalAppearance.cornerRadius, .small)
        XCTAssertEqual(restored.portalAppearance.spacing, .large)
        XCTAssertTrue(restored.portalAppearance.shadowEnabled)
    }

    @MainActor
    func testRejectedAppearanceChangeDoesNotMutateOrPersistThePreference() throws {
        let suiteName = "ApplicationSettingsWindowControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = ApplicationPreferencesController(userDefaults: defaults)
        controller.onPortalAppearanceChanged = { _ in false }

        XCTAssertFalse(controller.setPortalSpacing(.large))

        XCTAssertEqual(controller.portalAppearance.spacing, .small)
        let restored = ApplicationPreferencesController(userDefaults: defaults)
        XCTAssertEqual(restored.portalAppearance.spacing, .small)
    }

    @MainActor
    func testRetiredAppearanceExtremesNormalizeWhenPreferencesLoad() throws {
        let suiteName = "ApplicationSettingsRetiredValuesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("minimum_transparency", forKey: "portalAppearance.backgroundStyle")
        defaults.set(PortalSpacing.maximum.rawValue, forKey: "portalAppearance.spacing")

        let controller = ApplicationPreferencesController(userDefaults: defaults)

        XCTAssertEqual(controller.portalAppearance.backgroundStyle, .lowTransparency)
        XCTAssertEqual(controller.portalAppearance.spacing, .large)
        XCTAssertEqual(
            defaults.string(forKey: "portalAppearance.backgroundStyle"),
            PortalBackgroundStyle.lowTransparency.rawValue
        )
        XCTAssertEqual(
            defaults.integer(forKey: "portalAppearance.spacing"),
            PortalSpacing.large.rawValue
        )
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
        XCTAssertEqual(imported.backgroundStyle, .lowTransparency)
        XCTAssertEqual(imported.spacing, .large)

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
        let suiteName = "ApplicationSettingsStyleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ApplicationPreferencesController(userDefaults: defaults)
        preferences.onPortalAppearanceChanged = { _ in true }
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            preferencesController: preferences,
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
        XCTAssertEqual(spacing.numberOfTickMarks, 4)
        XCTAssertTrue(radius.allowsTickMarkValuesOnly)
        XCTAssertTrue(spacing.allowsTickMarkValuesOnly)
        XCTAssertEqual(contentSize.numberOfTickMarks, 3)
        XCTAssertEqual(transparency.numberOfTickMarks, 5)
        XCTAssertTrue(contentSize.allowsTickMarkValuesOnly)
        XCTAssertTrue(transparency.allowsTickMarkValuesOnly)
        XCTAssertEqual(radius.neutralValue, Double(PortalCornerRadius.medium.rawValue))
        XCTAssertEqual(spacing.neutralValue, Double(PortalSpacing.small.rawValue))
        XCTAssertEqual(contentSize.neutralValue, 1)
        XCTAssertEqual(transparency.neutralValue, 4)
        XCTAssertEqual(radius.tintProminence, .secondary)
        XCTAssertEqual(spacing.tintProminence, .secondary)
        XCTAssertEqual(contentSize.tintProminence, .secondary)
        XCTAssertEqual(transparency.tintProminence, .secondary)
        XCTAssertFalse(descendants(of: controller.settingsViewController.view).contains {
            $0.identifier?.rawValue.hasPrefix("application-settings.background-type") == true
        })
        XCTAssertEqual(
            descendants(of: controller.settingsViewController.view).filter {
                $0.identifier?.rawValue == "application-settings.row-separator"
            }.count,
            3
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
        var updateRequestCount = 0
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128)),
            canCheckForUpdates: { true },
            onCheckForUpdates: { updateRequestCount += 1 }
        )

        XCTAssertEqual(controller.window?.contentView?.bounds.size, NSSize(width: 400, height: 450))
        XCTAssertEqual(controller.window?.toolbarStyle, .preference)
        XCTAssertEqual(controller.window?.toolbar?.displayMode, .iconAndLabel)
        XCTAssertEqual(Set(controller.categoryItems.keys), Set(ApplicationSettingsViewController.Category.allCases))
        XCTAssertTrue(controller.categoryItems.values.allSatisfy { !$0.isBordered })
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
        let updateButton = try XCTUnwrap(
            descendants(of: controller.settingsViewController.view)
                .compactMap { $0 as? NSButton }
                .first {
                    $0.identifier?.rawValue == "application-settings.check-for-updates"
                }
        )
        updateButton.performClick(nil)
        XCTAssertEqual(updateRequestCount, 1)
        controller.close()
    }

    @MainActor
    func testAboutDisablesUpdateCheckWhenUpdaterIsUnavailable() throws {
        var updateRequestCount = 0
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128)),
            canCheckForUpdates: { false },
            onCheckForUpdates: { updateRequestCount += 1 }
        )
        controller.selectCategory(.about)
        let button = try XCTUnwrap(
            descendants(of: controller.settingsViewController.view)
                .compactMap { $0 as? NSButton }
                .first {
                    $0.identifier?.rawValue == "application-settings.check-for-updates"
                }
        )

        XCTAssertFalse(button.isEnabled)
        button.performClick(nil)
        XCTAssertEqual(updateRequestCount, 0)
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
    func testGeneralSettingsExposeFourApplicationLanguageChoices() throws {
        let suiteName = "ApplicationLanguageSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let languageController = ApplicationLanguageController(userDefaults: defaults)
        languageController.setSelectedLanguage(.english)
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            languageController: languageController,
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128))
        )
        let popUpButton = try XCTUnwrap(
            descendants(of: controller.settingsViewController.view)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.identifier?.rawValue == "application-settings.language" }
        )

        XCTAssertEqual(
            popUpButton.itemArray.compactMap { $0.representedObject as? String },
            ApplicationLanguage.allCases.map(\.rawValue)
        )
        XCTAssertEqual(popUpButton.selectedItem?.representedObject as? String, "en")
        controller.close()
    }

    @MainActor
    func testCompletingLanguageChangeRequestsAutomaticRelaunch() async throws {
        let suiteName = "ApplicationLanguageRelaunchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let relauncher = ApplicationRelauncherSpy()
        let controller = ApplicationSettingsWindowController(
            launchAtLoginController: LaunchAtLoginControllerSpy(),
            languageController: ApplicationLanguageController(userDefaults: defaults),
            applicationRelauncher: relauncher,
            metadata: ApplicationMetadata(infoDictionary: [:]),
            applicationIcon: NSImage(size: NSSize(width: 128, height: 128))
        )
        let popUpButton = try XCTUnwrap(
            descendants(of: controller.settingsViewController.view)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.identifier?.rawValue == "application-settings.language" }
        )
        popUpButton.selectItem(at: 2)
        let action = try XCTUnwrap(popUpButton.action)

        XCTAssertTrue(NSApplication.shared.sendAction(
            action,
            to: popUpButton.target,
            from: popUpButton
        ))
        let sheet = try XCTUnwrap(controller.window?.attachedSheet)
        let doneButton = try XCTUnwrap(
            descendants(of: try XCTUnwrap(sheet.contentView))
                .compactMap { $0 as? NSButton }
                .first {
                    $0.title == NSLocalizedString(
                        "application.settings.language.done",
                        comment: ""
                    )
                }
        )

        doneButton.performClick(nil)
        await Task.yield()

        XCTAssertEqual(relauncher.requestCount, 1)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
        controller.close()
    }

    @MainActor
    private func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
