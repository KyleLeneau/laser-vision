import Foundation
import simd

/// A linear-ish RGB laser color, stored in JSON as a `#RRGGBB` hex string.
public struct LaserColor: Codable, Sendable, Hashable {
    private static let hexPrefix = "#"
    private static let hexDigits = 6
    private static let channelMax: Float = 255

    public var red: Float
    public var green: Float
    public var blue: Float

    public init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#RRGGBB` (the leading `#` is optional).
    public init?(hex: String) {
        let digits = hex.hasPrefix(Self.hexPrefix) ? String(hex.dropFirst()) : hex
        guard digits.count == Self.hexDigits, let value = UInt32(digits, radix: 16) else { return nil }
        red = Float((value >> 16) & 0xFF) / Self.channelMax
        green = Float((value >> 8) & 0xFF) / Self.channelMax
        blue = Float(value & 0xFF) / Self.channelMax
    }

    public var hexString: String {
        func byte(_ channel: Float) -> Int { Int((min(max(channel, 0), 1) * Self.channelMax).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    public var simd: SIMD3<Float> { SIMD3(red, green, blue) }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = LaserColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected #RRGGBB, got \(string)")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

/// The set of laser colors a show draws from. Patterns reference colors by index.
public struct ColorPalette: Codable, Sendable, Hashable {
    public var colors: [LaserColor]

    public init(colors: [LaserColor]) {
        self.colors = colors
    }

    /// Returns the color at `index`, wrapping so out-of-range indices are always safe.
    public func color(at index: Int) -> LaserColor {
        precondition(!colors.isEmpty, "A validated palette is never empty")
        let count = colors.count
        return colors[((index % count) + count) % count]
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        colors = try container.decode([LaserColor].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(colors)
    }
}
