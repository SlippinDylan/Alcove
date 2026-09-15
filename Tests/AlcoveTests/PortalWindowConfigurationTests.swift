import AppKit
import AlcoveCore
import XCTest
@testable import Alcove

final class PortalWindowConfigurationTests: XCTestCase {
    @MainActor
    func testDevelopmentStrategyAppliesToKeyEligiblePortalWindow() {
        let strategy = PortalWindowStrategy.developmentDefault
        let contentController = NSViewController()
        contentController.view = NSView()

        let window = PortalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            strategy: strategy,
            contentViewController: contentController
        )

        XCTAssertEqual(window.level, strategy.level)
        XCTAssertEqual(window.collectionBehavior, strategy.collectionBehavior)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertNil(window.standardWindowButton(.closeButton))
        XCTAssertNil(window.standardWindowButton(.miniaturizeButton))
        XCTAssertNil(window.standardWindowButton(.zoomButton))
        XCTAssertEqual(window.minSize, NSSize(width: 240, height: 240))
    }

    @MainActor
    func testWindowAppearanceTogglesTheSystemShadow() {
        let window = makeWindow()

        window.updateAppearance(PortalAppearancePreferences(
            cornerRadius: .small,
            spacing: .medium,
            shadowEnabled: false
        ))
        XCTAssertFalse(window.hasShadow)

        window.updateAppearance(PortalAppearancePreferences(
            cornerRadius: .maximum,
            spacing: .medium,
            shadowEnabled: true
        ))
        XCTAssertTrue(window.hasShadow)
    }

    @MainActor
    func testKeyEligibilityIsAnIndependentStrategyDimension() {
        let strategy = PortalWindowStrategy(
            level: .normal,
            collectionBehavior: [],
            canBecomeKey: false
        )
        let contentController = NSViewController()
        contentController.view = NSView()

        let window = PortalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            strategy: strategy,
            contentViewController: contentController
        )

        XCTAssertFalse(window.canBecomeKey)
        XCTAssertEqual(window.level, .normal)
        XCTAssertEqual(window.collectionBehavior, [])
    }

    @MainActor
    func testOnlyTopControlRowBackgroundIsADragRegion() {
        let window = makeWindow()
        let contentPoint = NSPoint(
            x: window.contentLayoutRect.midX,
            y: window.contentLayoutRect.midY
        )
        XCTAssertFalse(window.isPortalDragRegion(at: contentPoint))
        XCTAssertTrue(
            window.isPortalDragRegion(
                at: NSPoint(x: window.frame.width - 20, y: window.frame.height - 20)
            )
        )
        XCTAssertFalse(
            window.isPortalDragRegion(
                at: NSPoint(x: window.frame.width / 2, y: window.frame.height - 2)
            )
        )
        XCTAssertFalse(
            window.isPortalDragRegion(
                at: NSPoint(x: 2, y: window.frame.height - 2)
            )
        )
        XCTAssertFalse(
            window.isPortalDragRegion(
                at: NSPoint(x: window.frame.width - 2, y: window.frame.height - 2)
            )
        )

        let button = NSButton(frame: NSRect(x: 20, y: window.frame.height - 34, width: 80, height: 24))
        window.contentView?.addSubview(button)
        let buttonPoint = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        XCTAssertFalse(window.isPortalDragRegion(at: buttonPoint))
    }

    func testPlacementTrackerCommitsOnlyAfterADragEvent() {
        var tracker = PortalWindowUserPlacementTracker()
        let initialFrame = NSRect(x: 20, y: 30, width: 320, height: 240)

        tracker.begin(at: NSPoint(x: 10, y: 10), frame: initialFrame)
        XCTAssertTrue(tracker.isTracking)
        XCTAssertNil(tracker.finish())
        XCTAssertFalse(tracker.isTracking)

        tracker.begin(at: NSPoint(x: 10, y: 10), frame: initialFrame)
        XCTAssertEqual(
            tracker.drag(to: NSPoint(x: 35, y: 50)),
            NSRect(x: 45, y: 70, width: 320, height: 240)
        )
        XCTAssertEqual(
            tracker.finish(),
            NSRect(x: 45, y: 70, width: 320, height: 240)
        )
        XCTAssertFalse(tracker.isTracking)
    }

    @MainActor
    func testUserDragCommitsOnceOnMouseUpWithoutTrackingRunLoop() throws {
        let pointer = PointerLocation(NSPoint(x: 10, y: 10))
        let window = makeWindow(pointerLocationProvider: { pointer.location })
        var commits: [NSRect] = []
        window.onUserPlacementCommit = { commits.append($0) }
        let initialOrigin = window.frame.origin
        window.beginUserDrag(at: NSPoint(x: 10, y: 10))

        pointer.location = NSPoint(x: 50, y: 70)
        window.handleUserDragEvent(try event(.leftMouseDragged, at: .zero, in: window))
        XCTAssertEqual(
            window.frame.origin,
            NSPoint(x: initialOrigin.x + 40, y: initialOrigin.y + 60)
        )
        XCTAssertTrue(window.isUserPlacementInteractionActive)
        XCTAssertTrue(window.applySystemPlacement(frame: NSRect(x: 100, y: 100, width: 560, height: 480)) == false)

        window.handleUserDragEvent(try event(.leftMouseUp, at: .zero, in: window))
        XCTAssertEqual(commits, [window.frame])
        XCTAssertFalse(window.isUserPlacementInteractionActive)
        XCTAssertTrue(window.applySystemPlacement(frame: NSRect(x: 100, y: 100, width: 560, height: 480)))
        XCTAssertEqual(window.frame, NSRect(x: 100, y: 100, width: 560, height: 480))
    }

    @MainActor
    func testUserDragDisplaysAndCommitsTheConstrainedFrame() throws {
        let pointer = PointerLocation(NSPoint(x: 10, y: 10))
        let window = makeWindow(pointerLocationProvider: { pointer.location })
        let constrainedFrame = window.frame.offsetBy(dx: 12, dy: 18)
        var commits: [NSRect] = []
        window.constrainUserDragFrame = { _, _, _ in constrainedFrame }
        window.onUserPlacementCommit = { commits.append($0) }
        window.beginUserDrag(at: pointer.location)

        pointer.location = NSPoint(x: 200, y: 200)
        window.handleUserDragEvent(try event(.leftMouseDragged, at: .zero, in: window))
        window.handleUserDragEvent(try event(.leftMouseUp, at: .zero, in: window))

        XCTAssertEqual(window.frame, constrainedFrame)
        XCTAssertEqual(commits, [constrainedFrame])
    }

    @MainActor
    func testLiveResizeRestoresTheLastValidFrame() {
        let window = makeWindow()
        let initialFrame = window.frame
        window.isValidUserPlacement = { $0.width <= initialFrame.width + 20 }
        window.beginUserResize()

        let validFrame = NSRect(
            origin: initialFrame.origin,
            size: NSSize(width: initialFrame.width + 20, height: initialFrame.height)
        )
        window.setFrame(validFrame, display: false)
        window.enforceLiveResizeConstraint()
        window.setFrame(
            NSRect(
                origin: initialFrame.origin,
                size: NSSize(width: initialFrame.width + 80, height: initialFrame.height)
            ),
            display: false
        )
        window.enforceLiveResizeConstraint()

        XCTAssertEqual(window.frame, validFrame)
        window.cancelUserPlacementInteraction(notify: false)
    }

    @MainActor
    func testZeroDistanceDragCancelsWithoutCommitting() throws {
        let pointer = PointerLocation(NSPoint(x: 10, y: 10))
        let window = makeWindow(pointerLocationProvider: { pointer.location })
        var commits: [NSRect] = []
        var cancellationCount = 0
        window.onUserPlacementCommit = { commits.append($0) }
        window.onUserPlacementInteractionCancelled = { cancellationCount += 1 }
        window.beginUserDrag(at: pointer.location)

        window.handleUserDragEvent(try event(.leftMouseDragged, at: .zero, in: window))
        window.handleUserDragEvent(try event(.leftMouseUp, at: .zero, in: window))

        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(cancellationCount, 1)
    }

    @MainActor
    func testUserResizeCommitsOnceAtLiveResizeEnd() {
        let window = makeWindow()
        var commits: [NSRect] = []
        window.onUserResizeCommit = { commits.append($0) }
        window.beginUserResize()
        window.setFrame(NSRect(x: 80, y: 90, width: 400, height: 300), display: false)

        XCTAssertTrue(window.isUserPlacementInteractionActive)
        XCTAssertFalse(window.applySystemPlacement(frame: NSRect(x: 10, y: 20, width: 300, height: 240)))
        window.endUserResize()
        window.endUserResize()

        XCTAssertEqual(commits, [NSRect(x: 80, y: 90, width: 400, height: 300)])
        XCTAssertFalse(window.isUserPlacementInteractionActive)
    }

    @MainActor
    func testUnchangedUserResizeCancelsWithoutCommitting() {
        let window = makeWindow()
        var commits: [NSRect] = []
        var cancellationCount = 0
        window.onUserResizeCommit = { commits.append($0) }
        window.onUserPlacementInteractionCancelled = { cancellationCount += 1 }

        window.beginUserResize()
        window.endUserResize()

        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(cancellationCount, 1)
    }

    @MainActor
    func testPinnedWindowRejectsUserPlacementAndResizeButAcceptsSystemPlacement() throws {
        let pointer = PointerLocation(NSPoint(x: 10, y: 10))
        let window = makeWindow(pointerLocationProvider: { pointer.location })
        let initialFrame = window.frame
        var placementCommits: [NSRect] = []
        var resizeCommits: [NSRect] = []
        window.onUserPlacementCommit = { placementCommits.append($0) }
        window.onUserResizeCommit = { resizeCommits.append($0) }

        window.setPinned(true)

        XCTAssertTrue(window.isPinned)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isPortalDragRegion(at: NSPoint(x: 100, y: 220)))
        window.beginUserDrag(at: pointer.location)
        pointer.location = NSPoint(x: 50, y: 70)
        window.handleUserDragEvent(try event(.leftMouseDragged, at: .zero, in: window))
        window.beginUserResize()

        XCTAssertEqual(window.frame, initialFrame)
        XCTAssertFalse(window.isUserPlacementInteractionActive)
        XCTAssertTrue(placementCommits.isEmpty)
        XCTAssertTrue(resizeCommits.isEmpty)

        let systemFrame = NSRect(x: 100, y: 120, width: 400, height: 300)
        XCTAssertTrue(window.applySystemPlacement(frame: systemFrame))
        XCTAssertEqual(window.frame, systemFrame)

        window.setPinned(false)
        XCTAssertFalse(window.isPinned)
        XCTAssertTrue(window.styleMask.contains(.resizable))
    }

    @MainActor
    func testAnimatedSystemPlacementDoesNotCommitAsUserResize() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: NSRect(x: 20, y: 30, width: 428, height: 316),
            display: DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "test-display"),
                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
            )
        )
        let controller = PortalWindowController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(),
            initialFrame: portal.frame
        )
        controller.present()
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window as? PortalWindow)
        var resizeCommitCount = 0
        controller.onUserResizeCommit = { _, _ in resizeCommitCount += 1 }

        let movedFrame = portal.frame.offsetBy(dx: 20, dy: -20)
        XCTAssertTrue(controller.applySystemPlacement(frame: movedFrame, animated: true))
        let resizedFrame = NSRect(
            origin: movedFrame.origin,
            size: NSSize(width: movedFrame.width + 40, height: movedFrame.height + 40)
        )
        XCTAssertTrue(controller.applySystemPlacement(frame: resizedFrame, animated: true))

        XCTAssertEqual(window.frame, resizedFrame)
        XCTAssertFalse(window.isUserPlacementInteractionActive)
        XCTAssertEqual(resizeCommitCount, 0)
    }

    @MainActor
    func testControllerSnapsContentSizeBeforeCommittingLiveResize() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: NSRect(x: 20, y: 30, width: 560, height: 480),
            display: DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "test-display"),
                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
            ),
            iconSize: .medium
        )
        let controller = PortalWindowController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(),
            initialFrame: portal.frame
        )
        let window = try XCTUnwrap(controller.window as? PortalWindow)
        let minimum = PortalViewController.minimumContentSize(for: .medium)
        var commits: [(NSRect, GridCapacity)] = []
        controller.onUserResizeCommit = { commits.append(($0, $1)) }

        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
        window.setContentSize(NSSize(width: minimum.width + 41, height: minimum.height + 73))
        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

        XCTAssertEqual(
            window.contentRect(forFrameRect: window.frame).size,
            PortalViewController.snappedContentSize(
                NSSize(width: minimum.width + 41, height: minimum.height + 73),
                for: .medium
            )
        )
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].0, window.frame)
        XCTAssertEqual(commits[0].1, try GridCapacity(columns: 3, rows: 2))
    }

    @MainActor
    func testControllerDoesNotSnapOrCommitAnUnchangedLiveResize() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: NSRect(x: 20, y: 30, width: 560, height: 480),
            display: DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "test-display"),
                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
            )
        )
        let controller = PortalWindowController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(),
            initialFrame: portal.frame
        )
        let window = try XCTUnwrap(controller.window as? PortalWindow)
        let initialFrame = window.frame
        var commitCount = 0
        controller.onUserResizeCommit = { _, _ in commitCount += 1 }

        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

        XCTAssertEqual(window.frame, initialFrame)
        XCTAssertEqual(commitCount, 0)
    }

    @MainActor
    func testControllerSwitchesCapacityAtHalfCellThresholdsDuringLiveResize() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: NSRect(x: 20, y: 30, width: 560, height: 480),
            display: DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "test-display"),
                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
            )
        )
        let controller = PortalWindowController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(),
            initialFrame: portal.frame
        )
        let window = try XCTUnwrap(controller.window)
        let minimum = PortalViewController.contentSize(
            for: .minimum,
            iconLayout: portal.iconLayout
        )
        let metrics = GridMetrics(iconSize: portal.iconSize, labelFontSize: portal.textSize)
        let columnPitch = metrics.itemSize.width + metrics.horizontalSpacing
        let rowPitch = metrics.itemSize.height + metrics.verticalSpacing

        let belowThreshold = frameSize(
            for: NSSize(
                width: minimum.width + columnPitch * 0.2,
                height: minimum.height + rowPitch * 0.2
            ),
            in: window
        )
        let belowResult = controller.windowWillResize(window, toFrameSize: belowThreshold)
        XCTAssertEqual(contentSize(for: belowResult, in: window), minimum)

        let threshold = frameSize(
            for: NSSize(
                width: minimum.width + columnPitch * 0.5,
                height: minimum.height + rowPitch * 0.5
            ),
            in: window
        )
        let thresholdResult = controller.windowWillResize(window, toFrameSize: threshold)
        XCTAssertEqual(
            contentSize(for: thresholdResult, in: window),
            PortalViewController.contentSize(
                for: try GridCapacity(columns: 4, rows: 2),
                iconLayout: portal.iconLayout
            )
        )
    }

    @MainActor
    func testPresentReinstallsQuickLookAfterWindowClose() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: NSRect(x: 20, y: 30, width: 560, height: 480),
            display: DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "test-display"),
                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
            )
        )
        let quickLook = QuickLookIntegration(panelProvider: { nil })
        let controller = PortalWindowController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(),
            initialFrame: portal.frame,
            quickLookIntegration: quickLook
        )
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.nextResponder === quickLook)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        XCTAssertFalse(window.nextResponder === quickLook)

        controller.present()
        XCTAssertTrue(window.nextResponder === quickLook)
        controller.close()
    }

    @MainActor
    func testControllerPortalSettingsDoNotExposeGlobalBackgroundControl() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: NSRect(x: 20, y: 30, width: 560, height: 480),
            display: DisplayDescriptor(
                identity: DisplayIdentity(rawValue: "test-display"),
                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
            )
        )
        let controller = PortalWindowController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(),
            initialFrame: portal.frame
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let tabBar = try XCTUnwrap(
            allDescendants(of: contentView).compactMap { $0 as? TabBarView }.first
        )
        tabBar.showSettingsWindow()
        let settingsController = try XCTUnwrap(tabBar.settingsWindowController)
        let settingsViewController = settingsController.settingsViewController
        settingsController.selectCategory(.style)
        let settingsRoot = settingsViewController.view
        settingsController.close()
        XCTAssertFalse(allDescendants(of: settingsRoot).contains {
            $0.identifier?.rawValue == "portal-settings.background"
        })
    }

    @MainActor
    func testCancelledDragClearsInteractionWithoutCommitting() {
        let window = makeWindow()
        var commits: [NSRect] = []
        var cancellationCount = 0
        window.onUserPlacementCommit = { commits.append($0) }
        window.onUserPlacementInteractionCancelled = { cancellationCount += 1 }
        window.beginUserDrag(at: NSPoint(x: 10, y: 10))

        window.handleUserDragEvent(nil)

        XCTAssertFalse(window.isUserPlacementInteractionActive)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(cancellationCount, 1)
    }

    @MainActor
    func testCancellingResizeClearsInteractionWithoutCommitting() {
        let window = makeWindow()
        var commits: [NSRect] = []
        var cancellationCount = 0
        window.onUserResizeCommit = { commits.append($0) }
        window.onUserPlacementInteractionCancelled = { cancellationCount += 1 }
        window.beginUserResize()

        window.cancelUserPlacementInteraction()
        window.endUserResize()

        XCTAssertFalse(window.isUserPlacementInteractionActive)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(cancellationCount, 1)
    }

    @MainActor
    private func makeWindow(
        pointerLocationProvider: @escaping () -> NSPoint = { NSEvent.mouseLocation }
    ) -> PortalWindow {
        let contentController = NSViewController()
        contentController.view = NSView()
        return PortalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            strategy: .developmentDefault,
            contentViewController: contentController,
            pointerLocationProvider: pointerLocationProvider
        )
    }

    @MainActor
    private func frameSize(for contentSize: NSSize, in window: NSWindow) -> NSSize {
        window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
    }

    @MainActor
    private func contentSize(for frameSize: NSSize, in window: NSWindow) -> NSSize {
        window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: frameSize)
        ).size
    }

    @MainActor
    private func allDescendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allDescendants)
    }

    @MainActor
    private func event(
        _ type: NSEvent.EventType,
        at location: NSPoint,
        in window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    @MainActor
    private final class PointerLocation {
        var location: NSPoint

        init(_ location: NSPoint) {
            self.location = location
        }
    }
}
