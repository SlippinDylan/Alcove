import AlcoveCore
import AppKit

@MainActor
protocol PortalCoordinating: AnyObject {
    func restorePortals() async throws
    func createPortal(for folderURL: URL, frame: NSRect?) async throws
}

@MainActor
final class PortalCoordinator: PortalCoordinating {
    private let locationValidator: FolderLocationValidator
    private let store: any PortalStoring
    private let windowFactory: any PortalWindowBuilding
    private var windows: [PortalID: any PortalWindowPresenting] = [:]
    private var persistenceTask: Task<Void, Never>?
    private(set) var portalStates: [Portal] = []
    private(set) var persistenceError: Error?

    init(
        locationValidator: FolderLocationValidator = FolderLocationValidator(),
        store: any PortalStoring = PortalStore(),
        windowFactory: any PortalWindowBuilding = PortalWindowFactory()
    ) {
        self.locationValidator = locationValidator
        self.store = store
        self.windowFactory = windowFactory
    }

    func restorePortals() async throws {
        let portals = try await store.load()
        portalStates = portals
        for portal in portals {
            present(portal)
        }
    }

    func createPortal(for folderURL: URL, frame: NSRect? = nil) async throws {
        let folderURL = try await locationValidator.validate(folderURL)
        try Task.checkCancellation()
        await persistenceTask?.value

        let portal = try Portal(
            folderURL: folderURL,
            frame: frame ?? Self.defaultFrame()
        )
        let updatedPortals = portalStates + [portal]
        try await store.save(updatedPortals)
        portalStates = updatedPortals
        present(portal)
    }

    func waitForPersistenceForTesting() async {
        await persistenceTask?.value
    }

    private func present(_ portal: Portal) {
        let window = windowFactory.makeWindow(for: portal)
        window.onFrameChange = { [weak self] frame in
            self?.recordFrame(frame, portalID: portal.id)
        }
        windows[portal.id] = window
        window.present()
    }

    private func recordFrame(_ frame: NSRect, portalID: PortalID) {
        guard let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
            return
        }
        do {
            try portalStates[index].updateFrame(frame)
        } catch {
            persistenceError = error
            return
        }

        let snapshot = portalStates
        let previousTask = persistenceTask
        persistenceTask = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            do {
                try await store.save(snapshot)
                persistenceError = nil
            } catch {
                persistenceError = error
            }
        }
    }

    private static func defaultFrame() -> NSRect {
        let size = NSSize(width: 560, height: 480)
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

enum StartupFolderResolver {
    static func resolve(arguments: [String]) -> URL? {
        guard arguments.count == 3, arguments[1] == "--folder" else { return nil }
        return URL(fileURLWithPath: arguments[2]).standardizedFileURL
    }
}
