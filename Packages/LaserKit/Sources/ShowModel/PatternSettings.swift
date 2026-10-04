import Foundation

/// The family of laser geometry a cue draws. Each kind maps to one GPU pattern kernel.
public enum PatternKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Golden-angle sunflower spiral of dots (r = c·√n, θ = n·137.5°).
    case phyllotaxis
    /// Lissajous figure x = sin(aθ + φ), y = sin(bθ).
    case lissajous
    /// Concentric rings flowing outward from the zenith.
    case tunnel
    /// Hypotrochoid "spirograph" curve.
    case spirograph
    /// Radial spokes that flash outward on onsets.
    case radialBurst
    /// A ring deformed by the live audio waveform.
    case waveformRing
    /// A sweeping fan of beam end-points; reads best with haze on.
    case beamFan
}

/// Pattern-independent knobs. Each kernel interprets them as documented per field;
/// values are normalized so shows are portable between renderers.
public struct PatternParameters: Codable, Sendable, Hashable {
    /// Animation rate multiplier. 1 is the nominal, tempo-locked speed.
    public var speed: Double
    /// Fraction (0…1) of the dome radius the pattern spans.
    public var scale: Double
    /// Fraction (0…1) of the kernel's maximum element count (dots, rings, spokes…).
    public var density: Double
    /// Rotational fold or frequency ratio, depending on the pattern. At least 1.
    public var symmetry: Int
    /// Pattern-specific shape morph (0…1), e.g. Lissajous phase or spirograph pen offset.
    public var variation: Double
    /// How strongly live audio features modulate size and brightness (0…1).
    public var audioReactivity: Double
    /// Palette indices for the two colors a pattern blends between.
    public var primaryColor: Int
    public var secondaryColor: Int

    public static let standard = PatternParameters()

    public init(
        speed: Double = 1,
        scale: Double = 0.6,
        density: Double = 0.5,
        symmetry: Int = 3,
        variation: Double = 0.5,
        audioReactivity: Double = 0.5,
        primaryColor: Int = 0,
        secondaryColor: Int = 1
    ) {
        self.speed = speed
        self.scale = scale
        self.density = density
        self.symmetry = symmetry
        self.variation = variation
        self.audioReactivity = audioReactivity
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
    }

    private enum CodingKeys: String, CodingKey {
        case speed, scale, density, symmetry, variation, audioReactivity, primaryColor, secondaryColor
    }

    /// Every field is optional in JSON and falls back to `standard`, keeping show files terse.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.standard
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? fallback.speed
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? fallback.scale
        density = try container.decodeIfPresent(Double.self, forKey: .density) ?? fallback.density
        symmetry = try container.decodeIfPresent(Int.self, forKey: .symmetry) ?? fallback.symmetry
        variation = try container.decodeIfPresent(Double.self, forKey: .variation) ?? fallback.variation
        audioReactivity = try container.decodeIfPresent(Double.self, forKey: .audioReactivity) ?? fallback.audioReactivity
        primaryColor = try container.decodeIfPresent(Int.self, forKey: .primaryColor) ?? fallback.primaryColor
        secondaryColor = try container.decodeIfPresent(Int.self, forKey: .secondaryColor) ?? fallback.secondaryColor
    }
}

/// A pattern kind together with its parameters.
public struct PatternSettings: Codable, Sendable, Hashable {
    public var kind: PatternKind
    public var parameters: PatternParameters

    public init(kind: PatternKind, parameters: PatternParameters = .standard) {
        self.kind = kind
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey { case kind, parameters }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(PatternKind.self, forKey: .kind)
        parameters = try container.decodeIfPresent(PatternParameters.self, forKey: .parameters) ?? .standard
    }
}
