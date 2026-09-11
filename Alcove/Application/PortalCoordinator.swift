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
    private let tabFolderPicker: any FolderPicking
    private let errorPresenter: any PortalCreationErrorPresenting
    private let lastTabRemovalConfirmer: any LastTabRemovalConfirming
    private var windows: [PortalID: any PortalWindowPresenting] = [:]
    private var persistenceTask: Task<Void, Never>?
    private var tabTask: Task<Void, Never>?
    private(set) var portalStates: [Portal] = []
    private(set) var persistenceError: Error?

    init(
        locationValidator: FolderLocationValidator = FolderLocationValidator(),
        store: any PortalStoring = PortalStore(),
        windowFactory: any PortalWindowBuilding = PortalWindowFactory(),
        tabFolderPicker: any FolderPicking = OpenPanelFolderPicker(),
        errorPresenter: any PortalCreationErrorPresenting = PortalCreationErrorPresenter(),
        lastTabRemovalConfirmer: any LastTabRemovalConfirming = LastTabRemovalConfirmer()
    ) {
        self.locationValidator = locationValidator
        self.store = store
        self.windowFactory = windowFactory
        self.tabFolderPicker = tabFolderPicker
        self.errorPresenter = errorPresenter
        self.lastTabRemovalConfirmer = lastTabRemovalConfirmer
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

    func waitForTabMutationForTesting() async {
        await tabTask?.value
    }

    private func present(_ portal: Portal) {
        let window = windowFactory.makeWindow(for: portal)
        window.onFrameChange = { [weak self] frame in
            self?.recordFrame(frame, portalID: portal.id)
        }
        window.onSelectTab = { [weak self] tabID in
            self?.startTabTask {
                try await self?.selectTab(tabID, in: portal.id)
            }
        }
        window.onAddTab = { [weak self] in
            self?.startTabTask {
                await self?.addTab(to: portal.id)
            }
        }
        window.onCloseTab = { [weak self] tabID in
            self?.startTabTask {
                await self?.closeTab(tabID, in: portal.id)
            }
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

    private func startTabTask(_ operation: @escaping @MainActor () async throws -> Void) {
        guard tabTask == nil else { return }
        tabTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
            } catch {
                persistenceError = error
            }
            tabTask = nil
        }
    }

    func selectTab(_ tabID: FolderTabID, in portalID: PortalID) async throws {
        guard let index = portalStates.firstIndex(where: { $0.id == portalID }) else { return }
        var portal = portalStates[index]
        try portal.selectTab(tabID)
        try await commit(portal, at: index)
    }

    func addTab(to portalID: PortalID) async {
        guard let index = portalStates.firstIndex(where: { $0.id == portalID }) else { return }
        while !Task.isCancelled {
            guard let folderURL = await tabFolderPicker.chooseFolder() else { return }
            do {
                let folderURL = try await locationValidator.validate(folderURL)
                var portal = portalStates[index]
                let tabID = try portal.appendTab(folderURL: folderURL)
                try portal.selectTab(tabID)
                try await commit(portal, at: index)
                return
            } catch is CancellationError {
                return
            } catch {
                errorPresenter.present(error)
            }
        }
    }

    func closeTab(_ tabID: FolderTabID, in portalID: PortalID) async {
        guard let index = portalStates.firstIndex(where: { $0.id == portalID }) else { return }
        let currentPortal = portalStates[index]
        if currentPortal.tabs.count == 1 {
            guard let tab = currentPortal.tabs.first,
                  await lastTabRemovalConfirmer.confirmRemoval(
                    folderName: tab.folderURL.lastPathComponent
                  ) else {
                return
            }
            var updatedPortals = portalStates
            updatedPortals.remove(at: index)
            do {
                try await store.save(updatedPortals)
                portalStates = updatedPortals
                windows.removeValue(forKey: portalID)?.close()
            } catch {
                persistenceError = error
            }
            return
        }

        var portal = currentPortal
        do {
            try portal.removeTab(tabID)
            try await commit(portal, at: index)
        } catch {
            persistenceError = error
        }
    }

    private func commit(_ portal: Portal, at index: Int) async throws {
        await persistenceTask?.value
        var updatedPortals = portalStates
        updatedPortals[index] = portal
        try await store.save(updatedPortals)
        portalStates = updatedPortals
        windows[portal.id]?.updatePortal(portal)
        persistenceError = nil
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
