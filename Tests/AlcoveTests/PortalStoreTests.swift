import AlcoveCore
import XCTest
@testable import Alcove

final class PortalStoreTests: XCTestCase {
    func testMissingStoreLoadsEmptyAndV11SaveRoundTrips() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let store = PortalStore(url: storeURL)
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
            XCTAssertTrue(json.contains("\"version\" : 11"))
            XCTAssertTrue(json.contains("\"sort_order\" : \"creation_date\""))
            XCTAssertTrue(json.contains("\"tint\" : \"indigo\""))
            XCTAssertTrue(json.contains("\"is_pinned\" : true"))
            XCTAssertFalse(json.contains("icon_layout_mode"))
            XCTAssertFalse(json.contains("text_size"))
            XCTAssertTrue(json.contains("\"background_style\" : \"maximum_transparency\""))
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

    func testV10MigratesToV11WithDefaultSortAndTintAndPreservesBackup() async throws {
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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
            XCTAssertTrue(migrated.contains("\"sort_order\" : \"name\""))
            XCTAssertTrue(migrated.contains("\"tint\" : \"default\""))
        }
    }

    func testV5MigratesToV11AndPreservesBackup() async throws {
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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
        }
    }

    func testV6MigratesToV11WithAnUnpinnedExpandedPlacement() async throws {
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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
            XCTAssertTrue(migrated.contains("\"is_pinned\" : false"))
        }
    }

    func testV7MigratesToV11PreservingPinCapacityAndTopRightEdges() async throws {
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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
        }
    }

    func testV8MigratesToV11PreservingPinCapacityHeightAndRightEdge() async throws {
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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
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

    func testMultiplePortalsTabsAndDisplayPlacementsPreserveOrderAndValues() async throws {
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
            let store = PortalStore(url: directory.appendingPathComponent("portals.json"))

            try await store.save([first, second])
            let loaded = try await store.load()

            XCTAssertEqual(loaded, [first, second])
            XCTAssertEqual(loaded[0].tabs.map(\.folderURL.path), ["/tmp/first", "/tmp/second-tab"])
            XCTAssertEqual(loaded[0].selectedTabID, secondTab)
            XCTAssertEqual(loaded[0].placement.framesByDisplay.count, 2)
            XCTAssertEqual(loaded[0].placement.homeDisplay, secondaryDisplay.identity)
            XCTAssertEqual(
                loaded.map(\.backgroundStyle),
                [.highTransparency, .lowTransparency]
            )
            XCTAssertEqual(loaded[0].iconLayout, .fixed(.medium))
            XCTAssertEqual(loaded[1].iconLayout, .fixed(.large))
        }
    }

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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
            XCTAssertTrue(loaded.allSatisfy { $0.backgroundStyle == .standard })
            XCTAssertTrue(loaded.allSatisfy { $0.iconLayout == .fixed(.medium) })
            XCTAssertEqual(loaded[0].gridCapacity, try GridCapacity(columns: 4, rows: 2))
            XCTAssertEqual(loaded[1].gridCapacity, try GridCapacity(columns: 4, rows: 2))
            let reloaded = try await PortalStore(url: storeURL).load()
            XCTAssertEqual(reloaded, loaded)
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

            try Data("{\"version\":12,\"portals\":[]}".utf8).write(to: storeURL)
            do {
                _ = try await PortalStore(url: storeURL).load()
                XCTFail("Future version must fail")
            } catch let error as PortalStoreError {
                XCTAssertEqual(error, .unsupportedVersion(12))
            }
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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
            XCTAssertTrue(migrated.contains("\"background_style\" : \"standard\""))
            XCTAssertFalse(migrated.contains("icon_layout_mode"))
            XCTAssertEqual(loaded[0].gridCapacity, try GridCapacity(columns: 3, rows: 2))
        }
    }

    func testInvalidV10BackgroundStyleFailsDomainMapping() async throws {
        try await withStoreDirectory { directory in
            let storeURL = directory.appendingPathComponent("portals.json")
            let store = PortalStore(url: storeURL)
            try await store.save([try makePortal(path: "/tmp/first", x: 10)])
            let valid = try String(contentsOf: storeURL, encoding: .utf8)
            let invalid = valid.replacingOccurrences(
                of: "\"background_style\" : \"standard\"",
                with: "\"background_style\" : \"unknown\""
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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
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
            XCTAssertTrue(migrated.contains("\"version\" : 11"))
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

    private var primaryDisplay: DisplayDescriptor {
        DisplayDescriptor(
            identity: DisplayIdentity(rawValue: primaryDisplayUUID),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
    }

    private var secondaryDisplay: DisplayDescriptor {
        DisplayDescriptor(
            identity: DisplayIdentity(rawValue: secondaryDisplayUUID),
            visibleFrame: CGRect(x: -1200, y: 0, width: 1200, height: 800)
        )
    }

    private func makePortal(
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

private let validV1JSON = """
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

private let primaryDisplayUUID = "10000000-0000-0000-0000-000000000001"
private let secondaryDisplayUUID = "20000000-0000-0000-0000-000000000002"

private func v4JSON(portal: Portal) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try String(
        decoding: encoder.encode(PortalEnvelopeV4DTO(portals: [portal])),
        as: UTF8.self
    )
}

private func v2JSON(
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

private func v3JSON(backgroundStyle: String) -> String {
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

private struct StubLegacyDisplayResolver: LegacyDisplayResolving {
    let negativeFrameDisplay: DisplayDescriptor
    let fallbackDisplay: DisplayDescriptor

    func resolveDisplay(forLegacyFrame frame: CGRect) throws -> DisplayDescriptor {
        frame.minX < 0 ? negativeFrameDisplay : fallbackDisplay
    }
}

private struct FailingIfCalledLegacyDisplayResolver: LegacyDisplayResolving {
    func resolveDisplay(forLegacyFrame frame: CGRect) throws -> DisplayDescriptor {
        throw UnexpectedResolverCall()
    }
}

private struct UnexpectedResolverCall: Error {}

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
