import Foundation
import CoreGraphics

public struct IconSize: Sendable, Comparable, Hashable {
    public static let minimum: CGFloat = 16
    public static let maximum: CGFloat = 128

    public let rawValue: CGFloat

    private init(validatedRawValue: CGFloat) {
        rawValue = validatedRawValue
    }

    public init?(rawValue: CGFloat) {
        guard rawValue >= Self.minimum, rawValue <= Self.maximum else {
            return nil
        }
        self.rawValue = rawValue
    }

    public static let small = IconSize(validatedRawValue: 48)
    public static let medium = IconSize(validatedRawValue: 64)
    public static let large = IconSize(validatedRawValue: 80)

    public static func < (lhs: IconSize, rhs: IconSize) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
