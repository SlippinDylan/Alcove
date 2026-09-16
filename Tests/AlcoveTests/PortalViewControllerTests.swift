import AlcoveCore
import XCTest
@testable import Alcove

final class PortalViewControllerTests: XCTestCase {
    @MainActor
    func testEmptyPortalShowsFolderChoiceInsideThePortal() throws {
        let controller = PortalViewController(
            portal: try Portal(
                frame: CGRect(x: 0, y: 0, width: 344, height: 180),
                display: testDisplay
            ),
            loadingCoordinator: FolderLoadingCoordinator()
        )
        var addRequestCount = 0
        controller.onAddTab = { addRequestCount += 1 }

        controller.loadView()

        XCTAssertEqual(controller.presentationState, .emptyPortal)
        let chooseButton = try XCTUnwrap(
            descendants(of: controller.view)
                .compactMap { $0 as? NSButton }
                .first {
                    $0.accessibilityLabel()
                        == NSLocalizedString("portal.choose.help", comment: "")
                }
        )
        XCTAssertFalse(chooseButton.isHidden)
        let pathBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? FolderPathBarView }.first
        )
        XCTAssertNil(pathBar.displayedPath)
        chooseButton.performClick(nil)
        XCTAssertEqual(addRequestCount, 1)
    }

    @MainActor
    func testPortalUsesOneBackgroundMaterialAndTwoSectionSeparators() throws {
        let controller = PortalViewController(
            portal: try Portal(
                folderURL: URL(fileURLWithPath: "/tmp/portal"),
                frame: CGRect(x: 0, y: 0, width: 420, height: 360),
                display: testDisplay
            ),
            loadingCoordinator: FolderLoadingCoordinator()
        )

        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 420, height: 360)
        controller.view.layoutSubtreeIfNeeded()

        let materials = descendants(of: controller.view)
            .compactMap { $0 as? PortalChromeMaterialView }
        let surface = try XCTUnwrap(materials.first)
        XCTAssertNotNil(surface.materialView)
        XCTAssertEqual(materials.count, 1)
        XCTAssertEqual(controller.topSeparator.boxType, .separator)
        XCTAssertEqual(controller.bottomSeparator.boxType, .separator)
        XCTAssertEqual(controller.topSeparator.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(controller.bottomSeparator.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(
            controller.topSeparator.frame.width,
            controller.view.bounds.width,
            accuracy: 0.5
        )
        XCTAssertEqual(
            controller.bottomSeparator.frame.width,
            controller.view.bounds.width,
            accuracy: 0.5
        )
    }

    @MainActor
    func testManagementMenuForwardsTheNextPersistentPinnedState() throws {
        var portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator()
        )
        var requestedStates: [Bool] = []
        controller.onSetPinned = { requestedStates.append($0) }
        controller.loadView()
        let tabBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? TabBarView }.first
        )

        tabBar.makeManagementMenu().performActionForItem(at: 0)
        portal.updatePinned(true)
        controller.updatePortal(portal)
        let pinnedMenu = tabBar.makeManagementMenu()
        pinnedMenu.performActionForItem(at: 0)

        XCTAssertEqual(requestedStates, [true, false])
        XCTAssertEqual(
            pinnedMenu.items[0].title,
            NSLocalizedString("portal.pin.unpin", comment: "")
        )
    }

    @MainActor
    func testGlobalTransparencyUpdateOnlyChangesStaticSurfaceWithoutInvalidatingSelection() async throws {
        let root = URL(fileURLWithPath: "/tmp/portal")
        let item = FileItem(
            url: root.appendingPathComponent("one"),
            name: "one",
            isDirectory: false,
            isHidden: false
        )
        var portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator(
                enumerator: FixedFolderEnumerator(root: root, items: [item])
            ),
            materialAccessibilityProvider: {
                PortalAccessibilityOptions(
                    reduceTransparency: false,
                    increaseContrast: false,
                    reduceMotion: false
                )
            }
        )
        var invalidationCount = 0
        controller.onSelectionInvalidated = { invalidationCount += 1 }
        controller.loadView()
        await controller.reload()
        let surface = try XCTUnwrap(
            descendants(of: controller.view)
                .compactMap { $0 as? PortalChromeMaterialView }
                .first
        )

        portal.updateBackgroundStyle(.lowTransparency)
        controller.updatePortal(portal)

        XCTAssertEqual(surface.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(surface.materialPath, .translucent)
        XCTAssertEqual(
            try XCTUnwrap(surface.materialView?.layer?.backgroundColor).alpha,
            0.52,
            accuracy: 0.001
        )
        XCTAssertEqual(controller.presentationState, .items(1))
        XCTAssertEqual(invalidationCount, 0)
    }

    @MainActor
    func testPortalSettingsDoNotExposeGlobalBackgroundControl() throws {
        let portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/portal"),
            frame: CGRect(x: 0, y: 0, width: 420, height: 360),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator()
        )
        controller.loadView()
        let tabBar = try XCTUnwrap(
            descendants(of: controller.view).compactMap { $0 as? TabBarView }.first
        )
        tabBar.showSettingsWindow()
        let settingsController = try XCTUnwrap(tabBar.settingsWindowController)
        let settingsViewController = settingsController.settingsViewController
        settingsController.selectCategory(.style)
        let settingsRoot = settingsViewController.view
        settingsController.close()
        XCTAssertFalse(descendants(of: settingsRoot).contains {
            $0.identifier?.rawValue == "portal-settings.background"
        })
    }

    @MainActor
    func testSelectedFolderCapsuleIsVisibleOnTheFirstPortalWindowLayout() throws {
        var portal = try Portal(
            folderURL: URL(fileURLWithPath: "/tmp/first"),
            frame: CGRect(x: 0, y: 0, width: 500, height: 360),
            display: testDisplay
        )
        _ = try portal.appendTab(folderURL: URL(fileURLWithPath: "/tmp/second"))
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: FolderLoadingCoordinator()
        )
        let window = PortalWindow(
            contentRect: portal.frame,
            strategy: .developmentDefault,
            contentViewController: controller
        )

        window.contentView?.layoutSubtreeIfNeeded()

        let contentView = try XCTUnwrap(window.contentView)
        let buttons = descendants(of: contentView)
            .compactMap { $0 as? PortalTabButton }
        XCTAssertEqual(buttons.count, 2)
        XCTAssertTrue(buttons.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 })
        let selectedButton = try XCTUnwrap(buttons.first { $0.isTabSelected })
        let selectedFrame = selectedButton.convert(selectedButton.bounds, to: contentView)
        XCTAssertTrue(
            contentView.bounds.contains(selectedFrame),
            "Expected selected folder capsule to be visible, got \(selectedFrame)"
        )
    }

    @MainActor
    func testMinimumContentSizeTracksGridAndChromeRows() {
        let metrics = GridMetrics(iconSize: .large)
        let actual = PortalViewController.minimumContentSize(for: .large)
        let expected = NSSize(
            width: metrics.minimumPortalSize.width,
            height: metrics.minimumPortalSize.height + PortalViewController.chromeHeight
        )

        XCTAssertEqual(actual, expected)
    }

    @MainActor
    func testContentSizeSnapsToGridIncrementsAndMinimum() {
        let metrics = GridMetrics(iconSize: .medium)
        let minimum = PortalViewController.minimumContentSize(for: .medium)

        XCTAssertEqual(
            PortalViewController.snappedContentSize(
                NSSize(width: minimum.width - 20, height: minimum.height - 20),
                for: .medium
            ),
            minimum
        )
        XCTAssertEqual(
            PortalViewController.snappedContentSize(
                NSSize(
                    width: minimum.width + metrics.itemSize.width + metrics.horizontalSpacing + 3,
                    height: minimum.height + metrics.itemSize.height + metrics.verticalSpacing + 3
                ),
                for: .medium
            ),
            NSSize(
                width: minimum.width + metrics.itemSize.width + metrics.horizontalSpacing,
                height: minimum.height + metrics.itemSize.height + metrics.verticalSpacing
            )
        )
    }

    @MainActor
    func waitUntilPresentation(
        _ controller: PortalViewController,
        equals expected: PortalPresentationState
    ) async throws {
        for _ in 0..<150 {
            if controller.presentationState == expected { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(expected); got \(controller.presentationState)")
    }
}

@MainActor
func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
}

