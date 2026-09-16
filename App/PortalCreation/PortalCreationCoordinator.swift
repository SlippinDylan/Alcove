import AppKit
import AlcoveCore

enum PortalCreationState: Equatable {
    case idle
    case selectingFrame
    case creating
}

@MainActor
protocol PortalCreationRequesting: AnyObject {
    func beginPortalCreation()
    func cancelPortalCreation()
}

@MainActor
protocol PortalFrameSelecting: AnyObject {
    func selectFrame() async -> PortalFrameSelection?
    func cancel()
}

struct PortalFrameSelection: Equatable {
    let frame: NSRect
    let capacity: GridCapacity
    let iconLayout: PortalIconLayout

    init(
        frame: NSRect,
        capacity: GridCapacity,
        iconLayout: PortalIconLayout = .fixed(.medium)
    ) {
        self.frame = frame
        self.capacity = capacity
        self.iconLayout = iconLayout
    }
}

@MainActor
final class PortalCreationCoordinator: PortalCreationRequesting {
    private let frameSelector: any PortalFrameSelecting
    private let portalCoordinator: any PortalCoordinating
    private let errorPresenter: any PortalCreationErrorPresenting
    private var creationTask: Task<Void, Never>?
    private(set) var state: PortalCreationState = .idle

    init(
        frameSelector: any PortalFrameSelecting,
        portalCoordinator: any PortalCoordinating,
        errorPresenter: any PortalCreationErrorPresenting = PortalCreationErrorPresenter()
    ) {
        self.frameSelector = frameSelector
        self.portalCoordinator = portalCoordinator
        self.errorPresenter = errorPresenter
    }

    func beginPortalCreation() {
        guard creationTask == nil else { return }
        creationTask = Task { [weak self] in
            guard let self else { return }
            await runCreation()
            creationTask = nil
        }
    }

    func cancelPortalCreation() {
        creationTask?.cancel()
        frameSelector.cancel()
    }

    func waitForCurrentCreation() async {
        await creationTask?.value
    }

    @discardableResult
    func runCreation() async -> Bool {
        guard state == .idle else { return false }
        state = .selectingFrame
        defer { state = .idle }

        guard let selection = await frameSelector.selectFrame(), !Task.isCancelled else {
            return false
        }

        state = .creating
        do {
            try await portalCoordinator.createPortal(
                for: nil,
                frame: selection.frame,
                gridCapacity: selection.capacity,
                iconLayout: selection.iconLayout
            )
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorPresenter.present(error)
            return false
        }
    }
}
