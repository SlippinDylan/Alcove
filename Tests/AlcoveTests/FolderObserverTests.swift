import CoreServices
import Foundation
import XCTest
@testable import Alcove

final class FolderObserverTests: XCTestCase {
    func testRecoveryFlagsTakePrecedenceOverOrdinaryEvents() {
        let ordinary = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
        XCTAssertEqual(FolderObservationPolicy.action(for: [ordinary]), .refreshSnapshot)

        let recoveryFlags: [FSEventStreamEventFlags] = [
            FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
            FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
        ]
        for flag in recoveryFlags {
            XCTAssertEqual(
                FolderObservationPolicy.action(for: [ordinary, flag]),
                .rebuildObservation
            )
        }
    }

    @MainActor
    func testStartAndStopOwnExactlyOneStream() async throws {
        try await withObservationDirectory { directory in
            let streams = StreamCollection()
            let identity = FolderRootIdentity(device: 1, inode: 2)
            let coordinator = makeCoordinator(
                identities: IdentitySequence([identity]),
                streams: streams
            )

            try await coordinator.start(root: directory)
            XCTAssertEqual(streams.items.count, 1)
            XCTAssertEqual(streams.items[0].startedRoots, [directory.resolvingSymlinksInPath()])

            coordinator.stop()
            coordinator.stop()
            XCTAssertEqual(streams.items[0].stopCount, 1)
        }
    }

    @MainActor
    func testOrdinaryEventsDebounceIntoOneFullRefresh() async throws {
        try await withObservationDirectory { directory in
            let streams = StreamCollection()
            var refreshCount = 0
            let coordinator = makeCoordinator(
                identities: IdentitySequence([FolderRootIdentity(device: 1, inode: 2)]),
                streams: streams,
                debounceDuration: .zero,
                onRefresh: { refreshCount += 1 }
            )
            try await coordinator.start(root: directory)

            streams.items[0].emit(FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated))
            streams.items[0].emit(FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved))
            await allowTasksToRun()

            XCTAssertEqual(refreshCount, 1)
        }
    }

    @MainActor
    func testRecoveryRestartsBeforeRefreshingWhenIdentityMatches() async throws {
        try await withObservationDirectory { directory in
            let identity = FolderRootIdentity(device: 1, inode: 2)
            let streams = StreamCollection()
            var refreshSawStreamCount: Int?
            let coordinator = makeCoordinator(
                identities: IdentitySequence([identity, identity]),
                streams: streams,
                onRefresh: { refreshSawStreamCount = streams.items.count }
            )
            try await coordinator.start(root: directory)

            streams.items[0].emit(
                FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
            )
            try await waitUntil { streams.items.count == 2 && refreshSawStreamCount != nil }

            XCTAssertEqual(streams.items[0].stopCount, 1)
            XCTAssertEqual(streams.items[1].startedRoots.count, 1)
            XCTAssertEqual(refreshSawStreamCount, 2)
        }
    }

    @MainActor
    func testRecoveryRejectsSamePathReplacement() async throws {
        try await withObservationDirectory { directory in
            let original = FolderRootIdentity(device: 1, inode: 2)
            let replacement = FolderRootIdentity(device: 1, inode: 3)
            let streams = StreamCollection()
            var failure: Error?
            var refreshCount = 0
            let coordinator = makeCoordinator(
                identities: IdentitySequence([original, replacement]),
                streams: streams,
                onRefresh: { refreshCount += 1 },
                onFailure: { failure = $0 }
            )
            try await coordinator.start(root: directory)

            streams.items[0].emit(
                FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
            )
            try await waitUntil { failure != nil }

            XCTAssertEqual(failure as? FolderAccessError, .folderReplaced(url: directory))
            XCTAssertEqual(streams.items.count, 1)
            XCTAssertEqual(refreshCount, 0)
        }
    }

    @MainActor
    func testStoppedSessionRejectsLateEvents() async throws {
        try await withObservationDirectory { directory in
            let streams = StreamCollection()
            var refreshCount = 0
            let coordinator = makeCoordinator(
                identities: IdentitySequence([FolderRootIdentity(device: 1, inode: 2)]),
                streams: streams,
                debounceDuration: .zero,
                onRefresh: { refreshCount += 1 }
            )
            try await coordinator.start(root: directory)
            coordinator.stop()

            streams.items[0].emit(FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated))
            await allowTasksToRun()

            XCTAssertEqual(refreshCount, 0)
        }
    }

    @MainActor
    func testSystemFSEventsStreamStartsAndStopsForARealDirectory() async throws {
        try await withObservationDirectory { directory in
            let observer = FSEventsFolderObserver(eventHandler: { _ in })
            try observer.start(root: directory)
            observer.stop()
        }
    }

    @MainActor
    func testRealFileCreationTriggersAFullRefreshRequest() async throws {
        try await withObservationDirectory { directory in
            let refresh = expectation(description: "FSEvents refresh")
            let coordinator = FolderObservationCoordinator(
                debounceDuration: .zero,
                onRefresh: { refresh.fulfill() },
                onFailure: { error in XCTFail("Unexpected observation failure: \(error)") }
            )
            try await coordinator.start(root: directory)

            try Data("created".utf8).write(to: directory.appendingPathComponent("created.txt"))
            await fulfillment(of: [refresh], timeout: 3)
            coordinator.stop()
        }
    }

    @MainActor
    private func makeCoordinator(
        identities: IdentitySequence,
        streams: StreamCollection,
        debounceDuration: Duration = .milliseconds(200),
        onRefresh: @escaping @MainActor () -> Void = {},
        onFailure: @escaping @MainActor (Error) -> Void = { _ in }
    ) -> FolderObservationCoordinator {
        FolderObservationCoordinator(
            identityProvider: StubIdentityProvider(sequence: identities),
            streamFactory: { handler in
                let stream = StreamSpy(handler: handler)
                streams.items.append(stream)
                return stream
            },
            debounceDuration: debounceDuration,
            onRefresh: onRefresh,
            onFailure: onFailure
        )
    }

    @MainActor
    private func allowTasksToRun() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        throw FolderObserverTestError.conditionNotMet
    }
}

private actor IdentitySequence {
    private var identities: [FolderRootIdentity]

    init(_ identities: [FolderRootIdentity]) {
        self.identities = identities
    }

    func next() throws -> FolderRootIdentity {
        guard !identities.isEmpty else { throw FolderObserverTestError.missingIdentity }
        return identities.removeFirst()
    }
}

private struct StubIdentityProvider: FolderRootIdentifying {
    let sequence: IdentitySequence

    func identity(for url: URL) async throws -> FolderRootIdentity {
        try await sequence.next()
    }
}

@MainActor
private final class StreamCollection {
    var items: [StreamSpy] = []
}

@MainActor
private final class StreamSpy: FolderEventStreaming {
    private let handler: @MainActor ([FSEventStreamEventFlags]) -> Void
    private(set) var startedRoots: [URL] = []
    private(set) var stopCount = 0

    init(handler: @escaping @MainActor ([FSEventStreamEventFlags]) -> Void) {
        self.handler = handler
    }

    func start(root: URL) throws {
        startedRoots.append(root)
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ flags: FSEventStreamEventFlags) {
        handler([flags])
    }
}

private enum FolderObserverTestError: Error {
    case conditionNotMet
    case missingIdentity
}

@MainActor
private func withObservationDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("alcove-observer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    do {
        try await body(directory)
    } catch {
        let bodyError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw FolderObserverTestError.conditionNotMet
        }
        throw bodyError
    }
    try FileManager.default.removeItem(at: directory)
}
