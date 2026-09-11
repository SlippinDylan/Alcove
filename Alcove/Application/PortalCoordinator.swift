import AppKit

@MainActor
protocol PortalCoordinating: AnyObject {
    func createPortal(for folderURL: URL) async throws
}

@MainActor
final class PortalCoordinator: PortalCoordinating {
    private let locationValidator: FolderLocationValidator
    private var windowControllers: [PortalWindowController] = []

    init(locationValidator: FolderLocationValidator = FolderLocationValidator()) {
        self.locationValidator = locationValidator
    }

    func createPortal(for folderURL: URL) async throws {
        let folderURL = try await locationValidator.validate(folderURL)
        let loadingCoordinator = FolderLoadingCoordinator()
        let controller = PortalWindowController(
            folderURL: folderURL,
            loadingCoordinator: loadingCoordinator
        )
        windowControllers.append(controller)
        controller.present()
    }
}

enum StartupFolderResolver {
    static func resolve(arguments: [String]) -> URL? {
        guard arguments.count == 3, arguments[1] == "--folder" else { return nil }
        return URL(fileURLWithPath: arguments[2]).standardizedFileURL
    }
}
