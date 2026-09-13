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

    @MainActor
    func testCreationOverlayRejectsAnOccupiedDefaultFrame() throws {
        let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let grid = try CreationGrid(metrics: GridMetrics(iconSize: .medium))
        let probe = PortalCreationOverlayView(
            screenFrame: visibleFrame,
            visibleFrame: visibleFrame,
            grid: grid
        )
        var occupiedFrame: NSRect?
        probe.onCompletion = { occupiedFrame = $0?.frame }
        XCTAssertTrue(probe.selectDefaultFrame())

        let overlay = PortalCreationOverlayView(
            screenFrame: visibleFrame,
            visibleFrame: visibleFrame,
            grid: grid,
            occupiedFrames: [try XCTUnwrap(occupiedFrame)]
        )
        var didComplete = false
        overlay.onCompletion = { _ in didComplete = true }

        XCTAssertFalse(overlay.selectDefaultFrame())
        XCTAssertFalse(didComplete)
    }

    func testCreationSkeletonMatchesPortalSectionsAndUsesCompleteTiles() throws {
        let grid = try CreationGrid(metrics: GridMetrics(iconSize: .medium))
        let frame = NSRect(x: 20, y: 30, width: 500, height: 360)
        let capacity = try GridCapacity(columns: 4, rows: 2)
        let skeleton = PortalCreationSkeletonGeometry(
            frame: frame,
            capacity: capacity,
            grid: grid
        )

        XCTAssertEqual(skeleton.cornerRadius, 24)
        XCTAssertEqual(skeleton.topSeparatorStart, NSPoint(x: frame.minX, y: frame.maxY - 40))
        XCTAssertEqual(skeleton.topSeparatorEnd, NSPoint(x: frame.maxX, y: frame.maxY - 40))
        XCTAssertEqual(skeleton.bottomSeparatorStart, NSPoint(x: frame.minX, y: frame.minY + 40))
        XCTAssertEqual(skeleton.bottomSeparatorEnd, NSPoint(x: frame.maxX, y: frame.minY + 40))

        XCTAssertEqual(skeleton.tileFrames.count, capacity.columns * capacity.rows)
        let firstTile = try XCTUnwrap(skeleton.tileFrames.first)
        XCTAssertEqual(firstTile.size, grid.metrics.itemSize)
        XCTAssertEqual(firstTile.minX, frame.minX + grid.metrics.contentInsets.leading)
        XCTAssertEqual(
            firstTile.maxY,
            frame.maxY - PortalLayoutMetrics.tabBarHeight - grid.metrics.contentInsets.top
        )

        let firstGhostTile = skeleton.tileFrame(row: -1, column: -1)
        XCTAssertEqual(firstGhostTile.size, firstTile.size)
        XCTAssertEqual(firstGhostTile.minX, firstTile.minX - grid.columnIncrement)
        XCTAssertEqual(firstGhostTile.minY, firstTile.minY + grid.rowIncrement)
    }

    func testCreationSkeletonClampsInjectedCornerRadiusToThePreviewFrame() throws {
        let grid = try CreationGrid(metrics: GridMetrics(iconSize: .medium))
        let skeleton = PortalCreationSkeletonGeometry(
            frame: NSRect(x: 0, y: 0, width: 30, height: 40),
            capacity: .minimum,
            grid: grid,
            cornerRadius: 100
        )

        XCTAssertEqual(skeleton.cornerRadius, 15)
        XCTAssertEqual(PortalCreationSkeletonGeometry.validatedCornerRadius(-1), 0)
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
