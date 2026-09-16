import AlcoveCore
import XCTest
@testable import Alcove

extension PortalStoreTests {
    func testV10MigratesToV12WithDefaultSortAndTintAndPreservesBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let portal = try makePortal(path: "/tmp/first", x: 10)
            let legacy = try JSONEncoder().encode(PortalEnvelopeV10DTO(portals: [portal]))
            try legacy.write(to: storeURL)

            let loaded = try await PortalStore(url: storeURL).load()

            XCTAssertEqual(loaded[0].sortOrder, .name)
            XCTAssertEqual(loaded[0].tint, .default)
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent("portals.v10.json.bak")),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
            XCTAssertTrue(migrated.contains("\"sort_order\" : \"name\""))
            XCTAssertTrue(migrated.contains("\"tint\" : \"default\""))
        }
    }

    func testV11MigratesToV12WithoutDuplicatingGlobalAppearance() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            var portal = try makePortal(path: "/tmp/first", x: 10)
            portal.updateIconSize(.large)
            portal.updateBackgroundStyle(.highTransparency)
            let legacy = try JSONEncoder().encode(PortalEnvelopeV11DTO(portals: [portal]))
            try legacy.write(to: storeURL)
            var appearance = PortalAppearancePreferences.defaults
            appearance.iconSize = .large
            appearance.backgroundStyle = .highTransparency
            let store = PortalStore(
                url: storeURL,
                globalIconSize: appearance.iconSize,
                globalBackgroundStyle: appearance.backgroundStyle
            )

            let loaded = try await store.load()

            XCTAssertEqual(loaded, [portal])
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent("portals.v11.json.bak")),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
            XCTAssertFalse(migrated.contains("icon_size"))
            XCTAssertFalse(migrated.contains("background_style"))
            let reloaded = try await store.load()
            XCTAssertEqual(reloaded, [portal])
        }
    }

    func testV5MigratesToV12AndPreservesBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let portal = try makePortal(path: "/tmp/first", x: 10)
            let legacy = try JSONEncoder().encode(PortalEnvelopeV5DTO(portals: [portal]))
            try legacy.write(to: storeURL)

            let loaded = try await PortalStore(url: storeURL).load()

            XCTAssertEqual(loaded.count, 1)
            XCTAssertEqual(loaded[0].tabs, portal.tabs)
            XCTAssertFalse(loaded[0].isPinned)
            XCTAssertEqual(loaded[0].frame.maxY, portal.frame.maxY)
            XCTAssertEqual(loaded[0].frame.size, CGSize(width: 328, height: 204))
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent("portals.v5.json.bak")),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
        }
    }

    func testV6MigratesToV12WithAnUnpinnedExpandedPlacement() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let portal = try makePortal(path: "/tmp/first", x: 10)
            let legacy = try JSONEncoder().encode(PortalEnvelopeV6DTO(portals: [portal]))
            try legacy.write(to: storeURL)

            let loaded = try await PortalStore(url: storeURL).load()

            XCTAssertEqual(loaded.count, 1)
            XCTAssertFalse(loaded[0].isPinned)
            XCTAssertEqual(loaded[0].frame.maxY, portal.frame.maxY)
            XCTAssertEqual(loaded[0].frame.size, CGSize(width: 328, height: 204))
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent("portals.v6.json.bak")),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
            XCTAssertTrue(migrated.contains("\"is_pinned\" : false"))
        }
    }

    func testV7MigratesToV12PreservingPinCapacityAndTopRightEdges() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            var portal = try makePortal(path: "/tmp/first", x: 10)
            try portal.recordUserPlacement(
                frame: CGRect(x: 10, y: 100, width: 320, height: 240),
                display: primaryDisplay
            )
            portal.updatePinned(true)
            let legacy = try JSONEncoder().encode(PortalEnvelopeV7DTO(portals: [portal]))
            try legacy.write(to: storeURL)

            let loaded = try await PortalStore(url: storeURL).load()

            XCTAssertEqual(loaded[0].isPinned, true)
            XCTAssertEqual(loaded[0].gridCapacity, portal.gridCapacity)
            XCTAssertEqual(loaded[0].frame.maxY, portal.frame.maxY)
            XCTAssertEqual(loaded[0].frame.maxX, portal.frame.maxX)
            XCTAssertEqual(loaded[0].frame.size, CGSize(width: 328, height: 204))
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent("portals.v7.json.bak")),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
        }
    }

    func testV8MigratesToV12PreservingPinCapacityHeightAndRightEdge() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            var portal = try makePortal(path: "/tmp/first", x: 500)
            portal.updateGridCapacity(try GridCapacity(columns: 4, rows: 2))
            portal.updatePinned(true)
            let legacy = try JSONEncoder().encode(PortalEnvelopeV8DTO(portals: [portal]))
            try legacy.write(to: storeURL)

            let loaded = try await PortalStore(url: storeURL).load()

            XCTAssertTrue(loaded[0].isPinned)
            XCTAssertEqual(loaded[0].gridCapacity, portal.gridCapacity)
            XCTAssertEqual(loaded[0].frame.maxX, portal.frame.maxX)
            XCTAssertEqual(loaded[0].frame.size, CGSize(width: 428, height: 316))
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent("portals.v8.json.bak")),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
        }
    }

    func testV6MigrationNeverOverwritesAnExistingDifferentBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let backupURL = directory.appendingPathComponent("portals.v6.json.bak")
            let portal = try makePortal(path: "/tmp/first", x: 10)
            let legacy = try JSONEncoder().encode(PortalEnvelopeV6DTO(portals: [portal]))
            let originalBackup = Data("first preserved v6".utf8)
            try legacy.write(to: storeURL)
            try originalBackup.write(to: backupURL)

            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("Migration must not replace the first preserved backup")
            } catch let error as PortalStoreError {
                XCTAssertEqual(error, .migrationBackupConflict(url: backupURL))
            }

            XCTAssertEqual(try Data(contentsOf: backupURL), originalBackup)
            XCTAssertEqual(try Data(contentsOf: storeURL), legacy)
        }
    }

    func testInvalidV10BackgroundStyleFailsDomainMapping() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let store = PortalStore(url: storeURL)
            let portal = try makePortal(path: "/tmp/first", x: 10)
            let valid = String(
                decoding: try JSONEncoder().encode(PortalEnvelopeV10DTO(portals: [portal])),
                as: UTF8.self
            )
            let invalid = valid.replacingOccurrences(
                of: "\"background_style\":\"standard\"",
                with: "\"background_style\":\"unknown\""
            )
            try Data(invalid.utf8).write(to: storeURL)

            do {
                _ = try await store.load()
                XCTFail("Unknown background style must not restore")
            } catch let error as PortalStoreError {
                guard case .invalidPortal(let index, let reason) = error else {
                    return XCTFail("Expected invalidPortal, got \(error)")
                }
                XCTAssertEqual(index, 0)
                XCTAssertTrue(reason.contains("invalidBackgroundStyle"))
            }
        }
    }

    func testInvalidV9IconLayoutValuesFailDomainMapping() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let valid = String(
            decoding: try JSONEncoder().encode(PortalEnvelopeV9DTO(portals: [portal])),
            as: UTF8.self
        )
        let invalidCases = [
            valid.replacingOccurrences(
                of: "\"icon_layout_mode\":\"fixed\"",
                with: "\"icon_layout_mode\":\"unsupported\""
            ),
            valid.replacingOccurrences(of: "\"icon_size\":64", with: "\"icon_size\":15"),
        ]

        for invalid in invalidCases {
            try await withStoreDirectory { directory in
                let storeURL = directory.appendingPathComponent("portals.json")
                try Data(invalid.utf8).write(to: storeURL)
                do {
                    _ = try await PortalStore(url: storeURL).load()
                    XCTFail("Invalid v9 icon layout must not restore")
                } catch let error as PortalStoreError {
                    guard case .invalidPortal(let index, _) = error else {
                        return XCTFail("Expected invalidPortal, got \(error)")
                    }
                    XCTAssertEqual(index, 0)
                }
            }
        }
    }

    func testV9FollowDesktopMigratesToNearestManualPreset() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let valid = String(
            decoding: try JSONEncoder().encode(PortalEnvelopeV9DTO(portals: [portal])),
            as: UTF8.self
        )
        let cases: [(Double, IconSize)] = [(55, .small), (64, .medium), (72, .large)]

        for (rawSize, expected) in cases {
            try await withStoreDirectory { directory in
                let storeURL = directory.appendingPathComponent("portals.json")
                let legacy = valid
                    .replacingOccurrences(
                        of: "\"icon_layout_mode\":\"fixed\"",
                        with: "\"icon_layout_mode\":\"follow_desktop\""
                    )
                    .replacingOccurrences(
                        of: "\"icon_size\":64",
                        with: "\"icon_size\":\(rawSize)"
                    )
                try Data(legacy.utf8).write(to: storeURL)

                let loaded = try await PortalStore(url: storeURL).load()

                XCTAssertEqual(loaded[0].iconLayout, .fixed(expected))
                let migrated = try String(contentsOf: storeURL, encoding: .utf8)
                XCTAssertFalse(migrated.contains("follow_desktop"))
                XCTAssertFalse(migrated.contains("icon_layout_mode"))
            }
        }
    }

    func testV4MigrationDerivesCapacityAndPreservesBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let legacyPortal = try makePortal(path: "/tmp/first", x: 10)
            let legacy = try v4JSON(portal: legacyPortal)
            try Data(legacy.utf8).write(to: storeURL)

            let loaded = try await PortalStore(url: storeURL).load()

            XCTAssertEqual(loaded.count, 1)
            XCTAssertEqual(loaded[0].gridCapacity, try GridCapacity(columns: 3, rows: 2))
            XCTAssertEqual(
                try String(
                    contentsOf: directory.appendingPathComponent("portals.v4.json.bak"),
                    encoding: .utf8
                ),
                legacy
            )
            let migrated = try String(contentsOf: storeURL, encoding: .utf8)
            XCTAssertTrue(migrated.contains("\"version\" : 12"))
            XCTAssertTrue(migrated.contains("\"columns\" : 3"))
            XCTAssertTrue(migrated.contains("\"rows\" : 2"))
        }
    }

    func testV4ToV5RewriteFailurePreservesSourceAndBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let legacy = try v4JSON(portal: makePortal(path: "/tmp/first", x: 10))
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
                    contentsOf: directory.appendingPathComponent("portals.v4.json.bak"),
                    encoding: .utf8
                ),
                legacy
            )
        }
    }

    func testV4MigrationNeverOverwritesAnExistingDifferentBackup() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let backupURL = directory.appendingPathComponent("portals.v4.json.bak")
            let legacy = try v4JSON(portal: makePortal(path: "/tmp/first", x: 10))
            let originalBackup = Data("first preserved v4".utf8)
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

    func testInvalidV10CapacityFailsDomainMapping() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let store = PortalStore(url: storeURL)
            try await store.save([try makePortal(path: "/tmp/first", x: 10)])
            let valid = try String(contentsOf: storeURL, encoding: .utf8)
            let invalid = valid.replacingOccurrences(
                of: "\"columns\" : 3",
                with: "\"columns\" : 2"
            )
            try Data(invalid.utf8).write(to: storeURL)

            do {
                _ = try await store.load()
                XCTFail("Invalid capacity must not restore")
            } catch let error as PortalStoreError {
                guard case .invalidPortal(let index, let reason) = error else {
                    return XCTFail("Expected invalidPortal, got \(error)")
                }
                XCTAssertEqual(index, 0)
                XCTAssertTrue(reason.contains("invalidGridCapacity"))
            }
        }
    }

}
