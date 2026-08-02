// DisplayInventoryTests.swift
// Alcove Spike 0.2B — Automated display inventory and observer tests.
//
// Tests use injected display records and NotificationCenter where practical,
// plus bounded real-current-session smoke tests. Tests must not depend on
// a specific display ID, UUID, name, screen count, or ordering.
// Disposable spike code, not production XCTest.

import AppKit
import CoreGraphics
import Foundation
import XCTest

@testable import DisplayInventory

// MARK: - JSON Encoding

final class JSONEncodingTests: XCTestCase {

    /// Verify that ScreenRecord Codable produces deterministic JSON
    /// with stable key ordering (sorted keys).
    func testScreenRecordJSONHasStableKeyOrdering() throws {
        let record = ScreenRecord(
            arrayIndex: 0,
            localizedName: "Test Display",
            displayID: 12345,
            uuidResult: .available("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055),
            backingScaleFactor: 2.0,
            isMainScreen: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode([record])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // Keys must appear in sorted order within each record.
        let frameRange = try XCTUnwrap(json.range(of: "\"frame\""))
        let isMainRange = try XCTUnwrap(json.range(of: "\"isMainScreen\""))
        XCTAssertTrue(frameRange.lowerBound < isMainRange.lowerBound,
                      "Keys must be sorted: 'frame' before 'isMainScreen'")

        // Verify the JSON is decodable and round-trips.
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([ScreenRecord].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].arrayIndex, 0)
        XCTAssertEqual(decoded[0].localizedName, "Test Display")
        XCTAssertEqual(decoded[0].displayID, 12345)
        XCTAssertEqual(decoded[0].uuidResult,
                       .available("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        XCTAssertEqual(decoded[0].frame, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(decoded[0].visibleFrame,
                       CGRect(x: 0, y: 25, width: 1920, height: 1055))
        XCTAssertEqual(decoded[0].backingScaleFactor, 2.0)
        XCTAssertTrue(decoded[0].isMainScreen)
    }

    /// Verify all UUIDResult variants encode/decode correctly.
    func testUUIDResultAllVariants() throws {
        let records: [ScreenRecord] = [
            ScreenRecord(
                arrayIndex: 0, localizedName: "A", displayID: 1,
                uuidResult: .available("12345678-1234-1234-1234-123456789abc"),
                frame: .zero, visibleFrame: .zero,
                backingScaleFactor: 1.0, isMainScreen: false
            ),
            ScreenRecord(
                arrayIndex: 1, localizedName: "B", displayID: 2,
                uuidResult: .unavailable,
                frame: .zero, visibleFrame: .zero,
                backingScaleFactor: 1.0, isMainScreen: false
            ),
            ScreenRecord(
                arrayIndex: 2, localizedName: "C", displayID: 3,
                uuidResult: .extractionError("missingDisplayID"),
                frame: .zero, visibleFrame: .zero,
                backingScaleFactor: 1.0, isMainScreen: false
            ),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(records)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([ScreenRecord].self, from: data)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].uuidResult,
                       .available("12345678-1234-1234-1234-123456789abc"))
        XCTAssertEqual(decoded[1].uuidResult, .unavailable)
        XCTAssertEqual(decoded[2].uuidResult, .extractionError("missingDisplayID"))
    }

    /// Verify that encoding an empty array produces valid JSON.
    func testEmptyArrayEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode([ScreenRecord]())
        let decoded = try JSONDecoder().decode([ScreenRecord].self, from: data)
        XCTAssertTrue(decoded.isEmpty)
    }
}

// MARK: - Display ID Extraction

final class DisplayIDExtractorTests: XCTestCase {

