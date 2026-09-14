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
    private var portalAppearance: PortalAppearancePreferences
    private var windows: [PortalID: any PortalWindowPresenting] = [:]
    private var spacingLayoutBaseFrames: [PortalID: NSRect] = [:]
    private var placementSessions: [PortalID: PlacementSession] = [:]
    private var deferredTopologyPortals = Set<PortalID>()
    private var spacingLayoutNeedsRetry = false
    private var pendingUserPlacements: [PortalID: PendingUserPlacement] = [:]
    private var pendingPlacementAttempts: [PortalID: UInt64] = [:]
    private var nextUserPlacementGeneration: UInt64 = 0
    private var mutationTail: Task<Void, Never>?
    private var mutationGeneration: UInt64 = 0
    private var pendingMutationCount = 0
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
        portalAppearance: PortalAppearancePreferences = .defaults,
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
        self.portalAppearance = portalAppearance
        self.displayNotificationCenter = displayNotificationCenter
        self.displaySnapshotProvider = displaySnapshotProvider
    }

    func restorePortals() async throws {
        try await performMutation { [weak self] in
            guard let self else { return }
            let storedPortals = try await store.load()
            let currentSnapshot = try? displaySnapshotProvider().get()
            var portals = storedPortals
            for index in portals.indices {
                let iconSizeChanged = portals[index].iconSize != portalAppearance.iconSize
                if iconSizeChanged {
                    portals[index].updateIconSize(portalAppearance.iconSize)
                }
                portals[index].updateBackgroundStyle(portalAppearance.backgroundStyle)
                if iconSizeChanged {
                    portals[index] = try portalSnappingFrame(
                        portals[index],
                        currentSnapshot: currentSnapshot
                    )
                }
            }
            if portals != storedPortals {
                try await store.save(portals)
            }
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
        let iconLayout = PortalIconLayout.fixed(portalAppearance.iconSize)
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
                gridCapacity: gridCapacity,
                spacing: portalAppearance.spacing.points
            )
            guard try isValidPortalFrame(
                initialFrame,
                in: snapshot,
                excluding: nil
            ) else {
                throw PortalCoordinatorError.placementUnavailable
            }
            let portal: Portal
            if let validatedFolderURL {
                portal = try Portal(
                    folderURL: validatedFolderURL,
                    frame: initialFrame,
                    display: display,
                    iconLayout: iconLayout,
                    backgroundStyle: portalAppearance.backgroundStyle,
                    gridCapacity: gridCapacity
                )
            } else {
                portal = try Portal(
                    frame: initialFrame,
                    display: display,
                    iconLayout: iconLayout,
                    backgroundStyle: portalAppearance.backgroundStyle,
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

    @discardableResult
    func updatePortalAppearance(_ appearance: PortalAppearancePreferences) -> Bool {
        guard pendingMutationCount == 0,
              pendingUserPlacements.isEmpty,
              !windows.values.contains(where: \.isUserPlacementInteractionActive),
              case .success(let snapshot) = displaySnapshotProvider() else {
            return false
        }
        let spacingChanged = portalAppearance.spacing != appearance.spacing
        let spacingPlan: [PortalID: NSRect]?
        if spacingChanged {
            guard let plan = portalSpacingLayoutPlan(
                      snapshot: snapshot,
                      spacing: appearance.spacing.points
                  ) else {
                return false
            }
            spacingPlan = plan
        } else {
            spacingPlan = nil
        }

        let iconSizeChanged = portalAppearance.iconSize != appearance.iconSize
        let sizePlan: [PortalID: NSRect]?
        if iconSizeChanged {
            guard let plan = portalIconSizeLayoutPlan(
                snapshot: snapshot,
                iconSize: appearance.iconSize,
                spacing: appearance.spacing.points,
                baseFrames: spacingPlan
            ) else {
                return false
            }
            sizePlan = plan
        } else {
            sizePlan = nil
        }

        var updatedPortals = portalStates
        do {
            for index in updatedPortals.indices {
                updatedPortals[index].updateBackgroundStyle(appearance.backgroundStyle)
                guard iconSizeChanged else { continue }
                updatedPortals[index].updateIconSize(appearance.iconSize)
                updatedPortals[index] = try portalSnappingFrame(
                    updatedPortals[index],
                    currentSnapshot: snapshot
                )
            }
        } catch {
            return false
        }

        portalAppearance = appearance
        portalStates = updatedPortals
        for portal in portalStates {
            windows[portal.id]?.updatePortal(portal)
            if iconSizeChanged {
                placementSessions[portal.id] = try? placementSession(for: portal)
            }
        }
        for window in windows.values {
            window.updateAppearance(appearance)
        }
        if let framePlan = sizePlan ?? spacingPlan {
            applyPortalSpacingLayout(framePlan, animated: true)
            for (portalID, frame) in framePlan {
                spacingLayoutBaseFrames[portalID] = frame
            }
        }
        return true
    }

    func occupiedPortalFrames() -> [NSRect] {
        runtimePortalFrames(excluding: nil)
    }

    func replaceLayout(with backup: AlcoveLayoutBackup) async throws {
        try await performMutation { [weak self] in
            guard let self else { return }
            guard hasLoadedPersistentState else {
                throw PortalCoordinatorError.persistentStateNotLoaded
            }
            guard pendingUserPlacements.isEmpty,
                  folderSelectionTask == nil,
                  !windows.values.contains(where: \.isUserPlacementInteractionActive) else {
                throw PortalCoordinatorError.layoutImportBusy
            }

            let snapshot = try currentDisplaySnapshot()
            let appearance = PortalAppearancePreferences(
                iconSize: backup.global.iconSize,
                backgroundStyle: backup.global.backgroundStyle,
                cornerRadius: backup.global.cornerRadius,
                spacing: backup.global.spacing,
                shadowEnabled: backup.global.shadowEnabled
            )
            let importedPortals = try portals(
                from: backup,
                appearance: appearance,
                display: snapshot.primaryDescriptor
            )

            // Persistence is the transaction boundary. Runtime state remains untouched
            // unless the complete imported layout has validated and saved successfully.
            try await store.save(importedPortals)

            for window in windows.values {
                window.close()
            }
            windows.removeAll()
            placementSessions.removeAll()
            deferredTopologyPortals.removeAll()
            pendingUserPlacements.removeAll()
            pendingPlacementAttempts.removeAll()
            spacingLayoutBaseFrames.removeAll()
            spacingLayoutNeedsRetry = false
            portalAppearance = appearance
            portalStates = importedPortals
            publishPortalMenu()
            applyDisplayTopology(.success(snapshot))
        }
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

    func showPortalSettings(_ portalID: PortalID) {
        windows[portalID]?.showPortalSettings()
    }

    func confirmPortalRemoval(_ portalID: PortalID) {
        windows[portalID]?.confirmPortalRemoval()
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
                let currentSnapshot: DisplaySnapshot? = switch displaySnapshotProvider() {
                case .success(let snapshot): snapshot
                case .failure: nil
                }
                let previousFrame = portalStates[index].frame
                var portal = portalStates[index]
                portal.updateIconSize(iconSize)
                portal = try portalSnappingFrame(portal, currentSnapshot: currentSnapshot)
                if let currentSnapshot,
                   currentSnapshot.display(with: portal.placement.homeDisplay) != nil,
                   try !isValidIconResizeFrame(
                       portal.frame,
                       snapshot: currentSnapshot,
                       portalID: portalID
                   ) {
                    throw PortalCoordinatorError.placementUnavailable
                }
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

    private func portalSnappingFrame(
        _ portal: Portal,
        currentSnapshot: DisplaySnapshot?
    ) throws -> Portal {
        var portal = portal
        let homeEntry = portal.placement.homeEntry
        let rememberedHomeDisplay = DisplayDescriptor(
            identity: portal.placement.homeDisplay,
            visibleFrame: homeEntry.referenceVisibleFrame
        )
        // A current home descriptor can be unavailable during snapshot capture or
        // while disconnected; its durable placement must still accept the preference.
        let homeDisplay = currentSnapshot?.display(with: portal.placement.homeDisplay)
            ?? rememberedHomeDisplay
        let adjustedFrame = Self.frameFittingCapacity(
            portal.frame,
            iconLayout: portal.iconLayout,
            visibleFrame: homeDisplay.visibleFrame,
            gridCapacity: portal.gridCapacity,
            anchor: .topLeft
        )
        guard adjustedFrame != portal.frame else { return portal }
        try portal.recordUserPlacement(frame: adjustedFrame, display: homeDisplay)
        return portal
    }

    private func portals(
        from backup: AlcoveLayoutBackup,
        appearance: PortalAppearancePreferences,
        display: DisplayDescriptor
    ) throws -> [Portal] {
        let spacing = appearance.spacing.points
        let usableFrame = display.visibleFrame.insetBy(dx: spacing, dy: spacing)
        let iconLayout = PortalIconLayout.fixed(appearance.iconSize)
        var portals: [Portal] = []
        var desiredFrames: [NSRect] = []
        portals.reserveCapacity(backup.portals.count)
        desiredFrames.reserveCapacity(backup.portals.count)

        for importedPortal in backup.portals {
            let contentSize = PortalViewController.contentSize(
                for: importedPortal.gridCapacity,
                iconLayout: iconLayout
            )
            let frameSize = NSWindow.frameRect(
                forContentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.resizable]
            ).size
            guard frameSize.width <= usableFrame.width,
                  frameSize.height <= usableFrame.height else {
                throw PortalCoordinatorError.placementUnavailable
            }
            let frame = NSRect(
                x: usableFrame.minX
                    + CGFloat(importedPortal.normalizedAnchor.x)
                    * (usableFrame.width - frameSize.width),
                y: usableFrame.minY
                    + CGFloat(importedPortal.normalizedAnchor.y)
                    * (usableFrame.height - frameSize.height),
                width: frameSize.width,
                height: frameSize.height
            )
            let tabs = importedPortal.folderURLs.map { FolderTab(folderURL: $0) }
            let selectedTabID = importedPortal.selectedFolderIndex.map { tabs[$0].id }
            let placement = try PlacementRecord(frame: frame, display: display)
            let portal = try Portal(
                id: importedPortal.id,
                tabs: tabs,
                selectedTabID: selectedTabID,
                placement: placement,
                iconLayout: iconLayout,
                backgroundStyle: appearance.backgroundStyle,
                gridCapacity: importedPortal.gridCapacity,
                isPinned: importedPortal.isPinned,
                sortOrder: importedPortal.sortOrder,
                tint: importedPortal.tint
            )
            portals.append(portal)
            desiredFrames.append(frame)
        }

        guard let reflowedFrames = try PortalFrameReflow.reflowedFrames(
            desiredFrames,
            visibleFrame: display.visibleFrame,
            minimumGap: spacing
        ) else {
            throw PortalCoordinatorError.placementUnavailable
        }
        for index in portals.indices {
            try portals[index].recordUserPlacement(
                frame: reflowedFrames[index],
                display: display
            )
        }
        return portals
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

    func setSortOrder(_ sortOrder: PortalSortOrder, for portalID: PortalID) async {
        do {
            try await performMutation { [weak self] in
                guard let self,
                      let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                    return
                }
                var portal = portalStates[index]
                portal.updateSortOrder(sortOrder)
                try await commit(portal, at: index)
            }
            persistenceError = nil
        } catch {
            restorePortalPresentation(portalID)
            presentPersistenceError(error)
        }
    }

    func setTint(_ tint: PortalTint, for portalID: PortalID) async {
        do {
            try await performMutation { [weak self] in
                guard let self,
                      let index = portalStates.firstIndex(where: { $0.id == portalID }) else {
                    return
                }
                var portal = portalStates[index]
                portal.updateTint(tint)
                try await commit(portal, at: index)
            }
            persistenceError = nil
        } catch {
            restorePortalPresentation(portalID)
            presentPersistenceError(error)
        }
    }

    private func restorePortalPresentation(_ portalID: PortalID) {
        guard let portal = portalStates.first(where: { $0.id == portalID }) else { return }
        windows[portalID]?.updatePortal(portal)
    }

    private func present(_ portal: Portal, transition: PlacementTransition) {
        placementSessions[portal.id] = transition.session
        let window = windowFactory.makeWindow(for: portal)
        window.updateAppearance(portalAppearance)
        window.configureUserPlacementConstraints(
            constrainDrag: { [weak self] currentFrame, proposedFrame, pointer in
                self?.constrainedUserDragFrame(
                    currentFrame: currentFrame,
                    proposedFrame: proposedFrame,
                    pointer: pointer,
                    portalID: portal.id
                ) ?? currentFrame
            },
            isValidFrame: { [weak self] frame in
                self?.isValidUserFrame(frame, portalID: portal.id) ?? false
            }
        )
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
        window.onSetSortOrder = { [weak self] sortOrder in
            self?.startTabMutationTask {
                await self?.setSortOrder(sortOrder, for: portal.id)
            }
        }
        window.onSetTint = { [weak self] tint in
            self?.startTabMutationTask {
                await self?.setTint(tint, for: portal.id)
            }
        }
        windows[portal.id] = window
        if let directive = transition.directive {
            if window.applySystemPlacement(frame: directive.frame) {
                spacingLayoutBaseFrames[portal.id] = directive.frame
            } else {
                deferredTopologyPortals.insert(portal.id)
            }
        } else if let presentedFrame = window.presentedFrame {
            spacingLayoutBaseFrames[portal.id] = presentedFrame
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
                guard try isValidPortalFrame(
                    committedFrame,
                    in: displaySnapshot,
                    excluding: portalID
                ) else {
                    clearPendingUserPlacement(
                        portalID: portalID,
                        generation: pending.generation
                    )
                    reconcile(portalID: portalID, with: displaySnapshot)
                    throw PortalCoordinatorError.placementUnavailable
                }
                try portal.recordUserPlacement(frame: committedFrame, display: display)
                var updatedPortals = portalStates
                updatedPortals[index] = portal
                try await store.save(updatedPortals)
                portalStates = updatedPortals
                placementSessions[portalID] = try placementSession(for: portal)
                spacingLayoutBaseFrames[portalID] = committedFrame
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
        pendingMutationCount += 1
        let mutation = Task { @MainActor in
            defer { pendingMutationCount -= 1 }
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
            if pendingUserPlacements.isEmpty {
                applyCurrentPortalSpacingLayout(snapshot: snapshot, animated: false)
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
                spacingLayoutBaseFrames[portalID] = directive.frame
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
        guard deferredTopologyPortals.contains(portalID)
                || spacingLayoutNeedsRetry else {
            return
        }
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

    private func constrainedUserDragFrame(
        currentFrame: NSRect,
        proposedFrame: NSRect,
        pointer: NSPoint,
        portalID: PortalID
    ) -> NSRect {
        guard case .success(let snapshot) = displaySnapshotProvider() else {
            return currentFrame
        }
        let destination = Self.display(containingOrNearestTo: pointer, in: snapshot)
        let otherFrames = runtimePortalFrames(excluding: portalID)
        let spacing = portalAppearance.spacing.points

        if destination.visibleFrame.contains(currentFrame) {
            do {
                return try PortalFrameConstraints.constrainedDragFrame(
                    initialFrame: currentFrame,
                    proposedFrame: proposedFrame,
                    visibleFrame: destination.visibleFrame,
                    otherPortalFrames: otherFrames,
                    minimumGap: spacing
                )
            } catch {
                // A layout created before spacing constraints may start invalid.
                // It may leave that state, but no new invalid frame is committed.
            }
        }

        let candidate = Self.frameClampedToVisibleBounds(
            proposedFrame,
            visibleFrame: destination.visibleFrame,
            spacing: spacing
        )
        return (try? PortalFrameConstraints.isValidPlacement(
            frame: candidate,
            visibleFrame: destination.visibleFrame,
            otherPortalFrames: otherFrames,
            minimumGap: spacing
        )) == true ? candidate : currentFrame
    }

    private func isValidUserFrame(_ frame: NSRect, portalID: PortalID) -> Bool {
        guard case .success(let snapshot) = displaySnapshotProvider() else { return false }
        return (try? isValidPortalFrame(frame, in: snapshot, excluding: portalID)) == true
    }

    private func isValidPortalFrame(
        _ frame: NSRect,
        in snapshot: DisplaySnapshot,
        excluding portalID: PortalID?
    ) throws -> Bool {
        let display = try LegacyFrameDisplayResolver.resolve(frame: frame, in: snapshot)
        return try PortalFrameConstraints.isValidPlacement(
            frame: frame,
            visibleFrame: display.visibleFrame,
            otherPortalFrames: runtimePortalFrames(excluding: portalID),
            minimumGap: portalAppearance.spacing.points
        )
    }

    private func isValidIconResizeFrame(
        _ frame: NSRect,
        snapshot: DisplaySnapshot,
        portalID: PortalID
    ) throws -> Bool {
        let display = try LegacyFrameDisplayResolver.resolve(frame: frame, in: snapshot)
        let spacing = portalAppearance.spacing.points
        // Existing layouts may predate the screen-edge spacing preference. Icon
        // changes preserve their top-left anchor, while still enforcing screen
        // containment and the full gap from every other portal.
        return try PortalFrameConstraints.isValidPlacement(
            frame: frame,
            visibleFrame: display.visibleFrame.insetBy(dx: -spacing, dy: -spacing),
            otherPortalFrames: runtimePortalFrames(excluding: portalID),
            minimumGap: spacing
        )
    }

    private func runtimePortalFrames(excluding portalID: PortalID?) -> [NSRect] {
        portalStates.compactMap { portal in
            guard portal.id != portalID else { return nil }
            return windows[portal.id]?.presentedFrame ?? portal.frame
        }
    }

    private func portalSpacingLayoutPlan(
        snapshot: DisplaySnapshot,
        spacing: CGFloat
    ) -> [PortalID: NSRect]? {
        guard pendingUserPlacements.isEmpty,
              !windows.values.contains(where: \.isUserPlacementInteractionActive) else {
            return nil
        }

        var portalsByDisplay: [DisplayIdentity: [(id: PortalID, frame: NSRect)]] = [:]
        for portal in portalStates {
            guard let window = windows[portal.id],
                  let presentedFrame = window.presentedFrame else {
                continue
            }
            let baseFrame = spacingLayoutBaseFrames[portal.id] ?? presentedFrame
            guard let display = try? LegacyFrameDisplayResolver.resolve(
                frame: baseFrame,
                in: snapshot
            ) else {
                return nil
            }
            portalsByDisplay[display.identity, default: []].append((portal.id, baseFrame))
        }

        var plan: [PortalID: NSRect] = [:]
        for display in snapshot.displays {
            guard let entries = portalsByDisplay[display.identity] else { continue }
            let result: [NSRect]?
            do {
                result = try PortalFrameReflow.reflowedFrames(
                    entries.map(\.frame),
                    visibleFrame: display.visibleFrame,
                    minimumGap: spacing
                )
            } catch {
                return nil
            }
            guard let reflowedFrames = result else {
                return nil
            }
            for (entry, frame) in zip(entries, reflowedFrames) {
                plan[entry.id] = frame
            }
        }
        return plan
    }

    private func portalIconSizeLayoutPlan(
        snapshot: DisplaySnapshot,
        iconSize: IconSize,
        spacing: CGFloat,
        baseFrames: [PortalID: NSRect]?
    ) -> [PortalID: NSRect]? {
        let iconLayout = PortalIconLayout.fixed(iconSize)
        var plan: [PortalID: NSRect] = [:]
        var displays: [PortalID: DisplayDescriptor] = [:]

        for portal in portalStates {
            guard let currentFrame = baseFrames?[portal.id]
                    ?? windows[portal.id]?.presentedFrame else {
                continue
            }
            guard let display = try? LegacyFrameDisplayResolver.resolve(
                frame: currentFrame,
                in: snapshot
            ) else {
                return nil
            }
            let contentSize = PortalViewController.contentSize(
                for: portal.gridCapacity,
                iconLayout: iconLayout
            )
            let frameSize = NSWindow.frameRect(
                forContentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.resizable]
            ).size
            plan[portal.id] = NSRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - frameSize.height,
                width: frameSize.width,
                height: frameSize.height
            )
            displays[portal.id] = display
        }

        for (portalID, frame) in plan {
            guard let display = displays[portalID],
                  (try? PortalFrameConstraints.isValidPlacement(
                    frame: frame,
                    visibleFrame: display.visibleFrame,
                    otherPortalFrames: plan.compactMap { id, frame in
                        id == portalID ? nil : frame
                    },
                    minimumGap: spacing
                  )) == true else {
                return nil
            }
        }
        return plan
    }

    private func applyCurrentPortalSpacingLayout(
        snapshot: DisplaySnapshot,
        animated: Bool
    ) {
        guard pendingUserPlacements.isEmpty,
              !windows.values.contains(where: \.isUserPlacementInteractionActive) else {
            spacingLayoutNeedsRetry = true
            return
        }
        guard let plan = portalSpacingLayoutPlan(
            snapshot: snapshot,
            spacing: portalAppearance.spacing.points
        ) else {
            return
        }
        applyPortalSpacingLayout(plan, animated: animated)
        spacingLayoutNeedsRetry = false
    }

    private func applyPortalSpacingLayout(
        _ plan: [PortalID: NSRect],
        animated: Bool
    ) {
        for portal in portalStates {
            guard let frame = plan[portal.id],
                  windows[portal.id]?.presentedFrame != frame else {
                continue
            }
            _ = windows[portal.id]?.applySystemPlacement(frame: frame, animated: animated)
        }
    }

    private static func display(
        containingOrNearestTo point: NSPoint,
        in snapshot: DisplaySnapshot
    ) -> DisplayDescriptor {
        snapshot.displays.min { first, second in
            squaredDistance(from: point, to: first.visibleFrame)
                < squaredDistance(from: point, to: second.visibleFrame)
        } ?? snapshot.primaryDescriptor
    }

    private static func squaredDistance(from point: NSPoint, to frame: NSRect) -> CGFloat {
        let dx = max(max(frame.minX - point.x, 0), point.x - frame.maxX)
        let dy = max(max(frame.minY - point.y, 0), point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    private static func frameClampedToVisibleBounds(
        _ frame: NSRect,
        visibleFrame: NSRect,
        spacing: CGFloat
    ) -> NSRect {
        let usableFrame = spacing == 0
            ? visibleFrame
            : visibleFrame.insetBy(dx: spacing, dy: spacing)
        guard frame.width <= usableFrame.width, frame.height <= usableFrame.height else {
            return frame
        }
        return NSRect(
            x: min(max(frame.minX, usableFrame.minX), usableFrame.maxX - frame.width),
            y: min(max(frame.minY, usableFrame.minY), usableFrame.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
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
            isPinned: portal.isPinned,
            sortOrder: portal.sortOrder,
            tint: portal.tint
        )
    }

    private func removeRuntimeState(for portalID: PortalID) {
        placementSessions.removeValue(forKey: portalID)
        deferredTopologyPortals.remove(portalID)
        pendingUserPlacements.removeValue(forKey: portalID)
        pendingPlacementAttempts.removeValue(forKey: portalID)
        spacingLayoutBaseFrames.removeValue(forKey: portalID)
    }

    private func publishPortalMenu() {
        let entries = portalStates.map { portal in
            let title = portal.selectedTab?.folderURL.lastPathComponent
                ?? NSLocalizedString("portal.empty.title", comment: "Empty portal title")
            return PortalMenuEntry(id: portal.id, title: title, isPinned: portal.isPinned)
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
        gridCapacity: GridCapacity,
        anchor: FrameResizeAnchor = .bottomLeft,
        spacing: CGFloat = 0
    ) -> NSRect {
        let usableFrame = visibleFrame.insetBy(dx: spacing, dy: spacing)
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
            width: min(snappedFrameSize.width, usableFrame.width),
            height: min(snappedFrameSize.height, usableFrame.height)
        )
        let proposedY = switch anchor {
        case .bottomLeft: frame.minY
        case .topLeft: frame.maxY - size.height
        }
        let origin = NSPoint(
            x: min(max(frame.minX, usableFrame.minX), usableFrame.maxX - size.width),
            y: min(max(proposedY, usableFrame.minY), usableFrame.maxY - size.height)
        )
        return NSRect(origin: origin, size: size)
    }
}

private enum FrameResizeAnchor {
    case bottomLeft
    case topLeft
}

private struct PendingUserPlacement {
    let generation: UInt64
    let frame: NSRect
    let gridCapacity: GridCapacity?
}

enum PortalCoordinatorError: Error, Equatable {
    case persistentStateNotLoaded
    case placementUnavailable
    case layoutImportBusy
}

extension PortalCoordinatorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .persistentStateNotLoaded:
            NSLocalizedString(
                "portal.state.not_loaded",
                comment: "Portal state unavailable error"
            )
        case .placementUnavailable:
            NSLocalizedString(
                "portal.placement.unavailable.detail",
                comment: "Portal placement conflict detail"
            )
        case .layoutImportBusy:
            NSLocalizedString(
                "application.settings.backup.import_busy",
                comment: "Layout import busy error"
            )
        }
    }
}

enum StartupFolderResolver {
    static func resolve(arguments: [String]) -> URL? {
        guard arguments.count == 3, arguments[1] == "--folder" else { return nil }
        return URL(fileURLWithPath: arguments[2]).standardizedFileURL
    }
}
