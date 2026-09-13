import AlcoveCore
import AppKit

@MainActor
protocol PortalCoordinating: AnyObject {
    func restorePortals() async throws
    func createPortal(
        for folderURL: URL?,
        frame: NSRect?,
        gridCapacity: GridCapacity,
        iconLayout: PortalIconLayout
    ) async throws
    func stop()
    func prepareForTermination() async
}

@MainActor
final class PortalCoordinator: PortalCoordinating {
    private let locationValidator: FolderLocationValidator
    private let store: any PortalStoring
    private let windowFactory: any PortalWindowBuilding
    private let tabFolderPicker: any FolderPicking
    private let errorPresenter: any PortalCreationErrorPresenting
    private let persistenceErrorPresenter: any PortalPersistenceErrorPresenting
    private let lastTabRemovalConfirmer: any LastTabRemovalConfirming
    private let displaySnapshotProvider: DisplayPlacementObserver.SnapshotProvider
    private let displayNotificationCenter: NotificationCenter
    private var windows: [PortalID: any PortalWindowPresenting] = [:]
    private var placementSessions: [PortalID: PlacementSession] = [:]
    private var deferredTopologyPortals = Set<PortalID>()
    private var pendingUserPlacements: [PortalID: PendingUserPlacement] = [:]
    private var pendingPlacementAttempts: [PortalID: UInt64] = [:]
    private var nextUserPlacementGeneration: UInt64 = 0
    private var mutationTail: Task<Void, Never>?
    private var mutationGeneration: UInt64 = 0
    private var folderSelectionTask: Task<Void, Never>?
    private var tabMutationTasks: [UUID: Task<Void, Never>] = [:]
    private var hasLoadedPersistentState = false
    private(set) var portalStates: [Portal] = []
    private(set) var persistenceError: Error?
    private(set) var displayError: Error?
    var onPortalsChanged: (([PortalMenuEntry]) -> Void)? {
        didSet { publishPortalMenu() }
    }
    private lazy var displayObserver = DisplayPlacementObserver(
        center: displayNotificationCenter,
        snapshotProvider: displaySnapshotProvider,
        eventHandler: { [weak self] result in
            self?.reconcileDisplayTopology(result)
        }
    )

    init(
        locationValidator: FolderLocationValidator = FolderLocationValidator(),
        store: (any PortalStoring)? = nil,
        windowFactory: any PortalWindowBuilding = PortalWindowFactory(),
        tabFolderPicker: any FolderPicking = OpenPanelFolderPicker(),
        errorPresenter: any PortalCreationErrorPresenting = PortalCreationErrorPresenter(),
        persistenceErrorPresenter: any PortalPersistenceErrorPresenting = PortalPersistenceErrorPresenter(),
        lastTabRemovalConfirmer: any LastTabRemovalConfirming = LastTabRemovalConfirmer(),
        displayNotificationCenter: NotificationCenter = .default,
        displaySnapshotProvider: @escaping DisplayPlacementObserver.SnapshotProvider = {
            DisplaySnapshot.captureResult()
        }
    ) {
        self.locationValidator = locationValidator
        self.store = store ?? PortalStore(
            legacyDisplayResolver: SystemLegacyDisplayResolver()
        )
        self.windowFactory = windowFactory
        self.tabFolderPicker = tabFolderPicker
        self.errorPresenter = errorPresenter
        self.persistenceErrorPresenter = persistenceErrorPresenter
        self.lastTabRemovalConfirmer = lastTabRemovalConfirmer
        self.displayNotificationCenter = displayNotificationCenter
        self.displaySnapshotProvider = displaySnapshotProvider
    }

    func restorePortals() async throws {
        try await performMutation { [weak self] in
            guard let self else { return }
            let portals = try await store.load()
            portalStates = portals
            hasLoadedPersistentState = true
            publishPortalMenu()
            displayObserver.start()
            applyDisplayTopology(displaySnapshotProvider())
        }
    }

