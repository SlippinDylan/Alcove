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
    func testUserResizeCommitsOnceAtLiveResizeEnd() {
        let window = makeWindow()
        var commits: [NSRect] = []
        window.onUserPlacementCommit = { commits.append($0) }
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
        window.setContentSize(NSSize(width: minimum.width + 41, height: minimum.height + 73))
        var commits: [NSRect] = []
        controller.onUserPlacementCommit = { commits.append($0) }

        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification))
        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))

        XCTAssertEqual(
            window.contentRect(forFrameRect: window.frame).size,
            PortalViewController.snappedContentSize(
                NSSize(width: minimum.width + 41, height: minimum.height + 73),
                for: .medium
            )
        )
        XCTAssertEqual(commits, [window.frame])
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
    func testControllerForwardsBackgroundStyleRequestFromPortalView() throws {
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
        var requestedStyle: PortalBackgroundStyle?
        controller.onSetBackgroundStyle = { requestedStyle = $0 }
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let tabBar = try XCTUnwrap(
            allDescendants(of: contentView).compactMap { $0 as? TabBarView }.first
        )
        let submenu = try XCTUnwrap(
            tabBar.managementMenu.item(withTitle: "Background")?.submenu
        )
        let index = try XCTUnwrap(
            submenu.items.firstIndex { $0.title == "Low Transparency" }
        )

        submenu.performActionForItem(at: index)

        XCTAssertEqual(requestedStyle, .lowTransparency)
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
        window.onUserPlacementCommit = { commits.append($0) }
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
