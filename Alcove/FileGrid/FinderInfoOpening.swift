import Carbon
import Foundation

enum FinderInfoError: LocalizedError, Equatable {
    case itemUnavailable
    case automationDenied
    case scriptFailed(Int)

    var errorDescription: String? {
        let key: String
        switch self {
        case .itemUnavailable:
            key = "portal.files.finder_info.item_unavailable"
        case .automationDenied:
            key = "portal.files.finder_info.automation_denied"
        case .scriptFailed:
            key = "portal.files.finder_info.failed"
        }
        return NSLocalizedString(key, comment: "Finder Get Info failure")
    }
}

@MainActor
protocol FinderInfoOpening: AnyObject {
    func openInfo(for url: URL) throws
}

@MainActor
final class FinderInfoAppleEventOpener: FinderInfoOpening {
    static let scriptSource = """
        on showInfo(posixPath)
            tell application "Finder"
                activate
                open information window of (POSIX file posixPath as alias)
            end tell
        end showInfo
        """

    private var compiledScript: NSAppleScript?

    func openInfo(for rawURL: URL) throws {
        let url = rawURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FinderInfoError.itemUnavailable
        }
        let script = try script()
        var errorInfo: NSDictionary?
        _ = script.executeAppleEvent(
            Self.subroutineEvent(path: url.path),
            error: &errorInfo
        )
        if let errorInfo {
            throw Self.error(from: errorInfo)
        }
    }

    static func subroutineEvent(path: String) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(
            NSAppleEventDescriptor(string: "showInfo"),
            forKeyword: AEKeyword(keyASSubroutineName)
        )
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: path), at: 1)
        event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
        return event
    }

    static func error(from errorInfo: NSDictionary) -> FinderInfoError {
        let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        return number == Int(errAEEventNotPermitted)
            ? .automationDenied
            : .scriptFailed(number)
    }

    private func script() throws -> NSAppleScript {
        if let compiledScript {
            return compiledScript
        }
        guard let script = NSAppleScript(source: Self.scriptSource) else {
            throw FinderInfoError.scriptFailed(0)
        }
        var errorInfo: NSDictionary?
        guard script.compileAndReturnError(&errorInfo) else {
            throw Self.error(from: errorInfo ?? [:])
        }
        compiledScript = script
        return script
    }
}
