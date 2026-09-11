import Foundation
import XCTest
@testable import Alcove

final class FolderAccessTests: XCTestCase {
    func testEnumerationRunsOffMainThread() async throws {
        let recorder = ExecutionRecorder()
        try await withTemporaryDirectory { root in
            _ = try await FolderEnumerator { isMainThread in
                recorder.record(isMainThread: isMainThread)
            }.enumerate(root: root, generation: 1)
        }
        XCTAssertEqual(recorder.isMainThread, false)
    }

    func testEnumerationSortsDirectoriesFirstWithLocalizedStandardNames() async throws {
        try await withTemporaryDirectory { root in
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Folder10"),
                withIntermediateDirectories: false
            )
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Folder2"),
                withIntermediateDirectories: false
            )
            try Data().write(to: root.appendingPathComponent("file10.txt"))
            try Data().write(to: root.appendingPathComponent("file2.txt"))
            try Data().write(to: root.appendingPathComponent(".hidden"))

            let result = try await FolderEnumerator().enumerate(root: root, generation: 7)

            XCTAssertEqual(result.generation, 7)
            XCTAssertEqual(result.items.map(\.name), ["Folder2", "Folder10", "file2.txt", "file10.txt"])
            XCTAssertTrue(result.items.prefix(2).allSatisfy(\.isDirectory))
            XCTAssertFalse(result.items.contains(where: \.isHidden))
            XCTAssertTrue(result.itemDiagnostics.isEmpty)
        }
    }

    func testEnumerationCanIncludeHiddenImmediateChildrenWithoutRecursing() async throws {
        try await withTemporaryDirectory { root in
            let childDirectory = root.appendingPathComponent("child", isDirectory: true)
            try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: false)
            try Data().write(to: childDirectory.appendingPathComponent("grandchild"))
            try Data().write(to: root.appendingPathComponent(".visible-to-request"))

            let result = try await FolderEnumerator().enumerate(
                root: root,
                showHidden: true,
                generation: 1
            )

            XCTAssertEqual(Set(result.items.map(\.name)), ["child", ".visible-to-request"])
            XCTAssertFalse(result.items.contains(where: { $0.name == "grandchild" }))
        }
    }

    func testEnumerationReturnsChildSymlinkWithoutTraversingItsTarget() async throws {
        try await withTemporaryDirectory { root in
            let observed = root.appendingPathComponent("observed", isDirectory: true)
            let target = root.appendingPathComponent("target", isDirectory: true)
            let link = observed.appendingPathComponent("linked-target", isDirectory: true)
            try FileManager.default.createDirectory(at: observed, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try Data().write(to: target.appendingPathComponent("target-child"))
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            let result = try await FolderEnumerator().enumerate(root: observed, generation: 1)

            XCTAssertEqual(result.items.map(\.name), ["linked-target"])
            XCTAssertFalse(result.items.contains(where: { $0.name == "target-child" }))
        }
    }

    func testRootErrorsKeepNSErrorMetadata() async throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        do {
            _ = try await FolderEnumerator().enumerate(root: missing, generation: 1)
            XCTFail("A missing folder must fail")
        } catch let error as FolderAccessError {
            guard case let .folderNotFound(url, metadata) = error else {
                return XCTFail("Expected folderNotFound, got \(error)")
            }
            XCTAssertEqual(url, missing.standardizedFileURL)
            XCTAssertFalse(metadata.domain.isEmpty)
        }

        try await withTemporaryDirectory { root in
            let file = root.appendingPathComponent("not-a-folder")
            try Data().write(to: file)
            do {
                _ = try await FolderEnumerator().enumerate(root: file, generation: 2)
                XCTFail("A regular file must not enumerate as a folder")
            } catch let error as FolderAccessError {
                guard case let .notDirectory(url, metadata) = error else {
                    return XCTFail("Expected notDirectory, got \(error)")
                }
                XCTAssertEqual(url, file.standardizedFileURL)
                XCTAssertFalse(metadata.domain.isEmpty)
            }
        }
    }

    func testLocationPolicyAcceptsOnlyFixedInternalLocalMetadata() {
        XCTAssertNil(FolderLocationPolicy.rejection(for: FolderVolumeMetadata(
            isLocal: true,
            isInternal: true,
            isRemovable: false,
            isEjectable: false
        )))
        XCTAssertEqual(
            FolderLocationPolicy.rejection(for: FolderVolumeMetadata(
                isLocal: nil,
                isInternal: true,
                isRemovable: false,
                isEjectable: false
            )),
            .metadataUnavailable
        )
        XCTAssertEqual(
            FolderLocationPolicy.rejection(for: FolderVolumeMetadata(
                isLocal: false,
                isInternal: true,
                isRemovable: false,
                isEjectable: false
            )),
            .notLocal
        )
        XCTAssertEqual(
            FolderLocationPolicy.rejection(for: FolderVolumeMetadata(
                isLocal: true,
                isInternal: false,
                isRemovable: false,
                isEjectable: false
            )),
            .notInternal
        )
        XCTAssertEqual(
            FolderLocationPolicy.rejection(for: FolderVolumeMetadata(
                isLocal: true,
                isInternal: true,
                isRemovable: true,
                isEjectable: false
            )),
            .removable
        )
        XCTAssertEqual(
            FolderLocationPolicy.rejection(for: FolderVolumeMetadata(
                isLocal: true,
                isInternal: true,
                isRemovable: false,
                isEjectable: true
            )),
            .ejectable
        )
    }

    func testLocationValidatorAcceptsTheCurrentInternalTemporaryDirectory() async throws {
        try await withTemporaryDirectory { root in
            let validated = try await FolderLocationValidator().validate(root)
            XCTAssertEqual(validated, root.standardizedFileURL)
        }
    }

    func testPermissionClassificationPreservesUnderlyingNSErrorMetadata() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        let classified = FolderAccessError.classifyRootError(
            url: URL(fileURLWithPath: "/private/fixture"),
            error: error
        )

        guard case let .permissionDenied(_, metadata) = classified else {
            return XCTFail("Expected permissionDenied, got \(classified)")
        }
        XCTAssertEqual(metadata.domain, NSCocoaErrorDomain)
        XCTAssertEqual(metadata.code, NSFileReadNoPermissionError)
        XCTAssertEqual(metadata.underlyingDomain, NSPOSIXErrorDomain)
        XCTAssertEqual(metadata.underlyingCode, Int(EACCES))
    }

    func testCoordinatorRejectsStaleAndCancelledCompletions() async throws {
        let coordinator = FolderLoadingCoordinator(enumerator: DelayedFolderEnumerator())
        let slowRoot = URL(fileURLWithPath: "/tmp/slow")
        let fastRoot = URL(fileURLWithPath: "/tmp/fast")

        let staleTask = Task {
            try await coordinator.load(root: slowRoot)
        }
        try await Task.sleep(for: .milliseconds(20))
        let currentResult = try await coordinator.load(root: fastRoot)
        let staleResult = try await staleTask.value

        XCTAssertEqual(
            currentResult,
            .accepted(
                request: FolderLoadRequest(generation: 2),
                outcome: .contents(DelayedFolderEnumerator.result(root: fastRoot, generation: 2))
            )
        )
        XCTAssertEqual(staleResult, .discarded(request: FolderLoadRequest(generation: 1)))

        let cancelledTask = Task {
            try await coordinator.load(root: slowRoot)
        }
        try await Task.sleep(for: .milliseconds(20))
        cancelledTask.cancel()
        let cancelledResult = try await cancelledTask.value
        XCTAssertEqual(
            cancelledResult,
            .discarded(request: FolderLoadRequest(generation: 3))
        )
    }
}

private struct DelayedFolderEnumerator: FolderEnumerating {
    func enumerate(
        root: URL,
        showHidden: Bool,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        if root.lastPathComponent == "slow" {
            try await Task.sleep(for: .milliseconds(100))
        }
        return Self.result(root: root, generation: generation)
    }

    static func result(root: URL, generation: UInt64) -> FolderEnumerationResult {
        FolderEnumerationResult(
            root: root,
            generation: generation,
            items: [],
            itemDiagnostics: []
        )
    }
}

private final class ExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValue: Bool?

    func record(isMainThread: Bool) {
        lock.withLock {
            recordedValue = isMainThread
        }
    }

    var isMainThread: Bool? {
        lock.withLock { recordedValue }
    }
}

private func withTemporaryDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    do {
        try await body(root)
    } catch {
        let bodyError = error
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            throw TemporaryDirectoryError.bodyAndCleanup(
                body: String(describing: bodyError),
                cleanup: String(describing: error)
            )
        }
        throw bodyError
    }
    try FileManager.default.removeItem(at: root)
}

private enum TemporaryDirectoryError: Error {
    case bodyAndCleanup(body: String, cleanup: String)
}
