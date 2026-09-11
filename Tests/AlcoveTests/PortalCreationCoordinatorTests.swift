import AppKit
import XCTest
@testable import Alcove

final class PortalCreationCoordinatorTests: XCTestCase {
    @MainActor
    func testValidTransactionCreatesExactlyOnePortal() async {
        let frame = NSRect(x: 10, y: 20, width: 300, height: 240)
        let folder = URL(fileURLWithPath: "/tmp/folder")
        let frameSelector = FrameSelectorStub(frames: [frame])
        let folderPicker = FolderPickerStub(folders: [folder])
        let portalCoordinator = PortalCoordinatorStub()
        let coordinator = PortalCreationCoordinator(
            frameSelector: frameSelector,
            folderPicker: folderPicker,
            portalCoordinator: portalCoordinator,
            errorPresenter: CreationErrorPresenterSpy()
        )

        let created = await coordinator.runCreation()
        XCTAssertTrue(created)

        XCTAssertEqual(portalCoordinator.requests, [PortalRequest(folder: folder, frame: frame)])
        XCTAssertEqual(coordinator.state, .idle)
    }

    @MainActor
    func testFrameAndFolderCancellationLeaveNoPartialPortal() async {
        let portalCoordinator = PortalCoordinatorStub()
        let frameCancelled = PortalCreationCoordinator(
            frameSelector: FrameSelectorStub(frames: [nil]),
            folderPicker: FolderPickerStub(folders: []),
            portalCoordinator: portalCoordinator,
            errorPresenter: CreationErrorPresenterSpy()
        )
        let frameResult = await frameCancelled.runCreation()
        XCTAssertFalse(frameResult)
        XCTAssertTrue(portalCoordinator.requests.isEmpty)

        let folderCancelled = PortalCreationCoordinator(
            frameSelector: FrameSelectorStub(frames: [NSRect(x: 0, y: 0, width: 300, height: 240)]),
            folderPicker: FolderPickerStub(folders: [nil]),
            portalCoordinator: portalCoordinator,
            errorPresenter: CreationErrorPresenterSpy()
        )
        let folderResult = await folderCancelled.runCreation()
        XCTAssertFalse(folderResult)
        XCTAssertTrue(portalCoordinator.requests.isEmpty)
    }

    @MainActor
    func testRejectedFolderPresentsErrorAndRetriesWithoutChangingFrame() async {
        let frame = NSRect(x: 40, y: 50, width: 320, height: 260)
        let rejected = URL(fileURLWithPath: "/tmp/external")
        let accepted = URL(fileURLWithPath: "/tmp/internal")
        let portalCoordinator = PortalCoordinatorStub(errors: [
            .unsupportedLocation(url: rejected, reason: .notInternal),
            nil,
        ])
        let presenter = CreationErrorPresenterSpy()
        let coordinator = PortalCreationCoordinator(
            frameSelector: FrameSelectorStub(frames: [frame]),
            folderPicker: FolderPickerStub(folders: [rejected, accepted]),
            portalCoordinator: portalCoordinator,
            errorPresenter: presenter
        )

        let created = await coordinator.runCreation()
        XCTAssertTrue(created)

        XCTAssertEqual(portalCoordinator.requests, [
            PortalRequest(folder: rejected, frame: frame),
            PortalRequest(folder: accepted, frame: frame),
        ])
        XCTAssertEqual(presenter.presentedErrors.count, 1)
    }

    @MainActor
    func testTwoSequentialTransactionsCreateTwoPortals() async {
        let frames = [
            NSRect(x: 0, y: 0, width: 300, height: 240),
            NSRect(x: 400, y: 300, width: 320, height: 260),
        ]
        let folders = [
            URL(fileURLWithPath: "/tmp/one"),
            URL(fileURLWithPath: "/tmp/two"),
        ]
        let portalCoordinator = PortalCoordinatorStub()
        let coordinator = PortalCreationCoordinator(
            frameSelector: FrameSelectorStub(frames: frames.map(Optional.some)),
            folderPicker: FolderPickerStub(folders: folders.map(Optional.some)),
            portalCoordinator: portalCoordinator,
            errorPresenter: CreationErrorPresenterSpy()
        )

        let firstCreated = await coordinator.runCreation()
        let secondCreated = await coordinator.runCreation()
        XCTAssertTrue(firstCreated)
        XCTAssertTrue(secondCreated)

        XCTAssertEqual(portalCoordinator.requests, [
            PortalRequest(folder: folders[0], frame: frames[0]),
            PortalRequest(folder: folders[1], frame: frames[1]),
        ])
    }

    @MainActor
    func testOpenPanelConfigurationIsDirectoryOnly() {
        let panel = NSOpenPanel()
        OpenPanelFolderPicker.configure(panel)

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canCreateDirectories)
        XCTAssertTrue(panel.resolvesAliases)
    }

    @MainActor
    func testRepeatedBeginWhileActiveDoesNotStartAnotherTransaction() async {
        let frameSelector = SuspendedFrameSelector()
        let coordinator = PortalCreationCoordinator(
            frameSelector: frameSelector,
            folderPicker: FolderPickerStub(folders: []),
            portalCoordinator: PortalCoordinatorStub(),
            errorPresenter: CreationErrorPresenterSpy()
        )

        coordinator.beginPortalCreation()
        await Task.yield()
        coordinator.beginPortalCreation()
        await Task.yield()

        XCTAssertEqual(frameSelector.selectionCount, 1)
        frameSelector.complete(with: nil)
        await coordinator.waitForCurrentCreation()
        XCTAssertEqual(coordinator.state, .idle)
    }
}

private struct PortalRequest: Equatable {
    let folder: URL
    let frame: NSRect?
}

@MainActor
private final class FrameSelectorStub: PortalFrameSelecting {
    private var frames: [NSRect?]
    private(set) var cancelCount = 0

    init(frames: [NSRect?]) {
        self.frames = frames
    }

    func selectFrame() async -> NSRect? {
        guard !frames.isEmpty else { return nil }
        return frames.removeFirst()
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class SuspendedFrameSelector: PortalFrameSelecting {
    private var continuation: CheckedContinuation<NSRect?, Never>?
    private(set) var selectionCount = 0

    func selectFrame() async -> NSRect? {
        selectionCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        complete(with: nil)
    }

    func complete(with frame: NSRect?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: frame)
    }
}

@MainActor
private final class FolderPickerStub: FolderPicking {
    private var folders: [URL?]
    private(set) var cancelCount = 0

    init(folders: [URL?]) {
        self.folders = folders
    }

    func chooseFolder() async -> URL? {
        guard !folders.isEmpty else { return nil }
        return folders.removeFirst()
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class PortalCoordinatorStub: PortalCoordinating {
    private var errors: [FolderAccessError?]
    private(set) var requests: [PortalRequest] = []

    init(errors: [FolderAccessError?] = []) {
        self.errors = errors
    }

    func createPortal(for folderURL: URL, frame: NSRect?) async throws {
        requests.append(PortalRequest(folder: folderURL, frame: frame))
        if !errors.isEmpty, let error = errors.removeFirst() {
            throw error
        }
    }
}

@MainActor
private final class CreationErrorPresenterSpy: PortalCreationErrorPresenting {
    private(set) var presentedErrors: [Error] = []

    func present(_ error: Error) {
        presentedErrors.append(error)
    }
}
