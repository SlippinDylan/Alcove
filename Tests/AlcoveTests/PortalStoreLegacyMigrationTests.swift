import AlcoveCore
import XCTest
@testable import Alcove

extension PortalStoreTests {
    func testV1MigrationUsesResolvedDisplaysAndCompensatesPlacements() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let legacy = """
            {
              "version": 1,
              "portals": [
                {
                  "id": "00000000-0000-0000-0000-000000000001",
                  "tabs": [{
                    "id": "00000000-0000-0000-0000-000000000002",
                    "folder_path": "/tmp/secondary"
                  }],
                  "selected_tab_id": "00000000-0000-0000-0000-000000000002",
                  "frame": {"x": -1100, "y": 20, "width": 500, "height": 300},
                  "icon_size": 64
                },
                {
                  "id": "00000000-0000-0000-0000-000000000003",
                  "tabs": [{
                    "id": "00000000-0000-0000-0000-000000000004",
                    "folder_path": "/tmp/offscreen"
                  }],
                  "selected_tab_id": "00000000-0000-0000-0000-000000000004",
                  "frame": {"x": 4000, "y": 20, "width": 500, "height": 300},
                  "icon_size": 64
                }
              ]
            }
            """
            try Data(legacy.utf8).write(to: storeURL)
            let resolver = StubLegacyDisplayResolver(
                negativeFrameDisplay: secondaryDisplay,
                fallbackDisplay: primaryDisplay
            )

            let loaded = try await PortalStore(
                url: storeURL,
                legacyDisplayResolver: resolver
            ).load()

            XCTAssertEqual(loaded[0].placement.homeDisplay, secondaryDisplay.identity)
            XCTAssertEqual(
                loaded[0].placement.homeEntry.referenceVisibleFrame,
                secondaryDisplay.visibleFrame
            )
            XCTAssertEqual(loaded[1].placement.homeDisplay, primaryDisplay.identity)
            XCTAssertEqual(loaded[1].frame, CGRect(x: 1012, y: 4, width: 428, height: 316))