    func createPortal(
        for folderURL: URL?,
        frame: NSRect? = nil,
        gridCapacity: GridCapacity = .minimum,
        iconLayout: PortalIconLayout = .fixed(.medium)
    ) async throws {
        let validatedFolderURL: URL?
        if let folderURL {
            validatedFolderURL = try await locationValidator.validate(folderURL)
        } else {
            validatedFolderURL = nil
        }
        try Task.checkCancellation()
        try await performMutation { [weak self] in
            guard let self else { return }
            guard hasLoadedPersistentState else {
                throw PortalCoordinatorError.persistentStateNotLoaded
            }
            let snapshot = try currentDisplaySnapshot()
            let requestedFrame = frame ?? Self.defaultFrame(on: snapshot.primaryDescriptor)
            let display = try LegacyFrameDisplayResolver.resolve(
                frame: requestedFrame,
                in: snapshot
            )
            let initialFrame = Self.frameFittingCapacity(
                requestedFrame,
                iconLayout: iconLayout,
                visibleFrame: display.visibleFrame,
                gridCapacity: gridCapacity
            )
            let portal: Portal
            if let validatedFolderURL {
                portal = try Portal(
                    folderURL: validatedFolderURL,
                    frame: initialFrame,
                    display: display,
                    iconLayout: iconLayout,
                    gridCapacity: gridCapacity
                )
            } else {
                portal = try Portal(
                    frame: initialFrame,
                    display: display,
                    iconLayout: iconLayout,
                    gridCapacity: gridCapacity
                )
            }
            let updatedPortals = portalStates + [portal]
            try await store.save(updatedPortals)
            portalStates = updatedPortals
            publishPortalMenu()
            applyDisplayTopology(displaySnapshotProvider())
        }
    }

    func waitForPersistenceForTesting() async {
        await waitForMutationQuiescence()
    }

    func waitForTabMutationForTesting() async {
        await waitForTabTasks()
    }

    func stop() {
        displayObserver.stop()
    }

    func prepareForTermination() async {
        displayObserver.stop()
        tabFolderPicker.cancel()
        folderSelectionTask?.cancel()
        for task in tabMutationTasks.values {
            task.cancel()
        }
        await waitForTabTasks()
        await waitForMutationQuiescence()
        if !pendingUserPlacements.isEmpty {
            applyDisplayTopology(displaySnapshotProvider())
            await waitForMutationQuiescence()
        }
    }

    func showPortal(_ portalID: PortalID) {
        windows[portalID]?.present()
    }

    func hidePortal(_ portalID: PortalID) {
        windows[portalID]?.hide()
    }

