import AlcoveCore
import XCTest
@testable import Alcove

final class AlcoveLayoutBackupCodecTests: XCTestCase {
    func testEncodeAndDecodeRoundTripsPortableLayoutState() throws {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        var portal = try makePortal(folderURL: home.appendingPathComponent("Repo/Alcove"))
        try portal.appendTab(folderURL: URL(fileURLWithPath: "/opt/shared", isDirectory: true))
        let secondTabID = try XCTUnwrap(portal.tabs.last?.id)
        try portal.selectTab(secondTabID)
        portal.updatePinned(true)
        portal.updateSortOrder(.modificationDate)
        portal.updateTint(.blue)
        portal.updateGridCapacity(try GridCapacity(columns: 5, rows: 2))
        let appearance = PortalAppearancePreferences(
            iconSize: .large,
            backgroundStyle: .highTransparency,
            cornerRadius: .small,
            spacing: .maximum,
            shadowEnabled: false
        )

        let data = try AlcoveLayoutBackupCodec.encode(
            portals: [portal],
            appearance: appearance,
            homeDirectory: home
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"format\" : \"com.alcove.layout-backup\""))
        XCTAssertTrue(json.contains("\"version\" : 1"))
        XCTAssertFalse(json.contains("background_type"))
        XCTAssertTrue(json.contains("\"background_style\" : \"high_transparency\""))
        XCTAssertTrue(json.contains("\"kind\" : \"home_relative\""))
        XCTAssertTrue(json.contains("\"path\" : \"Repo\\/Alcove\""))
        XCTAssertTrue(json.contains("\"kind\" : \"absolute\""))
        XCTAssertFalse(json.contains("launch"))

