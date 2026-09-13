/// A stable sRGB color used to tint one portal's material surface.
public struct PortalTintColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    fileprivate init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// The built-in tint choices for one portal. `default` preserves the neutral material.
public enum PortalTint: String, CaseIterable, Sendable {
    case `default`
    case red
    case orange
    case yellow
    case green
    case blue
    case indigo
    case purple

    public var color: PortalTintColor? {
        switch self {
        case .default:
            nil
        case .red:
            PortalTintColor(red: 1, green: 0.23, blue: 0.19)
        case .orange:
            PortalTintColor(red: 1, green: 0.58, blue: 0)
        case .yellow:
            PortalTintColor(red: 1, green: 0.80, blue: 0)
        case .green:
            PortalTintColor(red: 0.20, green: 0.78, blue: 0.35)
        case .blue:
            PortalTintColor(red: 0, green: 0.48, blue: 1)
        case .indigo:
            PortalTintColor(red: 0.35, green: 0.34, blue: 0.84)
        case .purple:
            PortalTintColor(red: 0.69, green: 0.32, blue: 0.87)
        }
    }
}
