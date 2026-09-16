import AlcoveCore
import AppKit
import Carbon
import XCTest
@testable import Alcove

extension FileGridViewControllerTests {
    func testRenamePlanRejectsInvalidAndConflictingNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let conflict = root.appendingPathComponent("conflict.txt")
        let hardLink = root.appendingPathComponent("hard-link.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: conflict.path, contents: Data()))
        try FileManager.default.linkItem(at: source, to: hardLink)

        for invalidName in ["", "   ", ".", "..", "folder/name", "bad\0name"] {
            XCTAssertThrowsError(try FileRenamePlan.make(
                sourceURL: source,
                newName: invalidName
            )) { error in
                XCTAssertEqual(error as? FileOperationError, .invalidName)
            }
        }
        XCTAssertThrowsError(try FileRenamePlan.make(
            sourceURL: source,
            newName: conflict.lastPathComponent
        )) { error in
            XCTAssertEqual(
                error as? FileOperationError,
                .destinationAlreadyExists(conflict)
            )
        }
        XCTAssertThrowsError(try FileRenamePlan.make(
            sourceURL: source,
            newName: hardLink.lastPathComponent
        )) { error in
            XCTAssertEqual(
                error as? FileOperationError,
                .destinationAlreadyExists(hardLink)
            )
        }
    }

    func testCoordinatedRenameSupportsCaseOnlyNamesWithoutOverwriting() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("report.txt")
        try Data("contents".utf8).write(to: original)
        let service = CoordinatedFileRenamingService()

        let renamed = try await service.rename(original, to: "Report.txt")

        XCTAssertEqual(renamed.lastPathComponent, "Report.txt")
        XCTAssertEqual(try Data(contentsOf: renamed), Data("contents".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Report.txt"])
    }

    @MainActor
    func testRenameCompletionMigratesPathBasedSelectionBeforeReload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("draft.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: original.path, contents: Data()))
        let item = FileItem(
            url: original,
            name: original.lastPathComponent,
            isDirectory: false,
            isHidden: false
        )
        let controller = FileGridViewController()
        controller.loadView()
        controller.setItems([item])
        controller.handleClick(index: 0, modifiers: [])
        let completed = expectation(description: "Rename reload requested")
        var selectedURLs: [[URL]] = []
        controller.onSelectionChanged = { selectedURLs.append($0) }
        controller.onFileOperationCompleted = { completed.fulfill() }

        controller.commitRename(item, to: "final.txt")
        await fulfillment(of: [completed], timeout: 2)

        let renamed = root.appendingPathComponent("final.txt")
        XCTAssertEqual(controller.selectionState.selectedIDs, [FileIdentity(url: renamed)])
        XCTAssertEqual(selectedURLs.last, [renamed])
    }

    @MainActor
    func testRenameSelectionRangePreservesFileExtensions() {
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/Archive.tar.gz"),
            name: "Archive.tar.gz",
            isDirectory: false,
            isHidden: false
        )
        let folder = FileItem(
            url: URL(fileURLWithPath: "/tmp/Folder"),
            name: "Folder",
            isDirectory: true,
            isHidden: false
        )
        let hidden = FileItem(
            url: URL(fileURLWithPath: "/tmp/.gitignore"),
            name: ".gitignore",
            isDirectory: false,
            isHidden: true
        )

        XCTAssertEqual(FileGridViewController.renameSelectionRange(for: file), NSRange(location: 0, length: 11))
        XCTAssertEqual(FileGridViewController.renameSelectionRange(for: folder), NSRange(location: 0, length: 6))
        XCTAssertEqual(FileGridViewController.renameSelectionRange(for: hidden), NSRange(location: 0, length: 10))
    }

