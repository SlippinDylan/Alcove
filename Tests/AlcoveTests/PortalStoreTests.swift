import AlcoveCore
import XCTest
@testable import Alcove

final class PortalStoreTests: XCTestCase {
    func testDefaultStoreURLUsesTheSystemApplicationSupportDirectory() {
        XCTAssertEqual(
            PortalStore.defaultURL,
            URL.applicationSupportDirectory
                .appendingPathComponent("Alcove", isDirectory: true)
                .appendingPathComponent("portals.json", isDirectory: false)
        )
    }

    func testMissingStoreLoadsEmptyAndV12SaveUsesGlobalAppearance() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            var appearance = PortalAppearancePreferences.defaults
            appearance.backgroundStyle = .maximumTransparency
            let store = PortalStore(
                url: storeURL,
                globalIconSize: appearance.iconSize,
                globalBackgroundStyle: appearance.backgroundStyle
            )
            let initial = try await store.load()
            XCTAssertEqual(initial, [])

            var portal = try makePortal(path: "/tmp/first", x: 10)
            portal.updateBackgroundStyle(.maximumTransparency)
            portal.updateGridCapacity(try GridCapacity(columns: 5, rows: 2))
            portal.updatePinned(true)
            portal.updateSortOrder(.creationDate)
            portal.updateTint(.indigo)
            try await store.save([portal])
            let restored = try await store.load()
            XCTAssertEqual(restored, [portal])

