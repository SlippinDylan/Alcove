import AppKit

struct PortalWindowStrategy: Equatable {
    let level: NSWindow.Level
    let collectionBehavior: NSWindow.CollectionBehavior
    let canBecomeKey: Bool

    // Keep interactive Portals above normal windows and below floating auxiliary windows.
    static let foregroundLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)

    static let developmentDefault = PortalWindowStrategy(
        level: NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        ),
        collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle],
        canBecomeKey: true
    )
}
