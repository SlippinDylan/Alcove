import Dispatch
import Foundation

struct FolderVolumeMetadata: Equatable, Sendable {
    let isLocal: Bool?
    let isInternal: Bool?
    let isRemovable: Bool?
    let isEjectable: Bool?
}

enum FolderLocationRejection: Equatable, Sendable {
    case metadataUnavailable
    case notLocal
    case notInternal
    case removable
    case ejectable
}

enum FolderLocationPolicy {
    static func rejection(for metadata: FolderVolumeMetadata) -> FolderLocationRejection? {
        guard let isLocal = metadata.isLocal,
              let isInternal = metadata.isInternal,
              let isRemovable = metadata.isRemovable,
              let isEjectable = metadata.isEjectable else {
            return .metadataUnavailable
        }
        guard isLocal else { return .notLocal }
        guard isInternal else { return .notInternal }
        guard !isRemovable else { return .removable }
        guard !isEjectable else { return .ejectable }
        return nil
    }
}

struct FolderLocationValidator {
    private static let queue = DispatchQueue(
        label: "com.dylanwang.alcove.folder-location",
        qos: .userInitiated
    )
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .volumeIsLocalKey,
        .volumeIsInternalKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
    ]

    func validate(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in
            Self.queue.async {
                do {
                    continuation.resume(returning: try Self.validateSynchronously(url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func validateForRestoration(_ url: URL) async throws -> URL {
        do {
            return try await validate(url)
        } catch let error as FolderAccessError {
            guard case .folderNotFound = error else { throw error }
            return url.standardizedFileURL
        }
    }

    private static func validateSynchronously(_ url: URL) throws -> URL {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let values: URLResourceValues
        do {
            values = try resolvedURL.resourceValues(forKeys: Self.resourceKeys)
        } catch let error as NSError {
            throw FolderAccessError.classifyRootError(url: resolvedURL, error: error)
        }

        guard values.isDirectory == true else {
            let error = NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(ENOTDIR),
                userInfo: [NSFilePathErrorKey: resolvedURL.path]
            )
            throw FolderAccessError.classifyRootError(url: resolvedURL, error: error)
        }

        let metadata = FolderVolumeMetadata(
            isLocal: values.volumeIsLocal,
            isInternal: values.volumeIsInternal,
            isRemovable: values.volumeIsRemovable,
            isEjectable: values.volumeIsEjectable
        )
        if let rejection = FolderLocationPolicy.rejection(for: metadata) {
            throw FolderAccessError.unsupportedLocation(url: resolvedURL, reason: rejection)
        }
        return resolvedURL
    }
}