            let json = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(json.contains("\"version\" : 12"))
            XCTAssertTrue(json.contains("\"sort_order\" : \"creation_date\""))
            XCTAssertTrue(json.contains("\"tint\" : \"indigo\""))
            XCTAssertTrue(json.contains("\"is_pinned\" : true"))
            XCTAssertFalse(json.contains("icon_layout_mode"))
            XCTAssertFalse(json.contains("text_size"))
            XCTAssertFalse(json.contains("icon_size"))
            XCTAssertFalse(json.contains("background_style"))
            XCTAssertTrue(json.contains("\"columns\" : 5"))
            XCTAssertTrue(json.contains("\"rows\" : 2"))
            XCTAssertTrue(json.contains("\"selected_tab_id\""))
            XCTAssertTrue(json.contains("\"folder_path\""))
            XCTAssertTrue(json.contains("\"home_display\""))
            XCTAssertTrue(json.contains("\"frames_by_display\""))
            XCTAssertTrue(json.contains("\"absolute_frame\""))
            XCTAssertTrue(json.contains("\"reference_visible_frame\""))
            XCTAssertTrue(json.contains("\"preferred_size\""))
            XCTAssertTrue(json.contains("\"normalized_anchor\""))
            XCTAssertTrue(json.hasSuffix("\n"))
        }
    }

    func testEmptyPortalRoundTripsWithNoSelectedTab() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let portal = try Portal(
                frame: CGRect(x: 10, y: 20, width: 344, height: 180),
                display: primaryDisplay
            )
            let store = PortalStore(url: storeURL)

            try await store.save([portal])
            let loaded = try await store.load()

            XCTAssertEqual(loaded, [portal])
            XCTAssertTrue(loaded[0].tabs.isEmpty)
            XCTAssertNil(loaded[0].selectedTabID)
            let json = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertFalse(json.contains("\"selected_tab_id\""))
        }
    }

    func testMultiplePortalsPreserveLocalStateAndRestoreOneGlobalAppearance() async throws {
        try await withStoreDirectory { directory in
            var first = try makePortal(path: "/tmp/first", x: 10)
            let secondTab = try first.appendTab(
                folderURL: URL(fileURLWithPath: "/tmp/second-tab")
            )
            try first.selectTab(secondTab)
            try first.recordUserPlacement(
                frame: CGRect(x: -1100, y: 30, width: 360, height: 260),
                display: secondaryDisplay
            )
            first.updateBackgroundStyle(.highTransparency)
            var second = try makePortal(path: "/tmp/second", x: 400)
            second.updateBackgroundStyle(.lowTransparency)
            second.updateIconSize(.large)
            var appearance = PortalAppearancePreferences.defaults
            appearance.iconSize = .small
            appearance.backgroundStyle = .maximumTransparency
            let store = PortalStore(
                url: directory.appendingPathComponent("portals.json"),
                globalIconSize: appearance.iconSize,
                globalBackgroundStyle: appearance.backgroundStyle
            )

            try await store.save([first, second])
            let loaded = try await store.load()

            XCTAssertEqual(loaded.map(\.id), [first.id, second.id])
            XCTAssertEqual(loaded[0].tabs.map(\.folderURL.path), ["/tmp/first", "/tmp/second-tab"])
            XCTAssertEqual(loaded[0].selectedTabID, secondTab)
            XCTAssertEqual(loaded[0].placement.framesByDisplay.count, 2)
            XCTAssertEqual(loaded[0].placement.homeDisplay, secondaryDisplay.identity)
            XCTAssertEqual(
                loaded.map(\.backgroundStyle),
                [.maximumTransparency, .maximumTransparency]
            )
            XCTAssertTrue(loaded.allSatisfy { $0.iconLayout == .fixed(.small) })
        }
    }

    func testMalformedAndFutureVersionsFailExplicitly() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            try Data("not-json".utf8).write(to: storeURL)
            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("Malformed JSON must fail")
            } catch let error as PortalStoreError {
                guard case .corruptedFile(let url, _) = error else {
                    return XCTFail("Expected corruptedFile, got \(error)")
                }
                XCTAssertEqual(url, storeURL)
            }

            try Data("{\"version\":13,\"portals\":[]}".utf8).write(to: storeURL)
            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("Future version must fail")
            } catch let error as PortalStoreError {
                XCTAssertEqual(error, .unsupportedVersion(13))
            }
        }
    }

    func testReplaceFailurePreservesExistingStoreAndCleansTemporaryFile() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let first = try makePortal(path: "/tmp/first", x: 10)
            let second = try makePortal(path: "/tmp/second", x: 20)
            let realStore = PortalStore(url: storeURL)
            try await realStore.save([first])

            let failingStore = PortalStore(
                url: storeURL,
                fileSystem: ReplaceFailingFileSystem()
            )
            do {
                try await failingStore.save([second])
                XCTFail("Injected replacement failure must fail")
            } catch let error as PortalStoreError {
                guard case .writeFailed(let url, _) = error else {
                    return XCTFail("Expected writeFailed, got \(error)")
                }
                XCTAssertEqual(url, storeURL)
            }

            let preserved = try await realStore.load()
            XCTAssertEqual(preserved, [first])
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: directory.path),
                ["portals.json"]
            )
        }
    }

    func testDuplicatePortalIDsAndRelativeFolderPathsAreRejected() async throws {
        try await withStoreDirectory { directory in
            let duplicateID = PortalID(rawValue: UUID())
            let first = try makePortal(id: duplicateID, path: "/tmp/first", x: 0)
            let second = try makePortal(id: duplicateID, path: "/tmp/second", x: 20)
            let storeURL = directory.appendingPathComponent("portals.json")
            do {
                try await PortalStore(url: storeURL).save([first, second])
                XCTFail("Duplicate portal IDs must not be stored")
            } catch let error as PortalStoreError {
                XCTAssertEqual(error, .duplicatePortalID(index: 1, id: duplicateID.rawValue))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))

            let relativePathJSON = v2JSON(
                homeDisplay: primaryDisplayUUID,
                anchorX: 0.5,
                preferredWidth: 300,
                folderPath: "relative/folder"
            )
            try Data(relativePathJSON.utf8).write(to: storeURL)
            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("Relative folder paths must not restore")
            } catch let error as PortalStoreError {
                guard case .invalidPortal(let index, let reason) = error else {
                    return XCTFail("Expected invalidPortal, got \(error)")
                }
                XCTAssertEqual(index, 0)
                XCTAssertTrue(reason.contains("invalidFolderPath"))
            }
        }
    }

    var primaryDisplay: DisplayDescriptor {
        DisplayDescriptor(
            identity: DisplayIdentity(rawValue: primaryDisplayUUID),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
    }

    var secondaryDisplay: DisplayDescriptor {
        DisplayDescriptor(
            identity: DisplayIdentity(rawValue: secondaryDisplayUUID),
            visibleFrame: CGRect(x: -1200, y: 0, width: 1200, height: 800)
        )
    }

    func makePortal(
        id: PortalID = PortalID(),
        path: String,
        x: CGFloat
    ) throws -> Portal {
        try Portal(
            id: id,
            folderURL: URL(fileURLWithPath: path),
            frame: CGRect(x: x, y: 20, width: 320, height: 240),
            display: primaryDisplay
        )
    }
}

