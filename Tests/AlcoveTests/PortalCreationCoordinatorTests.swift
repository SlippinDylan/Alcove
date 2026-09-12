import AppKit
import AlcoveCore
import XCTest
@testable import Alcove

final class PortalCreationCoordinatorTests: XCTestCase {
    @MainActor
    func testValidTransactionCreatesExactlyOneEmptyPortal() async throws {
        let frame = NSRect(x: 10, y: 20, width: 300, height: 240)
        let frameSelector = FrameSelectorStub(frames: [frame])
        let portalCoordinator = PortalCoordinatorStub()
        let coordinator = PortalCreationCoordinator(
            frameSelector: frameSelector,
            portalCoordinator: portalCoordinator,
            errorPresenter: CreationErrorPresenterSpy()
        )

        let created = await coordinator.runCreation()
        XCTAssertTrue(created)

        XCTAssertEqual(portalCoordinator.requests, [
            PortalRequest(
                folder: nil,
                frame: frame,
                capacity: .minimum
            ),
        ])
        XCTAssertEqual(coordinator.state, .idle)
    }

    @MainActor
    func testFrameCancellationLeavesNoPartialPortal() async {
        let portalCoordinator = PortalCoordinatorStub()
        let frameCancelled = PortalCreationCoordinator(
            frameSelector: FrameSelectorStub(frames: [nil]),
            portalCoordinator: portalCoordinator,
            errorPresenter: CreationErrorPresenterSpy()
        )
        let frameResult = await frameCancelled.runCreation()
        XCTAssertFalse(frameResult)
        XCTAssertTrue(portalCoordinator.requests.isEmpty)

    }

    @MainActor
    func testTwoSequentialTransactionsCreateTwoPortals() async {
        let frames = [
            NSRect(x: 0, y: 0, width: 300, height: 240),
            NSRect(x: 400, y: 300, width: 320, height: 260),
        ]
        let portalCoordinator = PortalCoordinatorStub()
        let coordinator = PortalCreationCoordinator(
            frameSelector: FrameSelectorStub(frames: frames.map(Optional.some)),
            portalCoordinator: portalCoordinator,
            errorPresenter: CreationErrorPresenterSpy()
        )

        let firstCreated = await coordinator.runCreation()
        let secondCreated = await coordinator.runCreation()
        XCTAssertTrue(firstCreated)
        XCTAssertTrue(secondCreated)

        XCTAssertEqual(portalCoordinator.requests, [
            PortalRequest(folder: nil, frame: frames[0], capacity: .minimum),
            PortalRequest(folder: nil, frame: frames[1], capacity: .minimum),
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

    @MainActor
    func testCreationOverlaySupportsKeyboardAndAccessibilityDefaultFrame() throws {
        let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let overlay = PortalCreationOverlayView(
            screenFrame: visibleFrame,
            visibleFrame: visibleFrame,
            grid: try CreationGrid(metrics: GridMetrics(iconSize: .medium))
        )
        var selectedFrame: PortalFrameSelection?
        overlay.onCompletion = { selectedFrame = $0 }

        XCTAssertEqual(overlay.accessibilityRole(), .button)
        XCTAssertEqual(
            overlay.accessibilityLabel(),
            NSLocalizedString("Create portal area", comment: "")
        )
        XCTAssertTrue(overlay.accessibilityPerformPress())
        let selection = try XCTUnwrap(selectedFrame)
        XCTAssertEqual(selection.capacity, .minimum)
        XCTAssertTrue(visibleFrame.contains(selection.frame))
        XCTAssertTrue(selection.frame.contains(NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)))
    }
}

private struct PortalRequest: Equatable {
    let folder: URL?
    let frame: NSRect?
    let capacity: GridCapacity
    let iconLayout: PortalIconLayout

    init(
        folder: URL?,
        frame: NSRect?,
        capacity: GridCapacity,
        iconLayout: PortalIconLayout = .fixed(.medium)
    ) {
        self.folder = folder
        self.frame = frame
        self.capacity = capacity
        self.iconLayout = iconLayout
    }
}

@MainActor
private final class FrameSelectorStub: PortalFrameSelecting {
    private var frames: [NSRect?]
    private let iconLayout: PortalIconLayout
    private(set) var cancelCount = 0

    init(
        frames: [NSRect?],
        iconLayout: PortalIconLayout = .fixed(.medium)
    ) {
        self.frames = frames
        self.iconLayout = iconLayout
    }

    func selectFrame() async -> PortalFrameSelection? {
        guard !frames.isEmpty else { return nil }
        return frames.removeFirst().map {
            PortalFrameSelection(
                frame: $0,
                capacity: .minimum,
                iconLayout: iconLayout
            )
        }
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class SuspendedFrameSelector: PortalFrameSelecting {
    private var continuation: CheckedContinuation<PortalFrameSelection?, Never>?
    private(set) var selectionCount = 0

    func selectFrame() async -> PortalFrameSelection? {
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
        continuation.resume(
            returning: frame.map {
                PortalFrameSelection(frame: $0, capacity: .minimum)
            }
        )
    }
}

@MainActor
private final class PortalCoordinatorStub: PortalCoordinating {
    private(set) var requests: [PortalRequest] = []

    func restorePortals() async throws {}

    func stop() {}

    func prepareForTermination() async {}

    func createPortal(
        for folderURL: URL?,
        frame: NSRect?,
        gridCapacity: GridCapacity,
        iconLayout: PortalIconLayout
    ) async throws {
        requests.append(
            PortalRequest(
                folder: folderURL,
                frame: frame,
                capacity: gridCapacity,
                iconLayout: iconLayout
            )
        )
    }
}

@MainActor
private final class CreationErrorPresenterSpy: PortalCreationErrorPresenting {
    private(set) var presentedErrors: [Error] = []

    func present(_ error: Error) {
        presentedErrors.append(error)
    }
}