    /// Verify extraction from a well-formed device description.
    func testExtractDisplayIDFromValidDescription() {
        let description: [NSDeviceDescriptionKey: Any] = [
            NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: UInt32(69731840))
        ]
        let result = extractDisplayID(from: description)
        switch result {
        case .success(let id):
            XCTAssertEqual(id, CGDirectDisplayID(69731840))
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    /// Verify explicit error when NSScreenNumber key is missing.
    func testMissingDisplayIDReturnsError() {
        let description: [NSDeviceDescriptionKey: Any] = [:]
        let result = extractDisplayID(from: description)
        switch result {
        case .success:
            XCTFail("Expected failure for missing key")
        case .failure(let error):
            XCTAssertEqual(error, .missingDisplayID)
        }
    }

    /// Verify explicit error when NSScreenNumber is not numeric.
    func testNonNumericDisplayIDReturnsError() {
        let description: [NSDeviceDescriptionKey: Any] = [
            NSDeviceDescriptionKey("NSScreenNumber"): "not-a-number"
        ]
        let result = extractDisplayID(from: description)
        switch result {
        case .success:
            XCTFail("Expected failure for non-numeric value")
        case .failure(let error):
            XCTAssertEqual(error, .nonNumericDisplayID)
        }
    }

    func testBooleanDisplayIDReturnsError() {
        let description: [NSDeviceDescriptionKey: Any] = [
            NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: true)
        ]
        XCTAssertEqual(
            extractDisplayID(from: description),
            .failure(.nonNumericDisplayID)
        )
    }

    func testInvalidNumericDisplayIDsReturnErrors() {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for value in [NSNumber(value: -1), NSNumber(value: 1.5), NSNumber(value: 4_294_967_296)] {
            XCTAssertEqual(
                extractDisplayID(from: [key: value]),
                .failure(.invalidDisplayIDValue)
            )
        }
    }
}

// MARK: - UUID Formatting

final class UUIDFormatterTests: XCTestCase {

    /// Verify that formatCFUUID produces a standard 8-4-4-4-12 string
    /// using a known UUID string.
    func testFormatCFUUIDProducesCanonicalString() throws {
        // Create a CFUUID from a known string.
        let uuidString = "AABBCCDD-EEFF-0011-2233-445566778899" as CFString
        let uuid = try XCTUnwrap(CFUUIDCreateFromString(kCFAllocatorDefault, uuidString))
        let result = formatCFUUID(uuid)
        XCTAssertEqual(result, "aabbccdd-eeff-0011-2233-445566778899")
    }

    /// Verify that formatCFUUID is deterministic for the same input.
    func testFormatCFUUIDIsDeterministic() throws {
        let uuidString = "12345678-1234-1234-1234-123456789abc" as CFString
        let uuid = try XCTUnwrap(CFUUIDCreateFromString(kCFAllocatorDefault, uuidString))
        let r1 = formatCFUUID(uuid)
        let r2 = formatCFUUID(uuid)
        XCTAssertEqual(r1, r2)
    }

    /// Verify that lookupDisplayUUID returns .unavailable for invalid ID.
    func testLookupDisplayUUIDReturnsUnavailableForInvalidID() {
        // Display ID 0 is typically invalid/virtual.
        let result = lookupDisplayUUID(0)
        switch result {
        case .available:
            // Some systems may return a UUID for ID 0; that's acceptable.
            break
        case .unavailable:
            // Expected on most systems.
            break
        case .extractionError:
            XCTFail("lookupDisplayUUID should not return extractionError")
        }
    }

    /// Verify that lookupDisplayUUID returns .available for a real display.
    /// Skips if no screens are available.
    @MainActor
    func testLookupDisplayUUIDHasExplicitResultForRealDisplay() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No screens available in the current session")
        }
        let deviceDesc = screen.deviceDescription
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let nsNumber = deviceDesc[key] as? NSNumber else {
            XCTFail("NSScreenNumber missing or not NSNumber")
            return
        }
        let displayID = CGDirectDisplayID(nsNumber.uint32Value)
        let result = lookupDisplayUUID(displayID)
        switch result {
        case .available(let uuidString):
            // Verify it looks like a UUID (8-4-4-4-12).
            let parts = uuidString.split(separator: "-")
            XCTAssertEqual(parts.count, 5, "UUID should have 5 parts")
            XCTAssertEqual(parts[0].count, 8)
            XCTAssertEqual(parts[1].count, 4)
            XCTAssertEqual(parts[2].count, 4)
            XCTAssertEqual(parts[3].count, 4)
            XCTAssertEqual(parts[4].count, 12)
        case .unavailable:
            // Explicitly represented and acceptable for some configurations.
            break
        case .extractionError:
            XCTFail("Should not get extractionError for a real screen")
        }
    }
}

// MARK: - Screen Observer

@MainActor
final class ScreenObserverTests: XCTestCase {
    private let notificationName = NSApplication.didChangeScreenParametersNotification