    @MainActor
    func testInlineRenameCommitsReturnAndCancelsEscape() {
        let cell = FileItemCell()
        cell.loadView()
        let item = makeItems(count: 1)[0]
        cell.configure(
            with: item,
            metrics: GridMetrics(iconSize: .medium),
            position: 1,
            itemCount: 1,
            onOpen: { true }
        )
        var committedNames: [String] = []
        cell.beginRenaming(selecting: NSRange(location: 0, length: 4)) {
            committedNames.append($0)
        }
        cell.nameLabel.stringValue = "renamed"

        XCTAssertTrue(cell.control(
            cell.nameLabel,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertEqual(committedNames, ["renamed"])
        XCTAssertEqual(cell.nameLabel.stringValue, item.name)
        XCTAssertFalse(cell.nameLabel.isEditable)

        cell.beginRenaming(selecting: NSRange(location: 0, length: 4)) {
            committedNames.append($0)
        }
        cell.nameLabel.stringValue = "cancelled"
        XCTAssertTrue(cell.control(
            cell.nameLabel,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ))
        XCTAssertEqual(committedNames, ["renamed"])
        XCTAssertEqual(cell.nameLabel.stringValue, item.name)
    }

    @MainActor
    func testDuplicateContextActionReloadsAndSelectsReturnedURLs() throws {
        let duplicator = FileDuplicatorSpy()
        let controller = FileGridViewController(fileDuplicator: duplicator)
        controller.loadView()
        let items = makeItems(count: 3)
        controller.setItems(items)
        controller.handleClick(index: 2, modifiers: [])
        controller.handleClick(index: 0, modifiers: .command)
        let menu = try XCTUnwrap(controller.contextMenu(forItemAt: 2))
        let completed = expectation(description: "Duplicate reload requested")
        var selectedURLs: [[URL]] = []
        controller.onSelectionChanged = { selectedURLs.append($0) }
        controller.onFileOperationCompleted = { completed.fulfill() }

        performMenuItem(titled: localized("portal.files.duplicate"), in: menu)

        wait(for: [completed], timeout: 1)
        let duplicatedURLs = [items[0].url, items[2].url].map {
            $0.deletingPathExtension().appendingPathExtension("copy")
        }
        XCTAssertEqual(duplicator.requests, [[items[0].url, items[2].url]])
        XCTAssertEqual(selectedURLs.last, duplicatedURLs)
        XCTAssertEqual(
            controller.selectionState.selectedIDs,
            Set(duplicatedURLs.map(FileIdentity.init(url:)))
        )
    }

    @MainActor
    func testSystemDuplicatorUsesFinderDuplicateAndReturnsSourceOrder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let completed = expectation(description: "Finder duplicate completed")
        var output: [URL] = []
        var outputError: Error?

        SystemFileDuplicator().duplicate([second, first]) { urls, error in
            output = urls
            outputError = error
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)

        XCTAssertNil(outputError)
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(try Data(contentsOf: output[0]), Data("second".utf8))
        XCTAssertEqual(try Data(contentsOf: output[1]), Data("first".utf8))
    }

    @MainActor
    func testGetInfoContextActionRequiresOneItemAndRoutesItsURL() async throws {
        let opener = FinderInfoOpenerSpy()
        let opened = expectation(description: "Finder info opened")
        opener.onOpen = { opened.fulfill() }
        let controller = FileGridViewController(finderInfoOpener: opener)
        controller.loadView()
        let items = makeItems(count: 2)
        controller.setItems(items)
        controller.handleClick(index: 1, modifiers: [])
        let menu = try XCTUnwrap(controller.contextMenu(forItemAt: 1))
        let getInfo = try XCTUnwrap(menu.item(withTitle: localized("portal.files.get_info")))

        XCTAssertTrue(controller.validateMenuItem(getInfo))
        performMenuItem(titled: localized("portal.files.get_info"), in: menu)
        await fulfillment(of: [opened], timeout: 2)
        XCTAssertEqual(opener.openedURLs, [items[1].url])

        controller.handleClick(index: 0, modifiers: .command)
        XCTAssertFalse(controller.validateMenuItem(getInfo))
    }

    @MainActor
    func testGetInfoContextActionReportsFinderAutomationFailure() async throws {
        let opener = FinderInfoOpenerSpy(error: .automationDenied)
        let failurePresenter = FileOperationFailurePresenterSpy()
        let presented = expectation(description: "Finder automation failure presented")
        failurePresenter.onPresent = { presented.fulfill() }
        let controller = FileGridViewController(
            fileOperationFailurePresenter: failurePresenter,
            finderInfoOpener: opener
        )
        controller.loadView()
        controller.setItems(makeItems(count: 1))
        let menu = try XCTUnwrap(controller.contextMenu(forItemAt: 0))

        performMenuItem(titled: localized("portal.files.get_info"), in: menu)
        await fulfillment(of: [presented], timeout: 2)

        XCTAssertEqual(
            failurePresenter.errors.first as? FinderInfoError,
            .automationDenied
        )
    }

    @MainActor
    func testFinderInfoScriptCompilesAndPassesPathAsAnEventArgument() async throws {
        let didCompile = await Task.detached {
            guard let script = NSAppleScript(source: FinderInfoAppleEventOpener.scriptSource) else {
                return false
            }
            var compilationError: NSDictionary?
            return script.compileAndReturnError(&compilationError) && compilationError == nil
        }.value
        XCTAssertTrue(didCompile)

        let path = "/tmp/quote-'-and-\"-characters"
        let event = FinderInfoAppleEventOpener.subroutineEvent(path: path)
        XCTAssertEqual(
            event.paramDescriptor(forKeyword: AEKeyword(keyASSubroutineName))?.stringValue,
            "showInfo"
        )
        let arguments = try XCTUnwrap(
            event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
        )
        XCTAssertEqual(arguments.atIndex(1)?.stringValue, path)
        XCTAssertFalse(FinderInfoAppleEventOpener.scriptSource.contains(path))
        XCTAssertEqual(
            FinderInfoAppleEventOpener.error(from: [
                NSAppleScript.errorNumber: Int(errAEEventNotPermitted),
            ]),
            .automationDenied
        )
        do {
            try await FinderInfoAppleEventOpener().openInfo(
                for: URL(fileURLWithPath: "/tmp/Alcove-missing-\(UUID().uuidString)")
            )
            XCTFail("Expected a missing item error")
        } catch {
            XCTAssertEqual(error as? FinderInfoError, .itemUnavailable)
        }
    }

    func testCompressionPlanUsesFinderNamesWithoutOverwriting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: first.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: second.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(
            atPath: root.appendingPathComponent("first.txt.zip").path,
            contents: Data()
        ))
        XCTAssertTrue(FileManager.default.createFile(
            atPath: root.appendingPathComponent("first.txt 2.zip").path,
            contents: Data()
        ))
        XCTAssertTrue(FileManager.default.createFile(
            atPath: root.appendingPathComponent("Archive.zip").path,
            contents: Data()
        ))

