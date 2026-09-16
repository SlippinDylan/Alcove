import AlcoveCore
import Foundation

struct FolderItemDiagnostic: Equatable, Sendable {
    let url: URL
    let metadata: FolderErrorMetadata
}

struct FolderEnumerationResult: Equatable, Sendable {
    let root: URL
    let generation: UInt64
    let items: [FileItem]
    let itemDiagnostics: [FolderItemDiagnostic]

    var isEmpty: Bool {
        items.isEmpty
    }
}

struct FolderErrorMetadata: Equatable, Sendable {
    let domain: String
    let code: Int
    let underlyingDomain: String?
    let underlyingCode: Int?

    init(error: NSError) {
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        domain = error.domain
        code = error.code
        underlyingDomain = underlying?.domain
        underlyingCode = underlying?.code
    }

    var posixCode: Int32? {
        if domain == NSPOSIXErrorDomain {
            return Int32(code)
        }
        guard underlyingDomain == NSPOSIXErrorDomain, let underlyingCode else {
            return nil
        }
        return Int32(underlyingCode)
    }
}

enum FolderAccessError: Error, Equatable, Sendable {
    case folderNotFound(url: URL, metadata: FolderErrorMetadata)
    case folderReplaced(url: URL)
    case notDirectory(url: URL, metadata: FolderErrorMetadata)
    case permissionDenied(url: URL, metadata: FolderErrorMetadata)
    case readFailed(url: URL, metadata: FolderErrorMetadata)
    case unsupportedLocation(url: URL, reason: FolderLocationRejection)

    static func classifyRootError(url: URL, error: NSError) -> FolderAccessError {
        let metadata = FolderErrorMetadata(error: error)
        if metadata.posixCode == ENOENT ||
            (metadata.domain == NSCocoaErrorDomain && metadata.code == NSFileReadNoSuchFileError) {
            return .folderNotFound(url: url, metadata: metadata)
        }
        if metadata.posixCode == ENOTDIR ||
            (metadata.domain == NSCocoaErrorDomain && metadata.code == NSFileReadInvalidFileNameError) {
            return .notDirectory(url: url, metadata: metadata)
        }
        if metadata.posixCode == EACCES || metadata.posixCode == EPERM ||
            (metadata.domain == NSCocoaErrorDomain && metadata.code == NSFileReadNoPermissionError) {
            return .permissionDenied(url: url, metadata: metadata)
        }
        return .readFailed(url: url, metadata: metadata)
    }

    var userMessage: String {
        switch self {
        case .folderNotFound, .folderReplaced:
            return NSLocalizedString("Folder not found", comment: "Folder access error")
        case .notDirectory:
            return NSLocalizedString(
                "The selected item is not a folder",
                comment: "Folder access error"
            )
        case .permissionDenied:
            return NSLocalizedString("Permission denied", comment: "Folder access error")
        case .readFailed:
            return NSLocalizedString(
                "Unable to read folder contents",
                comment: "Folder access error"
            )
        case .unsupportedLocation:
            return NSLocalizedString(
                "Choose a folder on this Mac's internal disk",
                comment: "Folder access error"
            )
        }
    }
}
