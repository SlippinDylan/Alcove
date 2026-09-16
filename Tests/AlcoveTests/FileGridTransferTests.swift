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
    func testExternalDropDefaultsToCopyAndCommandRequestsMove() {
        XCTAssertEqual(
            FileGridViewController.requestedDropOperation(
                sourceMask: [.copy, .move],
                modifiers: []
            ),
            [.copy, .move]
        )
        XCTAssertEqual(
            FileGridViewController.requestedDropOperation(
                sourceMask: [.copy, .move],
                modifiers: .command
            ),
            .move
        )
        XCTAssertEqual(
            FileGridViewController.requestedDropOperation(
                sourceMask: .copy,
                modifiers: .command
            ),
            .copy
        )
        XCTAssertEqual(
            FileGridViewController.requestedDropOperation(
                sourceMask: [.copy, .move],
                modifiers: [],
                isLocal: true
            ),
            .move
        )
        XCTAssertEqual(
            FileGridViewController.requestedTransferOperation(
                sourceMask: [.copy, .move],
                modifiers: []
            ),
            .automatic
        )
        XCTAssertNil(FileGridViewController.requestedTransferOperation(
            sourceMask: [.copy, .move],
            modifiers: [.command, .option]
        ))
        XCTAssertEqual(
            FileTransferOperation.automatic.resolved(
                sourceVolumeURL: URL(fileURLWithPath: "/Volumes/Source"),
                destinationVolumeURL: URL(fileURLWithPath: "/Volumes/Source")
            ),
            .move
        )
        XCTAssertEqual(
            FileTransferOperation.automatic.resolved(
                sourceVolumeURL: URL(fileURLWithPath: "/Volumes/Source"),
                destinationVolumeURL: URL(fileURLWithPath: "/Volumes/Destination")
            ),
            .copy
        )
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
    func testFolderTilesAcceptExternalAndLocalDropsWhileFilesAndBackgroundRejectLocalDrops() {
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
        XCTAssertNil(controller.destinationURL(forDropAt: 1, isLocal: false))
        XCTAssertNil(controller.destinationURL(forDropAt: 2, isLocal: false))
        XCTAssertNil(controller.destinationURL(forDropAt: 3, isLocal: false))
        XCTAssertEqual(controller.destinationURL(forDropAt: nil, isLocal: false), currentURL)
        XCTAssertNil(controller.destinationURL(forDropAt: nil, isLocal: true))
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
        try await service.transfer(
            sourceURLs: [automaticSource],
            to: moveDestination,
            operation: .automatic
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: automaticSource.path))
        XCTAssertEqual(
            try Data(contentsOf: moveDestination.appendingPathComponent("automatic.txt")),
            Data("automatic".utf8)
        )
    }

}