@MainActor
func withObservedPortalDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("alcove-portal-observation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    do {
        try await body(directory)
    } catch {
        let bodyError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw PortalViewObservationTestError.bodyAndCleanup(
                body: String(describing: bodyError),
                cleanup: String(describing: error)
            )
        }
        throw bodyError
    }
    try FileManager.default.removeItem(at: directory)
}

enum PortalViewObservationTestError: Error {
    case bodyAndCleanup(body: String, cleanup: String)
}

@MainActor
final class FolderPathOpenerSpy: FolderPathOpening {
    private(set) var finderURLs: [URL] = []
    private(set) var terminalURLs: [URL] = []

    func openInFinder(_ url: URL) -> Bool {
        finderURLs.append(url)
        return true
    }

    func openInTerminal(
        _ url: URL,
        completion: @escaping @MainActor @Sendable (FolderPathOpenError?) -> Void
    ) {
        terminalURLs.append(url)
        completion(nil)
    }
}

@MainActor
final class FolderPathFailurePresenterSpy: FolderPathOpenFailurePresenting {
    private(set) var failures: [(FolderPathOpenError, URL)] = []

    func present(_ error: FolderPathOpenError, for url: URL) {
        failures.append((error, url))
    }
}

let testDisplay = DisplayDescriptor(
    identity: DisplayIdentity(rawValue: "test-display"),
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
)

