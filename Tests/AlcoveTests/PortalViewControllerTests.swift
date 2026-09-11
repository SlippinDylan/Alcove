import AlcoveCore
import XCTest
@testable import Alcove

final class PortalViewControllerTests: XCTestCase {
    @MainActor
    func testReloadAppliesAcceptedFolderContents() async throws {
        let root = URL(fileURLWithPath: "/tmp/portal")
        let item = FileItem(
            url: root.appendingPathComponent("file.txt"),
            name: "file.txt",
            isDirectory: false,
            isHidden: false
        )
        let coordinator = FolderLoadingCoordinator(
            enumerator: FixedFolderEnumerator(root: root, items: [item])
        )
        let portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: coordinator
        )
        controller.loadView()

        await controller.reload()

        XCTAssertEqual(controller.presentationState, .items(1))
    }

    @MainActor
    func testReloadShowsEmptyState() async throws {
        let root = URL(fileURLWithPath: "/tmp/empty-portal")
        let coordinator = FolderLoadingCoordinator(
            enumerator: FixedFolderEnumerator(root: root, items: [])
        )
        let portal = try Portal(
            folderURL: root,
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            display: testDisplay
        )
        let controller = PortalViewController(
            portal: portal,
            loadingCoordinator: coordinator
        )
        controller.loadView()

        await controller.reload()

        XCTAssertEqual(controller.presentationState, .message("This folder is empty"))
    }

    @MainActor
    func testRealFolderChangeRefreshesVisiblePortalGrid() async throws {
        try await withObservedPortalDirectory { root in
            let portal = try Portal(
                folderURL: root,
                frame: CGRect(x: 0, y: 0, width: 320, height: 240),
                display: testDisplay
            )
            let controller = PortalViewController(
                portal: portal,
                loadingCoordinator: FolderLoadingCoordinator()
            )
            controller.loadView()
            controller.viewDidAppear()
            defer { controller.stopObservation() }
            try await waitUntilPresentation(
                controller,
                equals: .message("This folder is empty")
            )

            try Data("visible".utf8).write(to: root.appendingPathComponent("visible.txt"))
            try await waitUntilPresentation(controller, equals: .items(1))
        }
    }

    @MainActor
    private func waitUntilPresentation(
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
private func withObservedPortalDirectory(
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

private enum PortalViewObservationTestError: Error {
    case bodyAndCleanup(body: String, cleanup: String)
}

private let testDisplay = DisplayDescriptor(
    identity: DisplayIdentity(rawValue: "test-display"),
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
)

private struct FixedFolderEnumerator: FolderEnumerating {
    let root: URL
    let items: [FileItem]

    func enumerate(
        root: URL,
        showHidden: Bool,
        generation: UInt64
    ) async throws -> FolderEnumerationResult {
        FolderEnumerationResult(
            root: self.root,
            generation: generation,
            items: items,
            itemDiagnostics: []
        )
    }
}