        let single = try FileCompressionPlan.make(
            sourceURLs: [first],
            archiveBaseName: "Archive"
        )
        let multiple = try FileCompressionPlan.make(
            sourceURLs: [first, second],
            archiveBaseName: "Archive"
        )

        XCTAssertEqual(single.destinationURL.lastPathComponent, "first.txt 3.zip")
        XCTAssertEqual(multiple.destinationURL.lastPathComponent, "Archive 2.zip")
    }

    func testCompressionPlanRejectsSourcesFromDifferentFolders() throws {
        let firstRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secondRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let first = firstRoot.appendingPathComponent("first")
        let second = secondRoot.appendingPathComponent("second")
        XCTAssertTrue(FileManager.default.createFile(atPath: first.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: second.path, contents: Data()))

        XCTAssertThrowsError(try FileCompressionPlan.make(
            sourceURLs: [first, second],
            archiveBaseName: "Archive"
        )) { error in
            XCTAssertEqual(error as? FileOperationError, .compressionSourcesNotColocated)
        }
    }

    func testDittoCompressionCreatesFinderCompatibleSingleAndMultiItemZIPs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let nested = folder.appendingPathComponent("nested.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        try Data("nested".utf8).write(to: nested)
        let service = DittoFileCompressionService()

        let singleArchive = try await service.compress([folder])
        let multiArchive = try await service.compress([first, second, folder])

        XCTAssertEqual(
            try zipPayloadEntries(at: singleArchive),
            ["Folder/nested.txt"]
        )
        XCTAssertEqual(
            try zipPayloadEntries(at: multiArchive),
            ["Folder/nested.txt", "first.txt", "second.txt"]
        )
    }

    func testCompressionCancellationTerminatesTheActiveProcess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data()))
        let service = DittoFileCompressionService(
            executableURL: URL(fileURLWithPath: "/usr/bin/yes")
        )
        let task = Task {
            try await service.compress([source])
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled compression unexpectedly completed")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("source.txt.zip").path
            ))
        }
    }

    @MainActor
    func testCompressContextActionReloadsAndSelectsTheArchive() throws {
        let compressor = FileCompressorSpy()
        let controller = FileGridViewController(fileCompressor: compressor)
        controller.loadView()
        let items = makeItems(count: 2)
        controller.setItems(items)
        controller.handleKeyCommand(.selectAll)
        let menu = try XCTUnwrap(controller.contextMenu(forItemAt: 0))
        let completed = expectation(description: "Compression reload requested")
        var selectedURLs: [[URL]] = []
        controller.onSelectionChanged = { selectedURLs.append($0) }
        controller.onFileOperationCompleted = { completed.fulfill() }

        performMenuItem(titled: localized("portal.files.compress"), in: menu)
        wait(for: [completed], timeout: 1)

        let archiveURL = URL(fileURLWithPath: "/tmp/Archive.zip")
        XCTAssertEqual(selectedURLs.last, [archiveURL])
        XCTAssertEqual(controller.selectionState.selectedIDs, [FileIdentity(url: archiveURL)])
    }

}
