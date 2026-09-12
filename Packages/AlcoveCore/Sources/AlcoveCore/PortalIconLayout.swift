import CoreGraphics

/// A portal uses one of Alcove's app-selected icon sizes.
public enum PortalIconLayout: Equatable, Hashable, Sendable {
    case fixed(IconSize)

    public var iconSize: IconSize {
        switch self {
        case .fixed(let iconSize): iconSize
        }
    }

    public var textSize: CGFloat {
        12
    }
}