struct FixedFolderEnumerator: FolderEnumerating {
    let root: URL
    let items: [FileItem]

    func enumerate(
        root: URL,
        showHidden: Bool,
        sortOrder: PortalSortOrder,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        return FolderEnumerationResult(
            root: self.root,
            generation: generation,
            items: items,
            itemDiagnostics: []
        )
    }
}

struct FailingFolderEnumerator: FolderEnumerating {
    let error: FolderAccessError

    func enumerate(
        root: URL,
        showHidden: Bool,
        sortOrder: PortalSortOrder,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        throw error
    }
}

struct DelayedFixedFolderEnumerator: FolderEnumerating {
    let root: URL
    let items: [FileItem]

    func enumerate(
        root: URL,
        showHidden: Bool,
        sortOrder: PortalSortOrder,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        try await Task.sleep(for: .milliseconds(50))
        return FolderEnumerationResult(
            root: self.root,
            generation: generation,
            items: items,
            itemDiagnostics: []
        )
    }
}

struct FolderMapEnumerator: FolderEnumerating {
    let itemsByRoot: [URL: [FileItem]]

    func enumerate(
        root: URL,
        showHidden: Bool,
        sortOrder: PortalSortOrder,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        FolderEnumerationResult(
            root: root,
            generation: generation,
            items: itemsByRoot[root] ?? [],
            itemDiagnostics: []
        )
    }
}
actor MutableFolderEnumerator: FolderEnumerating {
    private var itemsByRoot: [URL: [FileItem]]
    private var sortOrders: [PortalSortOrder] = []

    init(itemsByRoot: [URL: [FileItem]]) {
        self.itemsByRoot = itemsByRoot
    }

    func setItems(_ items: [FileItem], for root: URL) {
        itemsByRoot[root] = items
    }

    func requestedSortOrders() -> [PortalSortOrder] {
        sortOrders
    }

    func enumerate(
        root: URL,
        showHidden: Bool,
        sortOrder: PortalSortOrder,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        sortOrders.append(sortOrder)
        return FolderEnumerationResult(
            root: root,
            generation: generation,
            items: itemsByRoot[root] ?? [],
            itemDiagnostics: []
        )
    }
}
