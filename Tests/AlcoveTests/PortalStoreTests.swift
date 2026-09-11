import AlcoveCore
import XCTest
@testable import Alcove

final class PortalStoreTests: XCTestCase {
    func testMissingStoreLoadsEmptyAndFirstSaveRoundTrips() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let store = PortalStore(url: storeURL)
            let initialPortals = try await store.load()
            XCTAssertEqual(initialPortals, [])

            let portal = try makePortal(path: "/tmp/first", x: 10)
            try await store.save([portal])
            let loadedPortals = try await store.load()
            XCTAssertEqual(loadedPortals, [portal])

            let json = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(json.contains("\"selected_tab_id\""))
            XCTAssertTrue(json.contains("\"folder_path\""))
            XCTAssertTrue(json.hasSuffix("\n"))
        }
    }

    func testMultiplePortalsAndTabsPreserveCreationOrder() async throws {
        try await withStoreDirectory { directory in
            var first = try makePortal(path: "/tmp/first", x: 10)
            let secondTab = try first.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second-tab"))
            try first.selectTab(secondTab)
            let second = try makePortal(path: "/tmp/second", x: 400)
            let store = PortalStore(url: directory.appendingPathComponent("portals.json"))

            try await store.save([first, second])
            let loaded = try await store.load()

            XCTAssertEqual(loaded, [first, second])
            XCTAssertEqual(loaded[0].tabs.map(\.folderURL.path), ["/tmp/first", "/tmp/second-tab"])
            XCTAssertEqual(loaded[0].selectedTabID, secondTab)
        }
    }

    func testMalformedAndFutureVersionsFailExplicitly() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            try Data("not-json".utf8).write(to: storeURL)
            let malformedStore = PortalStore(url: storeURL)
            do {
                _ = try await malformedStore.load()
                XCTFail("Malformed JSON must fail")
            } catch let error as PortalStoreError {
                guard case .corruptedFile(let url, _) = error else {
                    return XCTFail("Expected corruptedFile, got \(error)")
                }
                XCTAssertEqual(url, storeURL)
            }

            try Data("{\"version\":2,\"portals\":[]}".utf8).write(to: storeURL)
            let futureStore = PortalStore(url: storeURL)
            do {
                _ = try await futureStore.load()
                XCTFail("Future version must fail")
            } catch let error as PortalStoreError {
                XCTAssertEqual(error, .unsupportedVersion(2))
            }
        }
    }

    func testInvalidDTOFailsDomainMapping() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let invalid = """
            {
              "version": 1,
              "portals": [{
                "id": "00000000-0000-0000-0000-000000000001",
                "tabs": [],
                "selected_tab_id": "00000000-0000-0000-0000-000000000002",
                "frame": {"x": 0, "y": 0, "width": 300, "height": 240},
                "icon_size": 64
              }]
            }
            """
            try Data(invalid.utf8).write(to: storeURL)

            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("Invalid portal aggregate must fail")
            } catch let error as PortalStoreError {
                guard case .invalidPortal(let index, _) = error else {
                    return XCTFail("Expected invalidPortal, got \(error)")
                }
                XCTAssertEqual(index, 0)
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

            let preservedPortals = try await realStore.load()
            XCTAssertEqual(preservedPortals, [first])
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertEqual(files, ["portals.json"])
        }
    }

    private func makePortal(path: String, x: CGFloat) throws -> Portal {
        try Portal(
            folderURL: URL(fileURLWithPath: path),
            frame: CGRect(x: x, y: 20, width: 320, height: 240)
        )
    }
}

private struct ReplaceFailingFileSystem: PortalStoreFileSystem {
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

private func withStoreDirectory(
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

private enum StoreFixtureError: Error {
    case bodyAndCleanup(body: String, cleanup: String)
}
