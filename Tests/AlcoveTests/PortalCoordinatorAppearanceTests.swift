import AlcoveCore
import AppKit
import XCTest
@testable import Alcove

extension PortalCoordinatorTests {
    @MainActor
    func testSpacingPreferenceReflowsExistingPortalsAndReturnsToSavedFrames() async throws {
        let upper = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/upper"),
            frame: NSRect(x: 12, y: 488, width: 500, height: 400),
            display: coordinatorTestDisplay
        )
        let lower = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/lower"),
            frame: NSRect(x: 12, y: 176, width: 500, height: 300),
            display: coordinatorTestDisplay
        )
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let factory = PortalWindowFactorySpy()
        let minimumAppearance = PortalAppearancePreferences(
            cornerRadius: .maximum,
            spacing: .minimum,
            shadowEnabled: true
        )
        let store = PortalStoreSpy(portals: [upper, lower])
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            portalAppearance: minimumAppearance,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()
        let minimumFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(minimumFrames[0].minX, PortalSpacing.minimum.points)
        XCTAssertEqual(
            minimumFrames[0].maxY,
            coordinatorTestDisplay.visibleFrame.maxY - PortalSpacing.minimum.points
        )
        XCTAssertEqual(
            minimumFrames[0].minY - minimumFrames[1].maxY,
            PortalSpacing.minimum.points
        )

        var maximumAppearance = minimumAppearance
        maximumAppearance.spacing = .maximum
        XCTAssertTrue(coordinator.updatePortalAppearance(maximumAppearance))

        let maximumFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(maximumFrames[0].minX, PortalSpacing.maximum.points)
        XCTAssertEqual(
            maximumFrames[0].maxY,
            coordinatorTestDisplay.visibleFrame.maxY - PortalSpacing.maximum.points
        )
        XCTAssertEqual(
            maximumFrames[0].minY - maximumFrames[1].maxY,
            PortalSpacing.maximum.points
        )
        XCTAssertEqual(factory.windows.flatMap(\.systemPlacementAnimations).last, true)

        XCTAssertTrue(coordinator.updatePortalAppearance(minimumAppearance))
        let restoredFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(restoredFrames, minimumFrames)
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    func testGlobalContentSizeKeepsAttachedPortalsAtTheSelectedGap() async throws {
        let capacity = GridCapacity.minimum
        let mediumContentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: .fixed(.medium)
        )
        let mediumFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: mediumContentSize),
            styleMask: [.resizable]
        ).size
        let spacing = PortalSpacing.medium.points
        let visibleFrame = coordinatorTestDisplay.visibleFrame
        let upperFrame = NSRect(
            x: visibleFrame.minX + spacing,
            y: visibleFrame.maxY - spacing - mediumFrameSize.height,
            width: mediumFrameSize.width,
            height: mediumFrameSize.height
        )
        let lowerFrame = NSRect(
            x: upperFrame.minX,
            y: upperFrame.minY - spacing - mediumFrameSize.height,
            width: mediumFrameSize.width,
            height: mediumFrameSize.height
        )
        let upper = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/upper"),
            frame: upperFrame,
            display: coordinatorTestDisplay,
            iconLayout: .fixed(.medium),
            gridCapacity: capacity
        )
        let lower = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/lower"),
            frame: lowerFrame,
            display: coordinatorTestDisplay,
            iconLayout: .fixed(.medium),
            gridCapacity: capacity
        )
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let factory = PortalWindowFactorySpy()
        let mediumAppearance = PortalAppearancePreferences(
            iconSize: .medium,
            backgroundStyle: .standard,
            cornerRadius: .maximum,
            spacing: .medium,
            shadowEnabled: true
        )
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [upper, lower]),
            windowFactory: factory,
            portalAppearance: mediumAppearance,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        var smallAppearance = mediumAppearance
        smallAppearance.iconSize = .small
        XCTAssertTrue(coordinator.updatePortalAppearance(smallAppearance))
        let smallFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(smallFrames[0].maxY, upperFrame.maxY)
        XCTAssertEqual(smallFrames[0].minY - smallFrames[1].maxY, spacing)
        XCTAssertGreaterThan(smallFrames[1].minY, lowerFrame.minY)

        var largeAppearance = mediumAppearance
        largeAppearance.iconSize = .large
        largeAppearance.spacing = .maximum
        XCTAssertTrue(coordinator.updatePortalAppearance(largeAppearance))
        let largeFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(
            largeFrames[0].maxY,
            visibleFrame.maxY - PortalSpacing.maximum.points
        )
        XCTAssertEqual(
            largeFrames[0].minY - largeFrames[1].maxY,
            PortalSpacing.maximum.points
        )
        XCTAssertLessThan(largeFrames[1].minY, smallFrames[1].minY)

        XCTAssertTrue(coordinator.updatePortalAppearance(mediumAppearance))
        let restoredFrames = try factory.windows.map { try XCTUnwrap($0.presentedFrame) }
        XCTAssertEqual(restoredFrames, [upperFrame, lowerFrame])
    }

    @MainActor
    func testRestoreNormalizesGlobalContentSizeWithoutLosingAttachment() async throws {
        let capacity = GridCapacity.minimum
        let mediumContentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: .fixed(.medium)
        )
        let mediumFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: mediumContentSize),
            styleMask: [.resizable]
        ).size
        let smallContentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: .fixed(.small)
        )
        let smallFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: smallContentSize),
            styleMask: [.resizable]
        ).size
        let gap = PortalSpacing.medium.points
        let upperFrame = NSRect(
            x: gap,
            y: coordinatorTestDisplay.visibleFrame.maxY - gap - mediumFrameSize.height,
            width: mediumFrameSize.width,
            height: mediumFrameSize.height
        )
        let lowerFrame = NSRect(
            x: gap,
            y: upperFrame.minY - gap - smallFrameSize.height,
            width: smallFrameSize.width,
            height: smallFrameSize.height
        )
        let portals = try [
            Portal(
                folderURL: URL(fileURLWithPath: "/tmp/upper"),
                frame: upperFrame,
                display: coordinatorTestDisplay,
                iconLayout: .fixed(.medium),
                gridCapacity: capacity
            ),
            Portal(
                folderURL: URL(fileURLWithPath: "/tmp/lower"),
                frame: lowerFrame,
                display: coordinatorTestDisplay,
                iconLayout: .fixed(.small),
                gridCapacity: capacity
            ),
        ]
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let store = PortalStoreSpy(portals: portals)
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            portalAppearance: PortalAppearancePreferences(
                iconSize: .small,
                backgroundStyle: .standard,
                cornerRadius: .maximum,
                spacing: .medium,
                shadowEnabled: true
            ),
            displaySnapshotProvider: { .success(snapshot) }
        )

        try await coordinator.restorePortals()

        XCTAssertTrue(coordinator.portalStates.allSatisfy { $0.iconSize == .small })
        XCTAssertEqual(
            coordinator.portalStates[0].frame.minY - coordinator.portalStates[1].frame.maxY,
            gap
        )
        XCTAssertEqual(
            try factory.windows.map { try XCTUnwrap($0.presentedFrame) },
            coordinator.portalStates.map(\.frame)
        )
        let saves = await store.savedSnapshots()
        XCTAssertEqual(saves, [coordinator.portalStates])
    }

    @MainActor
    func testRestoreSizeNormalizationPreservesDisconnectedHomeDisplay() async throws {
        let portal = try makePortal(path: "/tmp/disconnected", x: 10)
        let fallback = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "fallback-display"),
            visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 700)
        )
        let snapshot = try DisplaySnapshot(
            displays: [fallback],
            primaryDisplay: fallback.identity
        )
        let factory = PortalWindowFactorySpy()
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal]),
            windowFactory: factory,
            portalAppearance: PortalAppearancePreferences(
                iconSize: .large,
                backgroundStyle: .standard,
                cornerRadius: .maximum,
                spacing: .medium,
                shadowEnabled: true
            ),
            displaySnapshotProvider: { .success(snapshot) }
        )

        try await coordinator.restorePortals()

        XCTAssertEqual(coordinator.portalStates[0].iconSize, .large)
        XCTAssertEqual(
            coordinator.portalStates[0].placement.homeDisplay,
            portal.placement.homeDisplay
        )
        XCTAssertTrue(
            fallback.visibleFrame.contains(try XCTUnwrap(factory.windows[0].presentedFrame))
        )
    }

    @MainActor
    func testGlobalLargeIconPresetAppliesMinimumPlacementWithoutPortalSave() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        var appearance = PortalAppearancePreferences.defaults
        appearance.iconSize = .large
        XCTAssertTrue(coordinator.updatePortalAppearance(appearance))

        let updated = coordinator.portalStates[0]
        XCTAssertEqual(updated.iconSize, .large)
        XCTAssertEqual(updated.gridCapacity, portal.gridCapacity)
        let updatedContentSize = NSWindow.contentRect(
            forFrameRect: updated.frame,
            styleMask: [.resizable]
        ).size
        XCTAssertEqual(
            updatedContentSize,
            PortalViewController.contentSize(
                for: portal.gridCapacity,
                iconLayout: .fixed(.large)
            )
        )
        let appliedFrame = try XCTUnwrap(factory.windows[0].systemFrames.last)
        XCTAssertEqual(appliedFrame.size, updated.frame.size)
        XCTAssertTrue(coordinatorTestDisplay.visibleFrame.contains(appliedFrame))
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    func testGlobalIconPresetExpansionReflowsBothPortals() async throws {
        let first = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: NSRect(x: 100, y: 300, width: 320, height: 240),
            display: coordinatorTestDisplay
        )
        let largeContentSize = PortalViewController.contentSize(
            for: first.gridCapacity,
            iconLayout: .fixed(.large)
        )
        let largeFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: largeContentSize),
            styleMask: [.resizable]
        ).size
        let second = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/second"),
            frame: NSRect(
                x: first.frame.minX + largeFrameSize.width + 5,
                y: 300,
                width: 320,
                height: 240
            ),
            display: coordinatorTestDisplay
        )
        let store = PortalStoreSpy(portals: [first, second])
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: PortalWindowFactorySpy(),
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        var appearance = PortalAppearancePreferences.defaults
        appearance.iconSize = .large
        XCTAssertTrue(coordinator.updatePortalAppearance(appearance))

        XCTAssertTrue(coordinator.portalStates.allSatisfy { $0.iconSize == .large })
        let saves = await store.savedSnapshots()
        XCTAssertTrue(saves.isEmpty)
    }

    @MainActor
    func testIconLayoutChangePreservesCapacityAndFitsNewMetrics() async throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: NSRect(x: 20, y: 30, width: 560, height: 480),
            display: coordinatorTestDisplay
        )
        let store = PortalStoreSpy(portals: [portal])
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: PortalWindowFactorySpy()
        )
        try await coordinator.restorePortals()
        let expectedContentSize = PortalViewController.contentSize(
            for: portal.gridCapacity,
            iconLayout: .fixed(.large)
        )

        var appearance = PortalAppearancePreferences.defaults
        appearance.iconSize = .large
        XCTAssertTrue(coordinator.updatePortalAppearance(appearance))

        let updatedContentSize = NSWindow.contentRect(
            forFrameRect: NSRect(
                origin: .zero,
                size: coordinator.portalStates[0].frame.size
            ),
            styleMask: [.resizable]
        ).size
        XCTAssertEqual(updatedContentSize, expectedContentSize)
        XCTAssertEqual(coordinator.portalStates[0].gridCapacity, portal.gridCapacity)
    }

    @MainActor
    func testIconPresetChangesKeepThePortalTopLeftCornerFixed() async throws {
        let capacity = try GridCapacity(columns: 4, rows: 2)
        let mediumContentSize = PortalViewController.contentSize(
            for: capacity,
            iconLayout: .fixed(.medium)
        )
        let mediumFrameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: mediumContentSize),
            styleMask: [.resizable]
        ).size
        let visibleFrame = coordinatorTestDisplay.visibleFrame
        let initialFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.maxY - mediumFrameSize.height,
            width: mediumFrameSize.width,
            height: mediumFrameSize.height
        )
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: initialFrame,
            display: coordinatorTestDisplay,
            iconLayout: .fixed(.medium),
            gridCapacity: capacity
        )
        let snapshot = try DisplaySnapshot(
            displays: [coordinatorTestDisplay],
            primaryDisplay: coordinatorTestDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal]),
            windowFactory: PortalWindowFactorySpy(),
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        var appearance = PortalAppearancePreferences.defaults
        for iconSize: IconSize in [.large, .medium, .small] {
            appearance.iconSize = iconSize
            XCTAssertTrue(coordinator.updatePortalAppearance(appearance))
            let frame = coordinator.portalStates[0].frame
            XCTAssertEqual(frame.minX, initialFrame.minX)
            XCTAssertEqual(frame.maxY, initialFrame.maxY)
        }
    }

    @MainActor
    func testIconPresetChangeUsesTheCurrentHomeDisplayVisibleFrame() async throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: NSRect(x: 0, y: 500, width: 560, height: 400),
            display: coordinatorTestDisplay
        )
        let currentDisplay = DisplayDescriptor(
            identity: coordinatorTestDisplay.identity,
            visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 760)
        )
        let snapshot = try DisplaySnapshot(
            displays: [currentDisplay],
            primaryDisplay: currentDisplay.identity
        )
        let coordinator = PortalCoordinator(
            store: PortalStoreSpy(portals: [portal]),
            windowFactory: PortalWindowFactorySpy(),
            displaySnapshotProvider: { .success(snapshot) }
        )
        try await coordinator.restorePortals()

        var appearance = PortalAppearancePreferences.defaults
        appearance.iconSize = .large
        XCTAssertTrue(coordinator.updatePortalAppearance(appearance))

        let updated = coordinator.portalStates[0]
        XCTAssertEqual(updated.frame.maxY, currentDisplay.visibleFrame.maxY)
        XCTAssertEqual(
            updated.placement.homeEntry.referenceVisibleFrame,
            currentDisplay.visibleFrame
        )
    }

    @MainActor
    func testIconPresetDuringPrimarySwitchPreservesDurableHomeAndFollowsPrimary() async throws {
        let portal = try makePortal(path: "/tmp/first", x: 10)
        let store = PortalStoreSpy(portals: [portal])
        let factory = PortalWindowFactorySpy()
        let fallback = DisplayDescriptor(
            identity: DisplayIdentity(rawValue: "fallback-display"),
            visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 700)
        )
        let snapshotBox = DisplaySnapshotResultBox(
            .success(
                try DisplaySnapshot(
                    displays: [coordinatorTestDisplay],
                    primaryDisplay: coordinatorTestDisplay.identity
                )
            )
        )
        let coordinator = PortalCoordinator(
            store: store,
            windowFactory: factory,
            displaySnapshotProvider: { snapshotBox.result }
        )
        try await coordinator.restorePortals()
        snapshotBox.result = .success(
            try DisplaySnapshot(displays: [fallback], primaryDisplay: fallback.identity)
        )
        coordinator.reconcileDisplayTopology(snapshotBox.result)
        await coordinator.waitForPersistenceForTesting()

        var appearance = PortalAppearancePreferences.defaults
        appearance.iconSize = .large
        XCTAssertTrue(coordinator.updatePortalAppearance(appearance))

        XCTAssertEqual(coordinator.portalStates[0].placement.homeDisplay, portal.placement.homeDisplay)
        XCTAssertTrue(fallback.visibleFrame.contains(try XCTUnwrap(factory.windows[0].systemFrames.last)))

        snapshotBox.result = .success(
            try DisplaySnapshot(
                displays: [fallback, coordinatorTestDisplay],
                primaryDisplay: fallback.identity
            )
        )
        coordinator.reconcileDisplayTopology(snapshotBox.result)
        await coordinator.waitForPersistenceForTesting()

        XCTAssertTrue(fallback.visibleFrame.contains(try XCTUnwrap(factory.windows[0].systemFrames.last)))
        XCTAssertEqual(coordinator.portalStates[0].placement.homeDisplay, portal.placement.homeDisplay)
    }

}
