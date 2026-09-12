import CoreGraphics

/// The Finder desktop measurements captured when a portal follows the desktop.
public struct DesktopIconSettings: Equatable, Hashable, Sendable {
    public static let minimumTextSize: CGFloat = 8
    public static let maximumTextSize: CGFloat = 32
    public static let defaultTextSize: CGFloat = 12

    public let iconSize: IconSize
    public let textSize: CGFloat

    public init?(iconSize: IconSize, textSize: CGFloat) {
        guard textSize.isFinite,
              (Self.minimumTextSize...Self.maximumTextSize).contains(textSize)
        else {
            return nil
        }
        self.iconSize = iconSize
        self.textSize = textSize
    }
}

/// A portal either uses an app-selected icon size or a captured Finder desktop setting.
public enum PortalIconLayout: Equatable, Hashable, Sendable {
    case fixed(IconSize)
    case followDesktop(DesktopIconSettings)

    public var iconSize: IconSize {
        switch self {
        case .fixed(let iconSize): iconSize
        case .followDesktop(let settings): settings.iconSize
        }
    }

    public var textSize: CGFloat {
        switch self {
        case .fixed: DesktopIconSettings.defaultTextSize
        case .followDesktop(let settings): settings.textSize
        }
    }
}