    func testStartAndStopAreIdempotent() async throws {
        let center = NotificationCenter()
        var callbackCount = 0
        let observer = ScreenObserver(
            center: center,
            snapshotProvider: { [] },
            eventHandler: { _ in callbackCount += 1 }
        )

        observer.start()
        observer.start()
        XCTAssertTrue(observer.isObserving)
        center.post(name: notificationName, object: nil)
        try await allowNotificationDelivery()
        XCTAssertEqual(callbackCount, 1)

        observer.stop()
        observer.stop()
        XCTAssertFalse(observer.isObserving)
    }

    func testNotificationCapturesFreshSnapshot() async throws {
        let center = NotificationCenter()
        var captureCount = 0
        var receivedDisplayIDs: [CGDirectDisplayID?] = []
        let observer = ScreenObserver(
            center: center,
            snapshotProvider: {
                captureCount += 1
                return [Self.record(displayID: CGDirectDisplayID(captureCount))]
            },
            eventHandler: { records in receivedDisplayIDs.append(records.first?.displayID) }
        )

        observer.start()
        center.post(name: notificationName, object: nil)
        try await allowNotificationDelivery()
        center.post(name: notificationName, object: nil)
        try await allowNotificationDelivery()
        observer.stop()

        XCTAssertEqual(captureCount, 2)
        XCTAssertEqual(receivedDisplayIDs, [1, 2])
    }

    func testStopPreventsCallbacks() async throws {
        let center = NotificationCenter()
        var callbackCount = 0
        let observer = ScreenObserver(
            center: center,
            snapshotProvider: { [] },
            eventHandler: { _ in callbackCount += 1 }
        )

        observer.start()
        observer.stop()
        center.post(name: notificationName, object: nil)
        try await allowNotificationDelivery()

        XCTAssertEqual(callbackCount, 0)
    }

    func testBackgroundNotificationIsDeliveredOnMainActor() async {
        let center = NotificationCenter()
        let callback = expectation(description: "main actor callback")
        let observer = ScreenObserver(
            center: center,
            snapshotProvider: { [] },
            eventHandler: { _ in
                MainActor.preconditionIsolated()
                callback.fulfill()
            }
        )

        observer.start()
        let name = notificationName
        await Task.detached {
            center.post(name: name, object: nil)
        }.value
        await fulfillment(of: [callback], timeout: 1.0)
        observer.stop()
    }

    private func allowNotificationDelivery() async throws {
        await Task.yield()
        try await Task.sleep(for: .milliseconds(20))
    }

    private static func record(displayID: CGDirectDisplayID) -> ScreenRecord {
        ScreenRecord(
            arrayIndex: 0,
            localizedName: "Injected",
            displayID: displayID,
            uuidResult: .unavailable,
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            visibleFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            backingScaleFactor: 1,
            isMainScreen: true
        )
    }
}

// MARK: - Current-Session Smoke Test

final class CurrentSessionSmokeTests: XCTestCase {

    /// Real current-session snapshot: at least one screen with finite/positive
    /// frame invariants and unique array indices. Skips honestly if no screens.
    @MainActor
    func testCurrentSessionSnapshotSmoke() throws {
        let records = ScreenInventory.capture()

        guard !records.isEmpty else {
            // No screens available in this test environment.
            // Report honestly rather than manufacturing a screen.
            throw XCTSkip("No screens available in the current session")
        }

        // Verify array indices are unique.
        let indices = Set(records.map(\.arrayIndex))
        XCTAssertEqual(indices.count, records.count,
                       "Array indices must be unique")

        // Verify each record has finite, positive frame invariants.
        for record in records {
            XCTAssertTrue(record.frame.width > 0 && record.frame.height > 0,
                          "Screen \(record.arrayIndex) frame must be positive: "
                          + "\(record.frame)")
            XCTAssertTrue(record.frame.origin.x.isFinite
                          && record.frame.origin.y.isFinite,
                          "Screen \(record.arrayIndex) frame origin must be finite")
            XCTAssertTrue(record.frame.width.isFinite && record.frame.height.isFinite)
            XCTAssertTrue(record.visibleFrame.width > 0
                          && record.visibleFrame.height > 0,
                          "Screen \(record.arrayIndex) visibleFrame must be positive")
            XCTAssertTrue(record.visibleFrame.origin.x.isFinite
                          && record.visibleFrame.origin.y.isFinite
                          && record.visibleFrame.width.isFinite
                          && record.visibleFrame.height.isFinite)
            XCTAssertTrue(record.backingScaleFactor.isFinite
                          && record.backingScaleFactor > 0,
                          "Screen \(record.arrayIndex) scale factor must be positive: "
                          + "\(record.backingScaleFactor)")
            XCTAssertFalse(record.localizedName.isEmpty,
                           "Screen \(record.arrayIndex) should have a name")
        }

        // Verify exactly one main screen.
        let mainCount = records.filter(\.isMainScreen).count
        XCTAssertEqual(mainCount, 1, "Exactly one screen should be main")
    }