    func removePortal(_ portalID: PortalID) async {
        do {
            try await performMutation { [weak self] in
                guard let self,
                      let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                    return
                }
                var updatedPortals = portalStates
                updatedPortals.remove(at: index)
                try await store.save(updatedPortals)
                portalStates = updatedPortals
                windows.removeValue(forKey: portalID)?.close()
                removeRuntimeState(for: portalID)
                publishPortalMenu()
            }
            persistenceError = nil
        } catch {
            presentPersistenceError(error)
        }
    }

    func setIconSize(_ iconSize: IconSize, for portalID: PortalID) async {
        do {
            try await performMutation { [weak self] in
                guard let self,
                      let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                    return
                }
                let previousFrame = portalStates[index].frame
                var portal = portalStates[index]
                portal.updateIconSize(iconSize)
                portal = try portalSnappingFrame(portal)
                try await commit(portal, at: index)
                if portal.frame != previousFrame {
                    placementSessions[portalID] = try placementSession(for: portal)
                    applyDisplayTopology(displaySnapshotProvider())
                }
            }
            persistenceError = nil
        } catch {
            presentPersistenceError(error)
        }
    }

    private func portalSnappingFrame(_ portal: Portal) throws -> Portal {
        var portal = portal
        let homeEntry = portal.placement.homeEntry
        let homeDisplay = DisplayDescriptor(
            identity: portal.placement.homeDisplay,
            visibleFrame: homeEntry.referenceVisibleFrame
        )
        let adjustedFrame = Self.frameFittingCapacity(
            portal.frame,
            iconLayout: portal.iconLayout,
            visibleFrame: homeDisplay.visibleFrame,
            gridCapacity: portal.gridCapacity
        )
        guard adjustedFrame != portal.frame else { return portal }
        try portal.recordUserPlacement(frame: adjustedFrame, display: homeDisplay)
        return portal
    }

    func setBackgroundStyle(
        _ backgroundStyle: PortalBackgroundStyle,
        for portalID: PortalID
    ) async {
        do {
            try await performMutation { [weak self] in
                guard let self,
                      let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                    return
                }
                var portal = portalStates[index]
                portal.updateBackgroundStyle(backgroundStyle)
                try await commit(portal, at: index)
            }
            persistenceError = nil
        } catch {
            presentPersistenceError(error)
        }
    }

    func setPinned(_ isPinned: Bool, for portalID: PortalID) async {
        do {
            try await performMutation { [weak self] in
                guard let self,
                      let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                    return
                }
                var portal = portalStates[index]
                portal.updatePinned(isPinned)
                try await commit(portal, at: index)
            }
            persistenceError = nil
        } catch {
            presentPersistenceError(error)
        }
    }

    private func present(_ portal: Portal, transition: PlacementTransition) {
        placementSessions[portal.id] = transition.session
        let window = windowFactory.makeWindow(for: portal)
        window.onUserPlacementCommit = { [weak self] frame in
            self?.recordUserPlacement(frame, portalID: portal.id)
        }
        window.onUserResizeCommit = { [weak self] frame, gridCapacity in
            self?.recordUserPlacement(
                frame,
                gridCapacity: gridCapacity,
                portalID: portal.id
            )
        }
        window.onUserPlacementInteractionCancelled = { [weak self] in
            self?.retryDeferredTopology(for: portal.id)
        }
        window.onSelectTab = { [weak self] tabID in
            self?.startTabMutationTask {
                try await self?.selectTab(tabID, in: portal.id)
            }
        }
        window.onAddTab = { [weak self] in
            self?.startFolderSelectionTask {
                await self?.addTab(to: portal.id)
            }
        }
        window.onCloseTab = { [weak self] tabID in
            self?.startTabMutationTask {
                await self?.closeTab(tabID, in: portal.id)
            }
        }
        window.onMoveTab = { [weak self] tabID, targetIndex in
            self?.startTabMutationTask {
                try await self?.moveTab(tabID, to: targetIndex, in: portal.id)
            }
        }
        window.onLocateFolder = { [weak self] tabID in
            self?.startFolderSelectionTask {
                await self?.relocateTab(tabID, in: portal.id)
            }
        }
        window.onSetBackgroundStyle = { [weak self] backgroundStyle in
            self?.startTabMutationTask {
                await self?.setBackgroundStyle(backgroundStyle, for: portal.id)
            }
        }
        window.onSetIconSize = { [weak self] iconSize in
            self?.startTabMutationTask {
                await self?.setIconSize(iconSize, for: portal.id)
            }
        }
        window.onRemovePortal = { [weak self] in
            self?.startTabMutationTask {
                await self?.removePortal(portal.id)
            }
        }
        window.onSetPinned = { [weak self] isPinned in
            self?.startTabMutationTask {
                await self?.setPinned(isPinned, for: portal.id)
            }
        }
        windows[portal.id] = window
        if let directive = transition.directive,
           !window.applySystemPlacement(frame: directive.frame) {
            deferredTopologyPortals.insert(portal.id)
        }
        window.present()
    }

    private func recordUserPlacement(
        _ frame: NSRect,
        gridCapacity: GridCapacity? = nil,
        portalID: PortalID
    ) {
        let snapshotResult = displaySnapshotProvider()
        nextUserPlacementGeneration += 1
        let pending = PendingUserPlacement(
            generation: nextUserPlacementGeneration,
            frame: frame,
            gridCapacity: gridCapacity
        )
        pendingUserPlacements[portalID] = pending
        pendingPlacementAttempts[portalID] = pending.generation
        enqueueUserPlacement(
            pending,
            portalID: portalID,
            snapshotResult: snapshotResult
        )
    }

    private func enqueueUserPlacement(
        _ pending: PendingUserPlacement,
        portalID: PortalID,
        snapshotResult: Result<DisplaySnapshot, DisplaySnapshotError>
    ) {
        enqueueMutation { [weak self] in
            guard let self else { return }
            guard let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                clearPendingUserPlacement(portalID: portalID, generation: pending.generation)
                return
            }
            var resolvedSnapshot: DisplaySnapshot?
            do {
                let displaySnapshot = try snapshotResult.get()
                resolvedSnapshot = displaySnapshot
                let display = try LegacyFrameDisplayResolver.resolve(
                    frame: pending.frame,
                    in: displaySnapshot
                )
                var portal = portalStates[index]
                if let gridCapacity = pending.gridCapacity {
                    portal.updateGridCapacity(gridCapacity)
                }
                let captured = try PlacementGeometry.capture(
                    windowFrame: pending.frame,
                    visibleFrame: display.visibleFrame
                )
                let committedFrame = try PlacementGeometry.restore(
                    record: captured,
                    currentVisibleFrame: display.visibleFrame,
                    gridSpacing: placementGridSpacing(for: portal)
                )
                try portal.recordUserPlacement(frame: committedFrame, display: display)
                var updatedPortals = portalStates
                updatedPortals[index] = portal
                try await store.save(updatedPortals)
                portalStates = updatedPortals
                placementSessions[portalID] = try placementSession(for: portal)
                clearPendingUserPlacement(portalID: portalID, generation: pending.generation)
                displayError = nil
            } catch {
                clearPendingPlacementAttempt(portalID: portalID, generation: pending.generation)
                if error is DisplaySnapshotError
                    || error is PlacementError
                    || error is PortalError {
                    displayError = error
                    return
                }
                if let resolvedSnapshot {
                    reconcile(portalID: portalID, with: resolvedSnapshot)
                }
                throw error
            }
            applyDisplayTopology(displaySnapshotProvider())
        }
    }

    private func performMutation(
        _ operation: @escaping @MainActor () async throws -> Void
    ) async throws {
        let mutation = scheduleMutation(operation)
        try await withTaskCancellationHandler {
            try await mutation.value
        } onCancel: {
            mutation.cancel()
        }
    }

    private func enqueueMutation(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        _ = scheduleMutation { [weak self] in
            guard let self else { return }
            do {
                try await operation()
                persistenceError = nil
            } catch {
                presentPersistenceError(error)
            }
        }
    }

    private func scheduleMutation(
        _ operation: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Error> {
        let previous = mutationTail
        mutationGeneration += 1
        let mutation = Task { @MainActor in
            await previous?.value
            try Task.checkCancellation()
            try await operation()
        }
        mutationTail = Task { @MainActor in
            _ = try? await mutation.value
        }
        return mutation
    }

    private func waitForMutationQuiescence() async {
        while true {
            let generation = mutationGeneration
            await mutationTail?.value
            guard generation != mutationGeneration else { return }
        }
    }

    private func startFolderSelectionTask(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        guard folderSelectionTask == nil else { return }
        folderSelectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
            } catch is CancellationError {
                // The owning workflow is terminating.
            } catch {
                presentPersistenceError(error)
            }
            folderSelectionTask = nil
        }
    }

    private func startTabMutationTask(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        let taskID = UUID()
        tabMutationTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
            } catch is CancellationError {
                // The owning workflow is terminating.
            } catch {
                presentPersistenceError(error)
            }
            tabMutationTasks.removeValue(forKey: taskID)
        }
    }

    private func waitForTabTasks() async {
        while true {
            let tasks = Array(tabMutationTasks.values)
            let folderTask = folderSelectionTask
            for task in tasks {
                await task.value
            }
            await folderTask?.value
            guard tabMutationTasks.isEmpty, folderSelectionTask == nil else { continue }
            return
        }
    }

    func selectTab(_ tabID: FolderTabID, in portalID: PortalID) async throws {
        try await performMutation { [weak self] in
            guard let self,
                  let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                return
            }
            var portal = portalStates[index]
            try portal.selectTab(tabID)
            try await commit(portal, at: index)
        }
    }

    func moveTab(_ tabID: FolderTabID, to targetIndex: Int, in portalID: PortalID) async throws {
        try await performMutation { [weak self] in
            guard let self,
                  let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                return
            }
            var portal = portalStates[index]
            guard var currentIndex = portal.tabs.firstIndex(where: { $0.id == tabID }),
                  portal.tabs.indices.contains(targetIndex),
                  currentIndex != targetIndex else {
                return
            }
            while currentIndex > targetIndex {
                try portal.moveTab(tabID, toward: .up)
                currentIndex -= 1
            }
            while currentIndex < targetIndex {
                try portal.moveTab(tabID, toward: .down)
                currentIndex += 1
            }
            try await commit(portal, at: index)
        }
    }

    func addTab(to portalID: PortalID) async {
        while !Task.isCancelled {
            guard let folderURL = await tabFolderPicker.chooseFolder() else { return }
            do {
                let folderURL = try await locationValidator.validate(folderURL)
                try await performMutation { [weak self] in
                    guard let self,
                          let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                        return
                    }
                    var portal = portalStates[index]
                    let tabID = try portal.appendTab(folderURL: folderURL)
                    try portal.selectTab(tabID)
                    try await commit(portal, at: index)
                }
                return
            } catch is CancellationError {
                return
            } catch let error as FolderAccessError {
                errorPresenter.present(error)
            } catch {
                presentPersistenceError(error)
                return
            }
        }
    }

    func relocateTab(_ tabID: FolderTabID, in portalID: PortalID) async {
        while !Task.isCancelled {
            guard let folderURL = await tabFolderPicker.chooseFolder() else { return }
            do {
                let folderURL = try await locationValidator.validate(folderURL)
                try await performMutation { [weak self] in
                    guard let self,
                          let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                        return
                    }
                    let currentPortal = portalStates[index]
                    let selectedFolderURL = currentPortal.tabs.first {
                        $0.id == currentPortal.selectedTabID
                    }?.folderURL
                    let portal = try replacingFolder(
                        for: tabID,
                        with: folderURL,
                        in: currentPortal
                    )
                    try await commit(portal, at: index)
                    if tabID == portal.selectedTabID,
                       selectedFolderURL == folderURL.standardizedFileURL {
                        windows[portalID]?.reloadSelectedFolder()
                    }
                }
                return
            } catch is CancellationError {
                return
            } catch let error as FolderAccessError {
                errorPresenter.present(error)
            } catch {
                presentPersistenceError(error)
                return
            }
        }
    }

    func closeTab(_ tabID: FolderTabID, in portalID: PortalID) async {
        guard let currentPortal = portalStates.first(where: { $0.id == portalID }) else { return }
        let confirmedLastTabRemoval: Bool
        if currentPortal.tabs.count == 1 {
            guard let tab = currentPortal.tabs.first else { return }
            confirmedLastTabRemoval = await lastTabRemovalConfirmer.confirmRemoval(
                folderName: tab.folderURL.lastPathComponent
            )
            guard confirmedLastTabRemoval else { return }
        } else {
            confirmedLastTabRemoval = false
        }
        do {
            try await performMutation { [weak self] in
                guard let self,
                      let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                    return
                }
                let current = portalStates[index]
                if current.tabs.count == 1 {
                    guard confirmedLastTabRemoval,
                          current.tabs[0].id == tabID else {
                        return
                    }
                    var updatedPortals = portalStates
                    updatedPortals.remove(at: index)
                    try await store.save(updatedPortals)
                    portalStates = updatedPortals
                    windows.removeValue(forKey: portalID)?.close()
                    removeRuntimeState(for: portalID)
                    publishPortalMenu()
                    return
                }

                var portal = current
                try portal.removeTab(tabID)
                try await commit(portal, at: index)
            }
            persistenceError = nil
        } catch {
            presentPersistenceError(error)
        }
    }

    private func commit(_ portal: Portal, at index: Int) async throws {
        var updatedPortals = portalStates
        updatedPortals[index] = portal
        try await store.save(updatedPortals)
        portalStates = updatedPortals
        windows[portal.id]?.updatePortal(portal)
        publishPortalMenu()
        persistenceError = nil
    }

    func reconcileDisplayTopology(
        _ result: Result<DisplaySnapshot, DisplaySnapshotError>
    ) {
        enqueueTopologyMutation { [weak self] in
            self?.applyDisplayTopology(result)
        }
    }

    private func enqueueTopologyMutation(_ operation: @escaping @MainActor () -> Void) {
        _ = scheduleMutation {
            operation()
        }
    }

    private func applyDisplayTopology(
        _ result: Result<DisplaySnapshot, DisplaySnapshotError>
    ) {
        switch result {
        case .success(let snapshot):
            displayError = nil
            for portal in portalStates {
                if let pending = pendingUserPlacements[portal.id] {
                    if pendingPlacementAttempts[portal.id] != pending.generation {
                        pendingPlacementAttempts[portal.id] = pending.generation
                        enqueueUserPlacement(
                            pending,
                            portalID: portal.id,
                            snapshotResult: .success(snapshot)
                        )
                    }
                    continue
                }
                if windows[portal.id] == nil {
                    do {
                        let transition = try placementTransition(
                            for: portal,
                            topology: snapshot
                        )
                        present(portal, transition: transition)
                    } catch {
                        displayError = error
                    }
                } else {
                    reconcile(portalID: portal.id, with: snapshot)
                }
            }
        case .failure(let error) where error == .noScreensAvailable
            || error == .missingPrimaryScreen:
            displayError = error
            for portal in portalStates {
                guard let session = placementSessions[portal.id] else { continue }
                do {
                    let transition = try PlacementStateMachine.reconcileTopology(
                        session: session,
                        displays: [],
                        primaryDisplay: session.homeDisplay
                    )
                    placementSessions[portal.id] = transition.session
                } catch {
                    displayError = error
                }
            }
        case .failure(let error):
            displayError = error
        }
    }

    private func reconcile(portalID: PortalID, with snapshot: DisplaySnapshot) {
        guard let session = placementSessions[portalID],
              let window = windows[portalID],
              let portal = portalStates.first(where: { $0.id == portalID }) else {
            return
        }
        do {
            let transition = try PlacementStateMachine.reconcileTopology(
                session: session,
                displays: snapshot.displays,
                primaryDisplay: snapshot.primaryDisplay,
                gridSpacing: placementGridSpacing(for: portal)
            )
            placementSessions[portalID] = transition.session
            guard let directive = transition.directive else { return }
            if window.applySystemPlacement(frame: directive.frame) {
                deferredTopologyPortals.remove(portalID)
            } else {
                deferredTopologyPortals.insert(portalID)
            }
        } catch {
            displayError = error
        }
    }

    private func placementSession(for portal: Portal) throws -> PlacementSession {
        try PlacementSession(
            placements: portal.placement.framesByDisplay,
            homeDisplay: portal.placement.homeDisplay,
            presentation: .active(on: portal.placement.homeDisplay)
        )
    }

    private func placementTransition(
        for portal: Portal,
        topology: DisplaySnapshot
    ) throws -> PlacementTransition {
        try PlacementStateMachine.reconcileTopology(
            session: placementSession(for: portal),
            displays: topology.displays,
            primaryDisplay: topology.primaryDisplay,
            gridSpacing: placementGridSpacing(for: portal)
        )
    }

    private func placementGridSpacing(for portal: Portal) -> GridSpacing {
        .snap(GridMetrics(iconSize: portal.iconSize).horizontalSpacing)
    }

    private func retryDeferredTopology(for portalID: PortalID) {
        guard deferredTopologyPortals.contains(portalID) else { return }
        reconcileDisplayTopology(displaySnapshotProvider())
    }

    private func clearPendingUserPlacement(portalID: PortalID, generation: UInt64) {
        if pendingUserPlacements[portalID]?.generation == generation {
            pendingUserPlacements.removeValue(forKey: portalID)
        }
        clearPendingPlacementAttempt(portalID: portalID, generation: generation)
    }

    private func clearPendingPlacementAttempt(portalID: PortalID, generation: UInt64) {
        if pendingPlacementAttempts[portalID] == generation {
            pendingPlacementAttempts.removeValue(forKey: portalID)
        }
    }

    private func currentDisplaySnapshot() throws -> DisplaySnapshot {
        try displaySnapshotProvider().get()
    }

    private func presentPersistenceError(_ error: Error) {
        guard !(error is CancellationError) else { return }
        persistenceError = error
        persistenceErrorPresenter.present(error)
    }

    private func replacingFolder(
        for tabID: FolderTabID,
        with folderURL: URL,
        in portal: Portal
    ) throws -> Portal {
        guard let index = portal.tabs.firstIndex(where: { $0.id == tabID }) else {
            throw PortalError.tabNotFound(tabID)
        }
        var tabs = portal.tabs
        tabs[index] = FolderTab(id: tabID, folderURL: folderURL)
        return try Portal(
            id: portal.id,
            tabs: tabs,
            selectedTabID: portal.selectedTabID,
            placement: portal.placement,
            iconLayout: portal.iconLayout,
            backgroundStyle: portal.backgroundStyle,
            gridCapacity: portal.gridCapacity,
            isPinned: portal.isPinned
        )
    }

    private func removeRuntimeState(for portalID: PortalID) {
        placementSessions.removeValue(forKey: portalID)
        deferredTopologyPortals.remove(portalID)
        pendingUserPlacements.removeValue(forKey: portalID)
        pendingPlacementAttempts.removeValue(forKey: portalID)
    }

    private func publishPortalMenu() {
        let entries = portalStates.map { portal in
            let title = portal.selectedTab?.folderURL.lastPathComponent
                ?? NSLocalizedString("portal.empty.title", comment: "Empty portal title")
            return PortalMenuEntry(id: portal.id, title: title)
        }
        onPortalsChanged?(entries)
    }

    private static func defaultFrame(on display: DisplayDescriptor) -> NSRect {
        let size = NSSize(width: 560, height: 480)
        let visibleFrame = display.visibleFrame
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func frameFittingCapacity(
        _ frame: NSRect,
        iconLayout: PortalIconLayout,
        visibleFrame: NSRect,
        gridCapacity: GridCapacity
    ) -> NSRect {
        let styleMask: NSWindow.StyleMask = [.resizable]
        let snappedContentSize = PortalViewController.contentSize(
            for: gridCapacity,
            iconLayout: iconLayout
        )
        let snappedFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: snappedContentSize),
            styleMask: styleMask
        ).size
        let size = NSSize(
            width: min(snappedFrameSize.width, visibleFrame.width),
            height: min(snappedFrameSize.height, visibleFrame.height)
        )
        let origin = NSPoint(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
        return NSRect(origin: origin, size: size)
    }
}

private struct PendingUserPlacement {
    let generation: UInt64
    let frame: NSRect
    let gridCapacity: GridCapacity?
}

enum PortalCoordinatorError: Error, Equatable {
    case persistentStateNotLoaded
}

enum StartupFolderResolver {
    static func resolve(arguments: [String]) -> URL? {
        guard arguments.count == 3, arguments[1] == "--folder" else { return nil }
        return URL(fileURLWithPath: arguments[2]).standardizedFileURL
    }
}