            let backupURL = directory.appendingPathComponent("portals.v1.json.bak")
            XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), legacy)
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
            XCTAssertTrue(loaded.allSatisfy { $0.backgroundStyle == .standard })
            XCTAssertTrue(loaded.allSatisfy { $0.iconLayout == .fixed(.medium) })
            XCTAssertEqual(loaded[0].gridCapacity, try GridCapacity(columns: 4, rows: 2))
            XCTAssertEqual(loaded[1].gridCapacity, try GridCapacity(columns: 4, rows: 2))
            let reloaded = try await PortalStore(url: storeURL).load()
            XCTAssertEqual(reloaded, loaded)
        }
    }

    func testV2MigrationDefaultsBackgroundAndPreservesBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let legacy = v2JSON(
                homeDisplay: primaryDisplayUUID,
                anchorX: 0.5,
                preferredWidth: 300
            )
            try Data(legacy.utf8).write(to: storeURL)

            let loaded = try await PortalStore(url: storeURL).load()

            XCTAssertEqual(loaded.map(\.backgroundStyle), [.standard])
            XCTAssertEqual(
                try String(
                    contentsOf: directory.appendingPathComponent("portals.v2.json.bak"),
                    encoding: .utf8
                ),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
            XCTAssertFalse(migrated.contains("background_style"))
            XCTAssertFalse(migrated.contains("icon_layout_mode"))
            XCTAssertEqual(loaded[0].gridCapacity, try GridCapacity(columns: 3, rows: 2))
        }
    }

    func testV3MigrationPreservesBackgroundAndWritesFixedLayoutBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let legacy = v3JSON(backgroundStyle: "low_transparency")
            try Data(legacy.utf8).write(to: storeURL)

            let loaded = try await PortalStore(url: storeURL).load()

            XCTAssertEqual(loaded.map(\.backgroundStyle), [.lowTransparency])
            XCTAssertEqual(loaded.map(\.iconLayout), [.fixed(.medium)])
            XCTAssertEqual(
                try String(
                    contentsOf: directory.appendingPathComponent("portals.v3.json.bak"),
                    encoding: .utf8
                ),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
            XCTAssertFalse(migrated.contains("icon_layout_mode"))
            XCTAssertFalse(migrated.contains("text_size"))
            XCTAssertEqual(loaded[0].gridCapacity, try GridCapacity(columns: 3, rows: 2))
        }
    }

    func testV3ToV5RewriteFailurePreservesSourceAndBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let legacy = v3JSON(backgroundStyle: "standard")
            try Data(legacy.utf8).write(to: storeURL)
            let store = PortalStore(
                url: storeURL,
                fileSystem: ReplaceFailingFileSystem()
            )

            do {
                _ = try await store.load()
                XCTFail("A failed v5 replacement must fail migration")
            } catch let error as PortalStoreError {
                guard case .writeFailed(let url, _) = error else {
                    return XCTFail("Expected writeFailed, got \(error)")
                }
                XCTAssertEqual(url, storeURL)
            }

            XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), legacy)
            XCTAssertEqual(
                try String(
                    contentsOf: directory.appendingPathComponent("portals.v3.json.bak"),
                    encoding: .utf8
                ),
                legacy
            )
        }
    }

    func testV3MigrationNeverOverwritesAnExistingDifferentBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let backupURL = directory.appendingPathComponent("portals.v3.json.bak")
            let legacy = v3JSON(backgroundStyle: "standard")
            let originalBackup = Data("first preserved v3".utf8)
            try Data(legacy.utf8).write(to: storeURL)
            try originalBackup.write(to: backupURL)

            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("Migration must not replace the first preserved backup")
            } catch let error as PortalStoreError {
                XCTAssertEqual(error, .migrationBackupConflict(url: backupURL))
            }

            XCTAssertEqual(try Data(contentsOf: backupURL), originalBackup)
            XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), legacy)
        }
    }

    func testV1MigrationRequiresDisplayResolver() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            try Data(validV1JSON.utf8).write(to: storeURL)

            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("A legacy frame must not acquire a fabricated display identity")
            } catch let error as PortalStoreError {
                guard case .legacyDisplayResolutionFailed(let index, let reason) = error else {
                    return XCTFail("Expected legacyDisplayResolutionFailed, got \(error)")
                }
                XCTAssertEqual(index, 0)
                XCTAssertTrue(reason.contains("unavailable"))
            }
            XCTAssertEqual(
                try String(
                    contentsOf: directory.appendingPathComponent("portals.v1.json.bak"),
                    encoding: .utf8
                ),
                validV1JSON
            )
            XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), validV1JSON)
        }
    }

    func testInvalidV2PlacementValuesFailDomainMapping() async throws {
        try await withStoreDirectory { directory in
            let invalidCases = [
                v2JSON(homeDisplay: "missing", anchorX: 0.5, preferredWidth: 300),
                v2JSON(homeDisplay: primaryDisplayUUID, anchorX: 1.5, preferredWidth: 300),
                v2JSON(homeDisplay: primaryDisplayUUID, anchorX: 0.5, preferredWidth: -1)
            ]

            for (caseIndex, invalid) in invalidCases.enumerated() {
                let storeURL = directory
                    .appendingPathComponent("case-\(caseIndex)")
                    .appendingPathComponent("portals.json")
                try FileManager.default.createDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(invalid.utf8).write(to: storeURL)
                do {
                    _ = try await PortalStore(url: storeURL).load()
                    XCTFail("Invalid placement must fail")
                } catch let error as PortalStoreError {
                    guard case .invalidPortal(let index, _) = error else {
                        return XCTFail("Expected invalidPortal, got \(error)")
                    }
                    XCTAssertEqual(index, 0)
                }
            }
        }
    }

    func testV2ToV3RewriteFailurePreservesSourceAndBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let legacy = v2JSON(
                homeDisplay: primaryDisplayUUID,
                anchorX: 0.5,
                preferredWidth: 300
            )
            try Data(legacy.utf8).write(to: storeURL)
            let store = PortalStore(
                url: storeURL,
                fileSystem: ReplaceFailingFileSystem()
            )

            do {
                _ = try await store.load()
                XCTFail("A failed v3 replacement must fail migration")
            } catch let error as PortalStoreError {
                guard case .writeFailed(let url, _) = error else {
                    return XCTFail("Expected writeFailed, got \(error)")
                }
                XCTAssertEqual(url, storeURL)
            }

            XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), legacy)
            XCTAssertEqual(
                try String(
                    contentsOf: directory.appendingPathComponent("portals.v2.json.bak"),
                    encoding: .utf8
                ),
                legacy
            )
        }
    }

    func testV2MigrationNeverOverwritesAnExistingDifferentBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let backupURL = directory.appendingPathComponent("portals.v2.json.bak")
            let legacy = v2JSON(
                homeDisplay: primaryDisplayUUID,
                anchorX: 0.5,
                preferredWidth: 300
            )
            let originalBackup = Data("first preserved v2".utf8)
            try Data(legacy.utf8).write(to: storeURL)
            try originalBackup.write(to: backupURL)

            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("Migration must not replace the first preserved backup")
            } catch let error as PortalStoreError {
                XCTAssertEqual(error, .migrationBackupConflict(url: backupURL))
            }

            XCTAssertEqual(try Data(contentsOf: backupURL), originalBackup)
            XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), legacy)
        }
    }

    func testInvalidV1FrameFailsBeforeDisplayResolution() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let invalid = validV1JSON.replacingOccurrences(
                of: "\"width\": 300",
                with: "\"width\": -300"
            )
            try Data(invalid.utf8).write(to: storeURL)

            do {
                _ = try await PortalStore(
                    url: storeURL,
                    legacyDisplayResolver: FailingIfCalledLegacyDisplayResolver()
                ).load()
                XCTFail("Invalid legacy geometry must fail")
            } catch let error as PortalStoreError {
                guard case .invalidPortal(let index, let reason) = error else {
                    return XCTFail("Expected invalidPortal, got \(error)")
                }
                XCTAssertEqual(index, 0)
                XCTAssertTrue(reason.contains("invalidFrame"))
            }
            XCTAssertEqual(
                try String(
                    contentsOf: directory.appendingPathComponent("portals.v1.json.bak"),
                    encoding: .utf8
                ),
                invalid
            )
            XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), invalid)
        }
    }

    func testV2RewriteFailureLeavesV1SourceAndBackupIntact() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            try Data(validV1JSON.utf8).write(to: storeURL)
            let store = PortalStore(
                url: storeURL,
                fileSystem: ReplaceFailingFileSystem(),
                legacyDisplayResolver: StubLegacyDisplayResolver(
                    negativeFrameDisplay: secondaryDisplay,
                    fallbackDisplay: primaryDisplay
                )
            )

            do {
                _ = try await store.load()
                XCTFail("A failed v2 replacement must fail migration")
            } catch let error as PortalStoreError {
                guard case .writeFailed(let url, _) = error else {
                    return XCTFail("Expected writeFailed, got \(error)")
                }
                XCTAssertEqual(url, storeURL)
            }

            XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), validV1JSON)
            XCTAssertEqual(
                try String(
                    contentsOf: directory.appendingPathComponent("portals.v1.json.bak"),
                    encoding: .utf8
                ),
                validV1JSON
            )
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
                ["portals.json", "portals.v1.json.bak"]
            )
        }
    }

    func testV1MigrationNeverOverwritesAnExistingDifferentBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let backupURL = directory.appendingPathComponent("portals.v1.json.bak")
            let originalBackup = Data("first preserved v1".utf8)
            try Data(validV1JSON.utf8).write(to: storeURL)
            try originalBackup.write(to: backupURL)
            let store = PortalStore(
                url: storeURL,
                legacyDisplayResolver: StubLegacyDisplayResolver(
                    negativeFrameDisplay: secondaryDisplay,
                    fallbackDisplay: primaryDisplay
                )
            )

            do {
                _ = try await store.load()
                XCTFail("Migration must not replace the first preserved backup")
            } catch let error as PortalStoreError {
                XCTAssertEqual(error, .migrationBackupConflict(url: backupURL))
            }

            XCTAssertEqual(try Data(contentsOf: backupURL), originalBackup)
            XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), validV1JSON)
        }
    }

}