        let backup = try AlcoveLayoutBackupCodec.decode(data, homeDirectory: home)
        XCTAssertEqual(backup.global.iconSize, .large)
        XCTAssertEqual(backup.global.backgroundStyle, .highTransparency)
        XCTAssertEqual(backup.global.cornerRadius, .small)
        XCTAssertEqual(backup.global.spacing, .large)
        XCTAssertFalse(backup.global.shadowEnabled)
        XCTAssertEqual(backup.portals.count, 1)
        let restored = try XCTUnwrap(backup.portals.first)
        XCTAssertEqual(restored.id, portal.id)
        XCTAssertEqual(restored.sortOrder, .modificationDate)
        XCTAssertEqual(restored.tint, .blue)
        XCTAssertTrue(restored.isPinned)
        XCTAssertEqual(restored.size, CGSize(width: 300, height: 200))
        XCTAssertEqual(restored.gridCapacity, try GridCapacity(columns: 5, rows: 2))
        XCTAssertEqual(restored.folderURLs, [
            home.appendingPathComponent("Repo/Alcove").standardizedFileURL,
            URL(fileURLWithPath: "/opt/shared").standardizedFileURL,
        ])
        XCTAssertEqual(restored.selectedFolderIndex, 1)
        XCTAssertEqual(restored.normalizedAnchor.x, 100.0 / 700.0, accuracy: 0.000_001)
        XCTAssertEqual(restored.normalizedAnchor.y, 160.0 / 600.0, accuracy: 0.000_001)
    }

    func testDecodeChecksFormatAndVersionBeforeThePayload() throws {
        XCTAssertThrowsError(try decode("""
        {"format":"other","version":1}
        """)) { error in
            XCTAssertEqual(error as? AlcoveLayoutBackupError, .invalidFormat("other"))
        }
        XCTAssertThrowsError(try decode("""
        {"format":"com.alcove.layout-backup","version":2}
        """)) { error in
            XCTAssertEqual(error as? AlcoveLayoutBackupError, .unsupportedVersion(2))
        }
    }

    func testDecodeRejectsInvalidGlobalEnumValues() throws {
        try assertReplacement(
            "\"icon_size\":64",
            with: "\"icon_size\":72",
            produces: .invalidIconSize(72)
        )
        try assertReplacement(
            "\"background_style\":\"standard\"",
            with: "\"background_style\":\"opaque\"",
            produces: .invalidBackgroundStyle("opaque")
        )
        try assertReplacement(
            "\"spacing\":2",
            with: "\"spacing\":9",
            produces: .invalidSpacing(9)
        )
        try assertReplacement(
            "\"corner_radius\":4",
            with: "\"corner_radius\":9",
            produces: .invalidCornerRadius(9)
        )
    }

    func testVersionOneBackupIgnoresRetiredBackgroundType() throws {
        let backup = try decode(validJSON)

        XCTAssertEqual(backup.global.backgroundStyle, .standard)
    }

    func testDecodeNormalizesRetiredAppearanceExtremes() throws {
        let retired = validJSON
            .replacingOccurrences(
                of: "\"background_style\":\"standard\"",
                with: "\"background_style\":\"minimum_transparency\""
            )
            .replacingOccurrences(of: "\"spacing\":2", with: "\"spacing\":4")

        let backup = try decode(retired)

        XCTAssertEqual(backup.global.backgroundStyle, .lowTransparency)
        XCTAssertEqual(backup.global.spacing, .large)
    }

    func testDecodeRejectsInvalidPerPortalEnumValues() throws {
        try assertReplacement(
            "\"sort_order\":\"name\"",
            with: "\"sort_order\":\"size\"",
            produces: .invalidSortOrder("size")
        )
        try assertReplacement(
            "\"tint\":\"default\"",
            with: "\"tint\":\"cyan\"",
            produces: .invalidTint("cyan")
        )
    }

    func testDecodeRejectsInvalidPlacementGeometryAndCapacity() throws {
        try assertReplacement(
            "\"x\":0.25",
            with: "\"x\":1.1",
            produces: .invalidAnchor(x: 1.1, y: 0.75)
        )
        try assertReplacement(
            "\"width\":300",
            with: "\"width\":0",
            produces: .invalidSize(width: 0, height: 200)
        )
        try assertReplacement(
            "\"columns\":3",
            with: "\"columns\":2",
            produces: .invalidGridCapacity(columns: 2, rows: 1)
        )
    }

    func testDecodeRejectsInvalidSelectedFolderIndex() throws {
        try assertReplacement(
            "\"selected_folder_index\":0",
            with: "\"selected_folder_index\":1",
            produces: .invalidSelectedFolderIndex(1)
        )
        let noSelection = validJSON.replacingOccurrences(
            of: "\"selected_folder_index\":0",
            with: "\"selected_folder_index\":null"
        )
        XCTAssertThrowsError(try decode(noSelection)) { error in
            XCTAssertEqual(error as? AlcoveLayoutBackupError, .invalidSelectedFolderIndex(nil))
        }
    }

    func testDecodeRejectsMoreThanFourFoldersInOnePortal() throws {
        let folder = "{\"kind\":\"home_relative\",\"path\":\"Repo\"}"
        let folders = Array(repeating: folder, count: Portal.maximumTabCount + 1)
            .joined(separator: ",")
        let json = validJSON.replacingOccurrences(
            of: "[\(folder)]",
            with: "[\(folders)]"
        )

        XCTAssertThrowsError(try decode(json)) { error in
            XCTAssertEqual(
                error as? AlcoveLayoutBackupError,
                .tooManyFolders(maximum: Portal.maximumTabCount)
            )
        }
    }

    func testDecodeRejectsUnsafeRelativeFolderPaths() throws {
        try assertReplacement(
            "\"path\":\"Repo\"",
            with: "\"path\":\"/tmp\"",
            produces: .invalidFolderPath("/tmp")
        )
        try assertReplacement(
            "\"path\":\"Repo\"",
            with: "\"path\":\"Repo/../Secrets\"",
            produces: .invalidFolderPath("Repo/../Secrets")
        )
    }

    func testDecodeRejectsRelativeAbsoluteFolderKind() throws {
        try assertReplacement(
            "\"kind\":\"home_relative\"",
            with: "\"kind\":\"absolute\"",
            produces: .invalidFolderPath("Repo")
        )
    }

    func testDecodeRejectsDuplicatePortalIdentifiers() throws {
        let portal = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(validJSON.utf8)) as? [String: Any]
        )
        var duplicated = portal
        let portals = try XCTUnwrap(portal["portals"] as? [[String: Any]])
        duplicated["portals"] = portals + portals
        let data = try JSONSerialization.data(withJSONObject: duplicated)
        let uuid = try XCTUnwrap(UUID(uuidString: portalID))

        XCTAssertThrowsError(try AlcoveLayoutBackupCodec.decode(data, homeDirectory: home)) { error in
            XCTAssertEqual(
                error as? AlcoveLayoutBackupError,
                .duplicatePortalID(uuid)
            )
        }
    }

    func testBackupValidationErrorsProvideUserFacingDescriptions() {
        XCTAssertEqual(
            AlcoveLayoutBackupError.malformedData.localizedDescription,
            NSLocalizedString(
                "application.settings.backup.error.malformed",
                comment: ""
            )
        )
        XCTAssertEqual(
            AlcoveLayoutBackupError.unsupportedVersion(99).localizedDescription,
            String(
                format: NSLocalizedString(
                    "application.settings.backup.error.version",
                    comment: ""
                ),
                99
            )
        )
    }

    private func makePortal(folderURL: URL) throws -> Portal {
        let display = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "display"),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        let id = try XCTUnwrap(UUID(uuidString: Self.portalID))
        return try Portal(
            id: PortalID(rawValue: id),
            folderURL: folderURL,
            frame: CGRect(x: 100, y: 160, width: 300, height: 200),
            display: display
        )
    }

    private func assertReplacement(
        _ original: String,
        with replacement: String,
        produces expectedError: AlcoveLayoutBackupError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let json = validJSON.replacingOccurrences(of: original, with: replacement)
        XCTAssertNotEqual(json, validJSON, file: file, line: line)
        XCTAssertThrowsError(try decode(json), file: file, line: line) { error in
            XCTAssertEqual(error as? AlcoveLayoutBackupError, expectedError, file: file, line: line)
        }
    }

    private func decode(_ json: String) throws -> AlcoveLayoutBackup {
        try AlcoveLayoutBackupCodec.decode(Data(json.utf8), homeDirectory: home)
    }

    private var home: URL {
        URL(fileURLWithPath: "/Users/example", isDirectory: true)
    }

    private static let portalID = "01234567-89AB-CDEF-0123-456789ABCDEF"
    private var portalID: String { Self.portalID }

    private var validJSON: String {
        """
        {
          "format":"com.alcove.layout-backup",
          "version":1,
          "global":{
            "icon_size":64,
            "background_type":"liquid_glass",
            "background_style":"standard",
            "spacing":2,
            "corner_radius":4,
            "shadow_enabled":true
          },
          "portals":[{
            "id":"\(portalID)",
            "sort_order":"name",
            "tint":"default",
            "is_pinned":false,
            "normalized_anchor":{"x":0.25,"y":0.75},
            "size":{"width":300,"height":200},
            "grid_capacity":{"columns":3,"rows":1},
            "folders":[{"kind":"home_relative","path":"Repo"}],
            "selected_folder_index":0
          }]
        }
        """
    }
}
