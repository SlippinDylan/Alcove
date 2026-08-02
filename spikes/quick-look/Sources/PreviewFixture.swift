// PreviewFixture.swift
// Alcove Spike 0.3A — Quick Look Responder Bootstrap
// Disposable harness; not production architecture.

import Foundation
import Quartz

struct PreviewFixture: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let displayName: String
}

enum PreviewFixtureStoreError: LocalizedError {
    case invalidFileName(String)
    case rollbackFailed(creation: Error, cleanup: Error)

    var errorDescription: String? {
        switch self {
        case .invalidFileName(let name):
            return "Invalid preview fixture file name: \(name)"
        case .rollbackFailed(let creation, let cleanup):
            return "Fixture creation failed (\(creation.localizedDescription)); rollback also failed (\(cleanup.localizedDescription))."
        }
    }
}

/// Owns one unique temporary directory and all fixture files within it.
/// Cleanup is explicit, throwing, and idempotent so teardown failures remain visible.
final class PreviewFixtureStore {
    let fixtures: [PreviewFixture]

    private let directoryURL: URL
    private var isCleanedUp = false

    private init(directoryURL: URL, fixtures: [PreviewFixture]) {
        self.directoryURL = directoryURL
        self.fixtures = fixtures
    }

    static func create(_ specifications: [(fileName: String, content: String)]) throws -> PreviewFixtureStore {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("AlcoveQLSpike-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        do {
            let fixtures = try specifications.map { specification in
                guard isSafeFileName(specification.fileName) else {
                    throw PreviewFixtureStoreError.invalidFileName(specification.fileName)
                }
                let url = directoryURL.appendingPathComponent(specification.fileName, isDirectory: false)
                try specification.content.write(to: url, atomically: true, encoding: .utf8)
                return PreviewFixture(id: UUID(), url: url, displayName: specification.fileName)
            }
            return PreviewFixtureStore(directoryURL: directoryURL, fixtures: fixtures)
        } catch let creationError {
            do {
                try fileManager.removeItem(at: directoryURL)
            } catch let cleanupError {
                throw PreviewFixtureStoreError.rollbackFailed(
                    creation: creationError,
                    cleanup: cleanupError
                )
            }
            throw creationError
        }
    }

    func cleanup() throws {
        guard !isCleanedUp else { return }
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        isCleanedUp = true
    }

    private static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return URL(fileURLWithPath: name).lastPathComponent == name
            && !name.contains("/")
            && !name.contains(":")
    }
}

final class FixturePreviewItem: NSObject, QLPreviewItem {
    let fixtureURL: URL
    let fixtureTitle: String

    init(fixture: PreviewFixture) {
        self.fixtureURL = fixture.url
        self.fixtureTitle = fixture.displayName
        super.init()
    }

    var previewItemURL: URL? { fixtureURL }
    var previewItemTitle: String? { fixtureTitle }
}

final class UnavailablePreviewItem: NSObject, QLPreviewItem {
    var previewItemURL: URL? { nil }
    var previewItemTitle: String? { "Preview unavailable" }
}
