import AppKit

struct PortalWindowStrategy: Equatable {
    let level: NSWindow.Level
    let collectionBehavior: NSWindow.CollectionBehavior
    let canBecomeKey: Bool

    static let developmentDefault = PortalWindowStrategy(
        level: NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        ),
        collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle],
        canBecomeKey: true
    )
}