let validV1JSON = """
{
  "version": 1,
  "portals": [{
    "id": "00000000-0000-0000-0000-000000000001",
    "tabs": [{
      "id": "00000000-0000-0000-0000-000000000002",
      "folder_path": "/tmp/folder"
    }],
    "selected_tab_id": "00000000-0000-0000-0000-000000000002",
    "frame": {"x": 0, "y": 0, "width": 300, "height": 240},
    "icon_size": 64
  }]
}
"""

let primaryDisplayUUID = "10000000-0000-0000-0000-000000000001"
let secondaryDisplayUUID = "20000000-0000-0000-0000-000000000002"

func v4JSON(portal: Portal) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try String(
        decoding: encoder.encode(PortalEnvelopeV4DTO(portals: [portal])),
        as: UTF8.self
    )
}

func v2JSON(
    homeDisplay: String,
    anchorX: Double,
    preferredWidth: Double,
    folderPath: String = "/tmp/folder"
) -> String {
    """
    {
      "version": 2,
      "portals": [{
        "id": "00000000-0000-0000-0000-000000000001",
        "tabs": [{
          "id": "00000000-0000-0000-0000-000000000002",
          "folder_path": "\(folderPath)"
        }],
        "selected_tab_id": "00000000-0000-0000-0000-000000000002",
        "placement": {
          "home_display": "\(homeDisplay)",
          "frames_by_display": {
            "\(primaryDisplayUUID)": {
              "absolute_frame": {"x": 0, "y": 0, "width": 300, "height": 240},
              "reference_visible_frame": {"x": 0, "y": 0, "width": 1440, "height": 900},
              "preferred_size": {"width": \(preferredWidth), "height": 240},
              "normalized_anchor": {"x": \(anchorX), "y": 0.5}
            }
          }
        },
        "icon_size": 64
      }]
    }
    """
}

func v3JSON(backgroundStyle: String) -> String {
    v2JSON(
        homeDisplay: primaryDisplayUUID,
        anchorX: 0.5,
        preferredWidth: 300
    )
    .replacingOccurrences(of: "\"version\": 2", with: "\"version\": 3")
    .replacingOccurrences(
        of: "\"icon_size\": 64",
        with: "\"icon_size\": 64,\n        \"background_style\": \"\(backgroundStyle)\""
    )
}

struct StubLegacyDisplayResolver: LegacyDisplayResolving {
    let negativeFrameDisplay: DisplayDescriptor
    let fallbackDisplay: DisplayDescriptor

    func resolveDisplay(forLegacyFrame frame: CGRect) throws -> DisplayDescriptor {
        frame.minX < 0 ? negativeFrameDisplay : fallbackDisplay
    }
}

struct FailingIfCalledLegacyDisplayResolver: LegacyDisplayResolving {
    func resolveDisplay(forLegacyFrame frame: CGRect) throws -> DisplayDescriptor {
        throw UnexpectedResolverCall()
    }
}

struct UnexpectedResolverCall: Error {}

struct ReplaceFailingFileSystem: PortalStoreFileSystem {
    private let base = FoundationPortalStoreFileSystem()

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func writeData(_ data: Data, to url: URL) throws { try base.writeData(data, to: url) }
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItem(at: sourceURL, to: destinationURL)
    }
    func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        throw NSError(domain: "PortalStoreTests", code: 1)
    }
    func removeItem(at url: URL) throws { try base.removeItem(at: url) }
}

func withStoreDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("alcove-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    do {
        try await body(directory)
    } catch {
        let bodyError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw StoreFixtureError.bodyAndCleanup(
                body: String(describing: bodyError),
                cleanup: String(describing: error)
            )
        }
        throw bodyError
    }
    try FileManager.default.removeItem(at: directory)
}

enum StoreFixtureError: Error {
    case bodyAndCleanup(body: String, cleanup: String)
}
