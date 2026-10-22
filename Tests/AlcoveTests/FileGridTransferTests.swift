import AlcoveCore
import AppKit
import Carbon
import XCTest
@testable import Alcove

extension FileGridViewControllerTests {
    func testTransferPlanRejectsSameDestinationAndNameConflicts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = destination.appendingPathComponent("existing.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: existing.path, contents: Data()))

        XCTAssertThrowsError(try FileTransferPlan.make(
            sourceURLs: [existing],
            destinationDirectoryURL: destination
        )) { error in
            XCTAssertEqual(error as? FileOperationError, .sourceAlreadyInDestination(existing))
        }

        let conflictingSource = source.appendingPathComponent("existing.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: conflictingSource.path, contents: Data()))
        XCTAssertThrowsError(try FileTransferPlan.make(
            sourceURLs: [conflictingSource],
            destinationDirectoryURL: destination
        )) { error in
            XCTAssertEqual(error as? FileOperationError, .destinationAlreadyExists(existing))
        }
    }

    func testTransferPlanUsesTheDestinationVolumesNameComparisonRules() {
        XCTAssertNotEqual(
            FileTransferPlan.destinationNameKey("Report.txt", caseSensitive: true),
            FileTransferPlan.destinationNameKey("report.txt", caseSensitive: true)
        )
        XCTAssertEqual(
            FileTransferPlan.destinationNameKey("Report.txt", caseSensitive: false),
            FileTransferPlan.destinationNameKey("report.txt", caseSensitive: false)
        )
        XCTAssertEqual(
            FileTransferPlan.destinationNameKey("Café.txt", caseSensitive: true),
            FileTransferPlan.destinationNameKey("Cafe\u{301}.txt", caseSensitive: true)
        )
    }

    @MainActor
    func testTransferIntentRespectsSourceCapabilitiesAndModifiers() {
        XCTAssertEqual(FileGridViewController.requestedTransferOperation(
            sourceMask: [.copy, .move], modifiers: []
        ), .automatic)
        XCTAssertEqual(FileGridViewController.requestedTransferOperation(
            sourceMask: [.copy, .move], modifiers: .command
        ), .move)
        XCTAssertEqual(FileGridViewController.requestedTransferOperation(
            sourceMask: [.copy, .move], modifiers: .option
        ), .copy)
        XCTAssertEqual(FileGridViewController.requestedTransferOperation(
            sourceMask: .copy, modifiers: .command
        ), .copy)
        XCTAssertEqual(FileGridViewController.requestedTransferOperation(
            sourceMask: .move, modifiers: .option
        ), .move)
        XCTAssertNil(FileGridViewController.requestedTransferOperation(
            sourceMask: [.copy, .move], modifiers: [.command, .option]
        ))
        for unsupported: NSDragOperation in [[], .link, .generic] {
            XCTAssertNil(FileGridViewController.requestedTransferOperation(
                sourceMask: unsupported, modifiers: []
            ))
        }
    }

    func testDefaultTransferOperationCopiesTheWholeBatchIfAnySourceIsOnAnotherVolume() {
        let destinationVolume = URL(fileURLWithPath: "/Volumes/Destination")
        XCTAssertEqual(FileTransferOperation.defaultOperation(
            sourceVolumeURLs: [destinationVolume, destinationVolume],
            destinationVolumeURL: destinationVolume
        ), .move)
        XCTAssertEqual(FileTransferOperation.defaultOperation(
            sourceVolumeURLs: [URL(fileURLWithPath: "/Volumes/Source")],
            destinationVolumeURL: destinationVolume
        ), .copy)
        XCTAssertEqual(FileTransferOperation.defaultOperation(
            sourceVolumeURLs: [destinationVolume, URL(fileURLWithPath: "/Volumes/Source")],
            destinationVolumeURL: destinationVolume
        ), .copy)
    }

    func testTransferPlanRejectsDirectoryIntoItsDescendant() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let descendant = source.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: descendant, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try FileTransferPlan.make(
            sourceURLs: [source],
            destinationDirectoryURL: descendant
        )) { error in
            XCTAssertEqual(error as? FileOperationError, .directoryIntoDescendant(source))
        }
        XCTAssertThrowsError(try FileTransferPlan.make(
            sourceURLs: [source],
            destinationDirectoryURL: source
        )) { error in
            XCTAssertEqual(error as? FileOperationError, .directoryIntoDescendant(source))
        }
    }

    @MainActor
    func testFolderTilesTargetSubfoldersAndOtherExternalDropsTargetCurrentDirectory() {
        let currentURL = URL(fileURLWithPath: "/tmp/current", isDirectory: true)
        let folder = FileItem(
            url: currentURL.appendingPathComponent("Folder", isDirectory: true),
            name: "Folder",
            isDirectory: true,
            isHidden: false
        )
        let file = FileItem(
            url: currentURL.appendingPathComponent("File.txt"),
            name: "File.txt",
            isDirectory: false,
            isHidden: false
        )
        let package = FileItem(
            url: currentURL.appendingPathComponent("App.app", isDirectory: true),
            name: "App.app",
            isDirectory: true,
            isPackage: true,
            isHidden: false
        )
        let symlink = FileItem(
            url: currentURL.appendingPathComponent("Link", isDirectory: true),
            name: "Link",
            isDirectory: true,
            isSymbolicLink: true,
            isHidden: false
        )
        let controller = FileGridViewController()
        controller.loadView()
        controller.setItems([folder, file, package, symlink])
        controller.updateDropDestination(currentURL)

        XCTAssertEqual(controller.destinationURL(forDropAt: 0, isLocal: false), folder.url)
        XCTAssertEqual(controller.destinationURL(forDropAt: 0, isLocal: true), folder.url)
        XCTAssertEqual(controller.destinationURL(forDropAt: 1, isLocal: false), currentURL)
        XCTAssertEqual(controller.destinationURL(forDropAt: 2, isLocal: false), currentURL)
        XCTAssertEqual(controller.destinationURL(forDropAt: 3, isLocal: false), currentURL)
        XCTAssertEqual(controller.destinationURL(forDropAt: nil, isLocal: false), currentURL)
        XCTAssertNil(controller.destinationURL(forDropAt: nil, isLocal: true))
        for index in 1...3 {
            XCTAssertNil(controller.destinationURL(forDropAt: index, isLocal: true))
        }
    }

    @MainActor
    func testNativeExternalDropsAcceptEmptyFullAndScrolledGrids() async throws {
        let currentURL = URL(fileURLWithPath: "/tmp/current", isDirectory: true)
        let sourceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sources = [
            sourceRoot.appendingPathComponent("file.txt"),
            sourceRoot.appendingPathComponent("folder", isDirectory: true),
        ]
        try FileManager.default.createDirectory(at: sources[1], withIntermediateDirectories: true)
        try Data("drop".utf8).write(to: sources[0])
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let metrics = GridMetrics(iconSize: .medium)
        for count in [0, 3, 30] {
            let transfer = GridDropTransferSpy()
            let failurePresenter = FileOperationFailurePresenterSpy()
            let controller = FileGridViewController(
                fileTransferService: transfer,
                fileOperationFailurePresenter: failurePresenter
            )
            controller.loadView()
            controller.setItems(makeItems(count: count))
            controller.updateDropDestination(currentURL)
            let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
            let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: metrics.minimumContainerSize),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = scrollView
            defer { window.close() }
            scrollView.layoutSubtreeIfNeeded()
            collectionView.layoutSubtreeIfNeeded()
            if count == 30 {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: metrics.itemSize.height * 2))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            let visibleRect = collectionView.visibleRect
            let points = [
                NSPoint(x: visibleRect.minX + 2, y: visibleRect.minY + 2),
                NSPoint(x: metrics.contentInsets.leading + metrics.itemSize.width / 2,
                        y: visibleRect.minY + metrics.contentInsets.top + 12),
                NSPoint(x: metrics.contentInsets.leading + metrics.itemSize.width / 2,
                        y: visibleRect.maxY - metrics.contentInsets.bottom - 4),
                NSPoint(x: metrics.contentInsets.leading + metrics.itemSize.width + 2,
                        y: visibleRect.midY),
                NSPoint(x: visibleRect.maxX - 2, y: visibleRect.maxY - 2),
            ]
            let completed = expectation(description: "All native drops reload the current directory")
            completed.expectedFulfillmentCount = points.count
            controller.onFileOperationCompleted = { completed.fulfill() }
            let draggingInfo = GridDropInfo(window: window, urls: sources)
            defer { draggingInfo.draggingPasteboard.releaseGlobally() }
            for point in points {
                scrollView.contentView.scroll(to: visibleRect.origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                draggingInfo.draggingLocation = collectionView.convert(point, to: nil)
                let operation = collectionView.draggingEntered(draggingInfo)
                XCTAssertFalse(operation.isEmpty, "Rejected drop with \(count) items at \(point)")
                XCTAssertFalse(collectionView.draggingUpdated(draggingInfo).isEmpty)
                XCTAssertTrue(collectionView.prepareForDragOperation(draggingInfo))
                XCTAssertTrue(collectionView.performDragOperation(draggingInfo))
                collectionView.draggingExited(draggingInfo)
            }
            await fulfillment(of: [completed], timeout: 2)
            XCTAssertEqual(transfer.destinations, Array(repeating: currentURL, count: points.count))
            XCTAssertEqual(transfer.sources, Array(repeating: sources, count: points.count))
            XCTAssertTrue(failurePresenter.errors.isEmpty)

            draggingInfo.draggingSource = collectionView
            XCTAssertTrue(collectionView.draggingEntered(draggingInfo).isEmpty)
            collectionView.draggingExited(draggingInfo)
            draggingInfo.draggingSource = nil
            controller.updateDropDestination(nil)
            XCTAssertTrue(collectionView.draggingEntered(draggingInfo).isEmpty)
            collectionView.draggingExited(draggingInfo)
            controller.updateDropDestination(currentURL)
            draggingInfo.draggingPasteboard.clearContents()
            draggingInfo.draggingPasteboard.setString("not a file URL", forType: .string)
            XCTAssertTrue(collectionView.draggingEntered(draggingInfo).isEmpty)
            collectionView.draggingExited(draggingInfo)
        }
    }

    @MainActor
    func testContinuousNativeDragRetargetsBetweenBackgroundFilesAndFolders() async throws {
        let currentURL = URL(fileURLWithPath: "/tmp/current", isDirectory: true)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("drop".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        for scrolled in [false, true] {
            let transfer = GridDropTransferSpy()
            let controller = FileGridViewController(fileTransferService: transfer)
            controller.loadView()
            let folderIndex = scrolled ? 18 : 0
            var items = makeItems(count: scrolled ? 30 : 3)
            let folderURL = currentURL.appendingPathComponent("Folder", isDirectory: true)
            items[folderIndex] = FileItem(
                url: folderURL, name: "Folder", isDirectory: true, isHidden: false
            )
            controller.setItems(items)
            controller.updateDropDestination(currentURL)
            let scroll = try XCTUnwrap(controller.view as? NSScrollView)
            let collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            defer { window.close() }
            scroll.layoutSubtreeIfNeeded()
            collection.layoutSubtreeIfNeeded()
            let layout = try XCTUnwrap(collection.collectionViewLayout)
            let folderFrame = try XCTUnwrap(layout.layoutAttributesForItem(
                at: IndexPath(item: folderIndex, section: 0)
            )).frame
            let fileFrame = try XCTUnwrap(layout.layoutAttributesForItem(
                at: IndexPath(item: folderIndex + 1, section: 0)
            )).frame
            if scrolled {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: folderFrame.minY - 8))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            let folder = NSPoint(x: folderFrame.midX, y: folderFrame.midY)
            let file = NSPoint(x: fileFrame.midX, y: fileFrame.midY)
            let blank = NSPoint(x: 2, y: folder.y)
            let paths = [[blank, folder], [folder, file, folder], [blank, folder, file], [folder, blank]]
            let completed = expectation(description: "Continuous drops finish")
            completed.expectedFulfillmentCount = paths.count
            controller.onFileOperationCompleted = { completed.fulfill() }
            let info = GridDropInfo(window: window, urls: [sourceURL])
            defer { info.draggingPasteboard.releaseGlobally() }
            for path in paths {
                for (index, point) in path.enumerated() {
                    info.draggingLocation = collection.convert(point, to: nil)
                    let operation = index == 0
                        ? collection.draggingEntered(info) : collection.draggingUpdated(info)
                    XCTAssertEqual(operation, .copy)
                }
                XCTAssertTrue(collection.prepareForDragOperation(info))
                XCTAssertTrue(collection.performDragOperation(info))
                collection.draggingExited(info)
            }
            await fulfillment(of: [completed], timeout: 2)
            XCTAssertEqual(transfer.destinations, [folderURL, folderURL, currentURL, currentURL])
        }
    }

    @MainActor
    func testStationaryNativeDropWaitsForPreparationAndExecutesTheOfferedOperation() async throws {
        for operation: FileTransferOperation in [.copy, .move] {
            let fixture = try GridDropFixture()
            defer { fixture.close() }
            let gate = GridDropOperationGate()
            fixture.transfer.defaultOperationHandler = { _, destination in
                try await gate.operation(for: destination)
            }
            fixture.info.draggingSourceOperationMask = [.copy, .move]
            let requested = expectation(description: "Volume preparation starts")
            gate.onRequest = { requested.fulfill() }
            XCTAssertTrue(fixture.collection.draggingEntered(fixture.info).isEmpty)
            XCTAssertFalse(fixture.collection.prepareForDragOperation(fixture.info))
            await fulfillment(of: [requested], timeout: 2)
            XCTAssertFalse(fixture.collection.performDragOperation(fixture.info))
            // A rejected perform ends this session; begin a fresh one and resolve only its result.
            gate.complete(0, with: .success(operation))
            let requestedAgain = expectation(description: "Fresh preparation starts")
            gate.onRequest = { requestedAgain.fulfill() }
            XCTAssertTrue(fixture.collection.draggingEntered(fixture.info).isEmpty)
            await fulfillment(of: [requestedAgain], timeout: 2)
            gate.complete(1, with: .success(operation))
            let nativeOperation: NSDragOperation = operation == .copy ? .copy : .move
            await fixture.waitForOperation(nativeOperation)
            let completed = expectation(description: "The offered transfer completes")
            fixture.controller.onFileOperationCompleted = { completed.fulfill() }
            XCTAssertTrue(fixture.collection.prepareForDragOperation(fixture.info))
            XCTAssertTrue(fixture.collection.performDragOperation(fixture.info))
            XCTAssertFalse(fixture.collection.performDragOperation(fixture.info))
            await fulfillment(of: [completed], timeout: 2)
            XCTAssertEqual(fixture.transfer.operations, [operation])
            XCTAssertEqual(fixture.transfer.destinations, [fixture.currentURL])
        }
    }

    @MainActor
    func testNativeDropDiscardsOldTargetPreparationAndReportsPreparationFailure() async throws {
        let fixture = try GridDropFixture()
        defer { fixture.close() }
        let gate = GridDropOperationGate()
        fixture.transfer.defaultOperationHandler = { _, destination in
            try await gate.operation(for: destination)
        }
        fixture.info.draggingSourceOperationMask = [.copy, .move]
        let initialRequest = expectation(description: "Background operation requested")
        gate.onRequest = { initialRequest.fulfill() }
        XCTAssertTrue(fixture.collection.draggingEntered(fixture.info).isEmpty)
        await fulfillment(of: [initialRequest], timeout: 2)
        let folderRequest = expectation(description: "Folder operation requested")
        gate.onRequest = { folderRequest.fulfill() }
        fixture.pointAtFolder()
        XCTAssertTrue(fixture.collection.draggingUpdated(fixture.info).isEmpty)
        await fulfillment(of: [folderRequest], timeout: 2)
        gate.complete(0, with: .success(.copy))
        await Task.yield()
        XCTAssertTrue(fixture.collection.draggingUpdated(fixture.info).isEmpty)
        gate.complete(1, with: .success(.move))
        await fixture.waitForOperation(.move)
        let folderItem = try XCTUnwrap(fixture.collection.item(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(folderItem.highlightState, .asDropTarget)
        XCTAssertTrue(fixture.controller.selectionState.selectedIDs.isEmpty)
        fixture.collection.draggingExited(fixture.info)
        XCTAssertEqual(folderItem.highlightState, .none)

        let failedRequest = expectation(description: "New session prepares again")
        let preparationFinished = expectation(description: "Failing preparation returns")
        fixture.transfer.defaultOperationHandler = { _, destination in
            defer { preparationFinished.fulfill() }
            return try await gate.operation(for: destination)
        }
        gate.onRequest = { failedRequest.fulfill() }
        XCTAssertTrue(fixture.collection.draggingEntered(fixture.info).isEmpty)
        await fulfillment(of: [failedRequest], timeout: 2)
        let error = FileOperationError.volumeUnavailable(fixture.currentURL)
        gate.complete(2, with: .failure(error))
        let reported = expectation(description: "Preparation error is presented after drag ends")
        fixture.failurePresenter.onPresent = { reported.fulfill() }
        await fulfillment(of: [preparationFinished], timeout: 2)
        XCTAssertTrue(fixture.collection.draggingUpdated(fixture.info).isEmpty)
        fixture.collection.draggingEnded(fixture.info)
        await fulfillment(of: [reported], timeout: 2)
        XCTAssertEqual(fixture.failurePresenter.errors.first as? FileOperationError, error)
        XCTAssertTrue(fixture.transfer.operations.isEmpty)
    }

    @MainActor
    func testNativeDropRejectsChangesAfterPreparation() throws {
        for change in ["target", "sources", "mask", "session", "directory", "reload"] {
            let fixture = try GridDropFixture()
            defer { fixture.close() }
            XCTAssertEqual(fixture.collection.draggingEntered(fixture.info), .copy)
            XCTAssertTrue(fixture.collection.prepareForDragOperation(fixture.info))
            switch change {
            case "target": fixture.pointAtFolder()
            case "sources":
                fixture.info.draggingPasteboard.clearContents()
                fixture.info.draggingPasteboard.writeObjects([
                    fixture.sourceURL.appendingPathExtension("changed") as NSURL,
                ])
            case "mask": fixture.info.draggingSourceOperationMask = .move
            case "session": fixture.info.draggingSequenceNumber += 1
            case "directory": fixture.controller.updateDropDestination(nil)
            case "reload": fixture.controller.setItems([])
            default: XCTFail("Unknown fixture change")
            }
            XCTAssertFalse(fixture.collection.performDragOperation(fixture.info), change)
            XCTAssertTrue(fixture.transfer.operations.isEmpty, change)
        }
    }

    @MainActor
    func testNativeDropAutoscrollsAtTheViewportEdge() throws {
        let fixture = try GridDropFixture()
        defer { fixture.close() }
        fixture.controller.setItems(makeItems(count: 60))
        fixture.collection.layoutSubtreeIfNeeded()
        let initial = fixture.collection.visibleRect
        fixture.info.draggingLocation = fixture.collection.convert(
            NSPoint(x: 2, y: initial.maxY - 1), to: nil
        )
        XCTAssertEqual(fixture.collection.draggingEntered(fixture.info), .copy)
        for _ in 0..<5 {
            XCTAssertEqual(fixture.collection.draggingUpdated(fixture.info), .copy)
        }
        XCTAssertGreaterThan(fixture.collection.visibleRect.minY, initial.minY)
    }

    @MainActor
    func testNativeFolderDropTargetsFolderAndReportsTransferFailure() async throws {
        let currentURL = URL(fileURLWithPath: "/tmp/current", isDirectory: true)
        let folder = FileItem(
            url: currentURL.appendingPathComponent("Folder", isDirectory: true),
            name: "Folder", isDirectory: true, isHidden: false
        )
        let transfer = GridDropTransferSpy()
        transfer.error = .destinationAlreadyExists(folder.url.appendingPathComponent("file.txt"))
        let failurePresenter = FileOperationFailurePresenterSpy()
        let failed = expectation(description: "Native drop reports transfer failure")
        failurePresenter.onPresent = { failed.fulfill() }
        let controller = FileGridViewController(
            fileTransferService: transfer,
            fileOperationFailurePresenter: failurePresenter
        )
        controller.loadView()
        controller.setItems([folder])
        controller.updateDropDestination(currentURL)
        var didReload = false
        controller.onFileOperationCompleted = { didReload = true }
        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        let collectionView = try XCTUnwrap(scrollView.documentView as? NSCollectionView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        defer { window.close() }
        scrollView.layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()
        let attributes = try XCTUnwrap(collectionView.collectionViewLayout?.layoutAttributesForItem(
            at: IndexPath(item: 0, section: 0)
        ))
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("drop".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let draggingInfo = GridDropInfo(window: window, urls: [sourceURL])
        defer { draggingInfo.draggingPasteboard.releaseGlobally() }
        draggingInfo.draggingLocation = collectionView.convert(
            NSPoint(x: attributes.frame.midX, y: attributes.frame.midY), to: nil
        )
        XCTAssertFalse(collectionView.draggingEntered(draggingInfo).isEmpty)
        XCTAssertTrue(collectionView.prepareForDragOperation(draggingInfo))
        XCTAssertTrue(collectionView.performDragOperation(draggingInfo))
        collectionView.draggingExited(draggingInfo)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(transfer.destinations, [folder.url])
        XCTAssertEqual(failurePresenter.errors.first as? FileOperationError, transfer.error)
        XCTAssertFalse(didReload)
    }

    func testCoordinatedTransferCopiesAndMovesWithoutOverwriting() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let copyDestination = root.appendingPathComponent("copy", isDirectory: true)
        let moveDestination = root.appendingPathComponent("move", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: copyDestination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: moveDestination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = source.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: original)
        let service = CoordinatedFileTransferService()

        try await service.transfer(
            sourceURLs: [original],
            to: copyDestination,
            operation: .copy
        )
        let copied = copyDestination.appendingPathComponent("note.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try Data(contentsOf: copied), Data("hello".utf8))

        try await service.transfer(
            sourceURLs: [copied],
            to: moveDestination,
            operation: .move
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(
            try Data(contentsOf: moveDestination.appendingPathComponent("note.txt")),
            Data("hello".utf8)
        )

        let automaticSource = source.appendingPathComponent("automatic.txt")
        try Data("automatic".utf8).write(to: automaticSource)
        let automaticOperation = try await service.defaultOperation(
            sourceURLs: [automaticSource], to: moveDestination
        )
        XCTAssertEqual(automaticOperation, .move)
        try await service.transfer(
            sourceURLs: [automaticSource], to: moveDestination, operation: automaticOperation
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: automaticSource.path))
        XCTAssertEqual(
            try Data(contentsOf: moveDestination.appendingPathComponent("automatic.txt")),
            Data("automatic".utf8)
        )
    }

}

@MainActor
private final class GridDropFixture {
    let currentURL = URL(fileURLWithPath: "/tmp/current", isDirectory: true)
    let sourceURL: URL
    let transfer = GridDropTransferSpy()
    let failurePresenter = FileOperationFailurePresenterSpy()
    let controller: FileGridViewController
    let collection: NSCollectionView
    let window: NSWindow
    let info: GridDropInfo

    init() throws {
        sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("drop".utf8).write(to: sourceURL)
        controller = FileGridViewController(
            fileTransferService: transfer, fileOperationFailurePresenter: failurePresenter
        )
        controller.loadView()
        controller.setItems([FileItem(
            url: currentURL.appendingPathComponent("Folder", isDirectory: true),
            name: "Folder", isDirectory: true, isHidden: false
        )])
        controller.updateDropDestination(currentURL)
        let scroll = try XCTUnwrap(controller.view as? NSScrollView)
        collection = try XCTUnwrap(scroll.documentView as? NSCollectionView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        scroll.layoutSubtreeIfNeeded()
        collection.layoutSubtreeIfNeeded()
        info = GridDropInfo(window: window, urls: [sourceURL])
        info.draggingLocation = collection.convert(NSPoint(x: 2, y: 50), to: nil)
    }

    func pointAtFolder() {
        info.draggingLocation = collection.convert(NSPoint(x: 64, y: 50), to: nil)
    }

    func waitForOperation(_ expected: NSDragOperation, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if collection.draggingUpdated(info) == expected { return }
            await Task.yield()
        }
        XCTFail("The stationary drop never became ready", file: file, line: line)
    }

    func close() {
        collection.draggingEnded(info)
        info.draggingPasteboard.releaseGlobally()
        window.close()
        do { try FileManager.default.removeItem(at: sourceURL) }
        catch { XCTFail("Could not remove drop fixture: \(error)") }
    }
}

@MainActor
private final class GridDropOperationGate {
    private var continuations: [CheckedContinuation<FileTransferOperation, Error>] = []
    var onRequest: () -> Void = {}

    func operation(for destination: URL) async throws -> FileTransferOperation {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            onRequest()
        }
    }

    func complete(_ index: Int, with result: Result<FileTransferOperation, Error>) {
        continuations[index].resume(with: result)
    }
}

@MainActor
private final class GridDropTransferSpy: FileTransferPerforming {
    private(set) var sources: [[URL]] = []
    private(set) var destinations: [URL] = []
    var error: FileOperationError?
    private(set) var operations: [FileTransferOperation] = []
    var defaultOperationHandler: ([URL], URL) async throws -> FileTransferOperation = { _, _ in .move }

    func defaultOperation(sourceURLs: [URL], to destinationDirectoryURL: URL) async throws -> FileTransferOperation {
        try await defaultOperationHandler(sourceURLs, destinationDirectoryURL)
    }

    func transfer(sourceURLs: [URL], to destinationDirectoryURL: URL, operation: FileTransferOperation) async throws {
        operations.append(operation)
        sources.append(sourceURLs)
        destinations.append(destinationDirectoryURL)
        if let error { throw error }
    }
}

@MainActor
private final class GridDropInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(window: NSWindow, urls: [URL]) {
        draggingDestinationWindow = window
        super.init()
        draggingPasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options: NSDraggingItemEnumerationOptions,
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
