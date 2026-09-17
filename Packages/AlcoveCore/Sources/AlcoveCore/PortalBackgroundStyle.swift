public enum PortalBackgroundStyle: String, CaseIterable, Sendable {
    case highestTransparency = "highest_transparency"
    case maximumTransparency = "maximum_transparency"
    case highTransparency = "high_transparency"
    case standard
    case lowTransparency = "low_transparency"
    /// Retained only to decode existing preferences and layout backups.
    case minimumTransparency = "minimum_transparency"

    public static let selectableCases: [PortalBackgroundStyle] = [
        .highestTransparency,
        .maximumTransparency,
        .highTransparency,
        .standard,
        .lowTransparency,
    ]

    public var normalizedSelection: PortalBackgroundStyle {
        self == .minimumTransparency ? .lowTransparency : self
    }
}