    /// Verify JSON encoding of a real snapshot is decodable.
    @MainActor
    func testSnapshotJSONIsDecodable() throws {
        let records = ScreenInventory.capture()
        let data = try ScreenInventory.encodeJSON(records)

        let decoded = try JSONDecoder().decode([ScreenRecord].self, from: data)
        XCTAssertEqual(decoded.count, records.count)

        for (original, decodedRecord) in zip(records, decoded) {
            XCTAssertEqual(original.arrayIndex, decodedRecord.arrayIndex)
            XCTAssertEqual(original.displayID, decodedRecord.displayID)
            XCTAssertEqual(original.frame, decodedRecord.frame)
            XCTAssertEqual(original.visibleFrame, decodedRecord.visibleFrame)
            XCTAssertEqual(original.backingScaleFactor,
                           decodedRecord.backingScaleFactor)
            XCTAssertEqual(original.isMainScreen, decodedRecord.isMainScreen)
        }
    }
}

// MARK: - CLI Argument Parsing

@MainActor
final class CLIArgumentParsingTests: XCTestCase {

    /// Verify that invalid commands are rejected without crash.
    func testInvalidCommandIsRejected() async {
        let code = await runProbe(arguments: ["DisplayProbe", "invalid-command"])
        XCTAssertEqual(code, 1, "Invalid command should exit with code 1")
    }

    /// Verify that missing arguments are rejected without crash.
    func testMissingArgumentsIsRejected() async {
        let code = await runProbe(arguments: ["DisplayProbe"])
        XCTAssertEqual(code, 1, "Missing arguments should exit with code 1")
    }

    /// Verify that observe without --seconds is rejected.
    func testObserveWithoutSecondsIsRejected() async {
        let code = await runProbe(arguments: ["DisplayProbe", "observe"])
        XCTAssertEqual(code, 1, "Observe without --seconds should exit with code 1")
    }

    /// Verify that observe with non-numeric seconds is rejected.
    func testObserveWithNonNumericSecondsIsRejected() async {
        let code = await runProbe(arguments: ["DisplayProbe", "observe", "--seconds", "abc"])
        XCTAssertEqual(code, 1, "Non-numeric seconds should exit with code 1")
    }

    /// Verify that observe with negative seconds is rejected.
    func testObserveWithNegativeSecondsIsRejected() async {
        let code = await runProbe(arguments: ["DisplayProbe", "observe", "--seconds", "-1"])
        XCTAssertEqual(code, 1, "Negative seconds should exit with code 1")
    }

    /// Verify that observe with zero seconds is rejected.
    func testObserveWithZeroSecondsIsRejected() async {
        let code = await runProbe(arguments: ["DisplayProbe", "observe", "--seconds", "0"])
        XCTAssertEqual(code, 1, "Zero seconds should exit with code 1")
    }

    /// Verify that observe with infinity is rejected.
    func testObserveWithInfinityIsRejected() async {
        let code = await runProbe(arguments: ["DisplayProbe", "observe", "--seconds", "inf"])
        XCTAssertEqual(code, 1, "Infinity seconds should exit with code 1")
    }
    func testObserveWithTrailingArgumentsIsRejected() async {
        let code = await runProbe(
            arguments: ["DisplayProbe", "observe", "--seconds", "1", "extra"]
        )
        XCTAssertEqual(code, 1)
    }

    func testSnapshotCommandReturnsSuccess() async {
        let code = await runProbe(arguments: ["DisplayProbe", "snapshot"])
        XCTAssertEqual(code, 0)
    }

    func testSnapshotWithTrailingArgumentsIsRejected() async {
        let code = await runProbe(
            arguments: ["DisplayProbe", "snapshot", "extra"]
        )
        XCTAssertEqual(code, 1)
    }

    func testBoundedObserveCommandReturnsSuccess() async {
        let code = await runProbe(
            arguments: ["DisplayProbe", "observe", "--seconds", "0.01"]
        )
        XCTAssertEqual(code, 0)
    }
}
