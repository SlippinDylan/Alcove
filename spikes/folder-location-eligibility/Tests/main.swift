import Darwin
import Foundation

private final class TestSuite {
    private(set) var assertions = 0
    private(set) var failures = 0

    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        expect(actual == expected, "\(message) — expected \(expected), got \(actual)")
    }
}

private func metadata(
    local: Bool? = true,
    internalVolume: Bool? = true,
    removable: Bool? = false,
    ejectable: Bool? = false
) -> VolumeMetadata {
    VolumeMetadata(
        isLocal: local,
        isInternal: internalVolume,
        isRemovable: removable,
        isEjectable: ejectable
    )
}

private func testPolicy(_ suite: TestSuite) {
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata()), .accepted, "Internal fixed local volume should be accepted")
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata(local: false)), .rejected(.notLocal), "Network volume should be rejected")
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata(internalVolume: false)), .rejected(.notInternal), "External volume should be rejected")
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata(removable: true)), .rejected(.removable), "Removable volume should be rejected")
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata(ejectable: true)), .rejected(.ejectable), "Ejectable volume should be rejected")
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata(local: nil)), .rejected(.metadataUnavailable), "Missing local metadata should fail closed")
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata(internalVolume: nil)), .rejected(.metadataUnavailable), "Missing internal metadata should fail closed")
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata(removable: nil)), .rejected(.metadataUnavailable), "Missing removable metadata should fail closed")
    suite.expectEqual(FolderLocationPolicy.evaluate(metadata(ejectable: nil)), .rejected(.metadataUnavailable), "Missing ejectable metadata should fail closed")
    suite.expectEqual(
        FolderLocationPolicy.evaluate(metadata(local: false, internalVolume: false, removable: true, ejectable: true)),
        .rejected(.notLocal),
        "Non-local rejection should take precedence"
    )
}

private func testRealFilesystem(_ suite: TestSuite) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("folder-location-tests-\(UUID().uuidString)", isDirectory: true)
    let target = root.appendingPathComponent("target", isDirectory: true)
    let link = root.appendingPathComponent("link", isDirectory: true)
    let file = root.appendingPathComponent("file.txt", isDirectory: false)
    let missing = root.appendingPathComponent("missing", isDirectory: true)

    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    do {
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try Data("fixture".utf8).write(to: file)

        let targetInspection = try FoundationFolderLocationValidator.inspect(path: target.path)
        suite.expectEqual(targetInspection.decision, .accepted, "Temporary directory on the current internal volume should be eligible")
        suite.expectEqual(targetInspection.metadata.isLocal, true, "Temporary directory volume should be local")
        suite.expectEqual(targetInspection.metadata.isInternal, true, "Temporary directory volume should be internal")
        suite.expectEqual(targetInspection.metadata.isRemovable, false, "Temporary directory volume should not be removable")
        suite.expectEqual(targetInspection.metadata.isEjectable, false, "Temporary directory volume should not be ejectable")

        let linkInspection = try FoundationFolderLocationValidator.inspect(path: link.path)
        suite.expectEqual(linkInspection.resolvedPath, targetInspection.resolvedPath, "Symlink should be resolved before volume validation")
        suite.expectEqual(linkInspection.decision, targetInspection.decision, "Symlink should inherit the target volume decision")

        do {
            _ = try FoundationFolderLocationValidator.inspect(path: file.path)
            suite.expect(false, "Regular file should be rejected")
        } catch let error as FolderLocationValidationError {
            suite.expectEqual(error, .notDirectory(file.path), "Regular file should produce notDirectory")
        }

        do {
            _ = try FoundationFolderLocationValidator.inspect(path: missing.path)
            suite.expect(false, "Missing path should be rejected")
        } catch let error as FolderLocationValidationError {
            suite.expectEqual(error, .pathNotFound(missing.path), "Missing path should produce pathNotFound")
        }
    } catch {
        do {
            try FileManager.default.removeItem(at: root)
        } catch let cleanupError {
            throw NSError(
                domain: "FolderLocationTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Primary: \(error); cleanup: \(cleanupError)"
                ]
            )
        }
        throw error
    }

    try FileManager.default.removeItem(at: root)
    suite.expect(!FileManager.default.fileExists(atPath: root.path), "Fixture root should be removed")
}

private func run() -> Int32 {
    let suite = TestSuite()
    testPolicy(suite)
    do {
        try testRealFilesystem(suite)
    } catch {
        suite.expect(false, "Filesystem tests failed: \(error)")
    }

    print("Assertions: \(suite.assertions)")
    print("Failures: \(suite.failures)")
    return suite.failures == 0 ? 0 : 1
}

exit(run())
