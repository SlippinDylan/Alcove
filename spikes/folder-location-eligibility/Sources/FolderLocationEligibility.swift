import Foundation

struct VolumeMetadata: Encodable, Equatable, Sendable {
    let isLocal: Bool?
    let isInternal: Bool?
    let isRemovable: Bool?
    let isEjectable: Bool?
}

enum FolderLocationRejection: String, Encodable, Equatable, Sendable {
    case metadataUnavailable
    case notLocal
    case notInternal
    case removable
    case ejectable
}

enum FolderLocationDecision: Encodable, Equatable, Sendable {
    case accepted
    case rejected(FolderLocationRejection)

    private enum CodingKeys: String, CodingKey {
        case eligible
        case rejection
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .accepted:
            try container.encode(true, forKey: .eligible)
        case .rejected(let reason):
            try container.encode(false, forKey: .eligible)
            try container.encode(reason, forKey: .rejection)
        }
    }
}

enum FolderLocationPolicy {
    static func evaluate(_ metadata: VolumeMetadata) -> FolderLocationDecision {
        guard let isLocal = metadata.isLocal,
              let isInternal = metadata.isInternal,
              let isRemovable = metadata.isRemovable,
              let isEjectable = metadata.isEjectable else {
            return .rejected(.metadataUnavailable)
        }
        guard isLocal else { return .rejected(.notLocal) }
        guard isInternal else { return .rejected(.notInternal) }
        guard !isRemovable else { return .rejected(.removable) }
        guard !isEjectable else { return .rejected(.ejectable) }
        return .accepted
    }
}

enum FolderLocationValidationError: Error, CustomStringConvertible, Equatable {
    case pathNotFound(String)
    case notDirectory(String)
    case resourceValuesFailed(path: String, domain: String, code: Int)

    var description: String {
        switch self {
        case .pathNotFound(let path):
            return "Folder not found: \(path)"
        case .notDirectory(let path):
            return "Not a directory: \(path)"
        case .resourceValuesFailed(let path, let domain, let code):
            return "Cannot read volume metadata for \(path): \(domain):\(code)"
        }
    }
}

struct FolderLocationInspection: Encodable, Equatable, Sendable {
    let resolvedPath: String
    let metadata: VolumeMetadata
    let decision: FolderLocationDecision
}

enum FoundationFolderLocationValidator {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .volumeIsLocalKey,
        .volumeIsInternalKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
    ]

    static func inspect(path: String) throws -> FolderLocationInspection {
        let inputURL = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FolderLocationValidationError.pathNotFound(inputURL.path)
        }

        let resolvedURL = inputURL.resolvingSymlinksInPath().standardizedFileURL
        let values: URLResourceValues
        do {
            values = try resolvedURL.resourceValues(forKeys: resourceKeys)
        } catch let error as NSError {
            throw FolderLocationValidationError.resourceValuesFailed(
                path: resolvedURL.path,
                domain: error.domain,
                code: error.code
            )
        }

        guard values.isDirectory == true else {
            throw FolderLocationValidationError.notDirectory(resolvedURL.path)
        }

        let metadata = VolumeMetadata(
            isLocal: values.volumeIsLocal,
            isInternal: values.volumeIsInternal,
            isRemovable: values.volumeIsRemovable,
            isEjectable: values.volumeIsEjectable
        )
        return FolderLocationInspection(
            resolvedPath: resolvedURL.path,
            metadata: metadata,
            decision: FolderLocationPolicy.evaluate(metadata)
        )
    }
}
