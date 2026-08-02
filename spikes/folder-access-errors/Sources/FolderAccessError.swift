import Darwin
import Foundation

enum FolderAccessCategory: String, Codable, Sendable {
    case folderNotFound
    case notDirectory
    case permissionDenied
    case enumerationFailed
}

struct ErrorMetadata: Codable, Equatable, Sendable {
    let domain: String
    let code: Int
    let underlyingDomain: String?
    let underlyingCode: Int?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case domain, code, underlyingDomain, underlyingCode
    }

    init(_ error: NSError) {
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        domain = error.domain
        code = error.code
        underlyingDomain = underlying?.domain
        underlyingCode = underlying?.code
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: DynamicErrorCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = dynamic.allKeys.first(where: { !known.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(
                forKey: unknown,
                in: dynamic,
                debugDescription: "Unknown key: \(unknown.stringValue)"
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decode(String.self, forKey: .domain)
        code = try container.decode(Int.self, forKey: .code)
        underlyingDomain = try container.decodeIfPresent(String.self, forKey: .underlyingDomain)
        underlyingCode = try container.decodeIfPresent(Int.self, forKey: .underlyingCode)
    }
}

private struct DynamicErrorCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct ClassifiedFolderAccessError: Codable, Equatable, Sendable {
    let category: FolderAccessCategory
    let metadata: ErrorMetadata
    let observedPOSIXCode: Int32?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case category, metadata, observedPOSIXCode
    }

    init(
        category: FolderAccessCategory,
        metadata: ErrorMetadata,
        observedPOSIXCode: Int32?
    ) {
        self.category = category
        self.metadata = metadata
        self.observedPOSIXCode = observedPOSIXCode
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: DynamicErrorCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = dynamic.allKeys.first(where: { !known.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(
                forKey: unknown,
                in: dynamic,
                debugDescription: "Unknown key: \(unknown.stringValue)"
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(FolderAccessCategory.self, forKey: .category)
        metadata = try container.decode(ErrorMetadata.self, forKey: .metadata)
        observedPOSIXCode = try container.decodeIfPresent(Int32.self, forKey: .observedPOSIXCode)
    }
}

func classifyEnumerationError(_ error: NSError) -> ClassifiedFolderAccessError {
    let metadata = ErrorMetadata(error)
    let observedPOSIXCode: Int32?
    if error.domain == NSPOSIXErrorDomain {
        observedPOSIXCode = Int32(error.code)
    } else if metadata.underlyingDomain == NSPOSIXErrorDomain,
              let underlyingCode = metadata.underlyingCode {
        observedPOSIXCode = Int32(underlyingCode)
    } else {
        observedPOSIXCode = nil
    }

    let category: FolderAccessCategory
    switch observedPOSIXCode {
    case ENOENT: category = .folderNotFound
    case ENOTDIR: category = .notDirectory
    case EACCES, EPERM: category = .permissionDenied
    default:
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError {
            category = .folderNotFound
        } else if error.domain == NSCocoaErrorDomain,
                  error.code == NSFileReadNoPermissionError {
            category = .permissionDenied
        } else {
            category = .enumerationFailed
        }
    }

    return ClassifiedFolderAccessError(
        category: category,
        metadata: metadata,
        observedPOSIXCode: observedPOSIXCode
    )
}
