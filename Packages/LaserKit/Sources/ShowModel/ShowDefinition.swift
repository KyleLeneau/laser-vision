import Foundation

/// A complete laser show: metadata, the audio it plays against, and the cue timeline
/// that choreographs patterns to the music.
///
/// This is the on-disk interchange format (`*.show.json`) shared by the player and a
/// future editor, so changes must stay backwards compatible or bump `formatVersion`.
public struct ShowDefinition: Codable, Sendable, Hashable, Identifiable {
    /// The newest format version this build can read.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var id: String
    public var title: String
    public var artist: String
    public var album: String?
    public var audio: AudioReference
    public var tempo: Tempo
    public var palette: ColorPalette
    /// The pattern that best represents the show; rendered as the library card's key visual.
    public var signature: PatternSettings
    /// Cues ordered by `startBar`. The first cue is active from the start of the track.
    public var cues: [Cue]

    public init(
        formatVersion: Int = ShowDefinition.currentFormatVersion,
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        audio: AudioReference,
        tempo: Tempo,
        palette: ColorPalette,
        signature: PatternSettings,
        cues: [Cue]
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.audio = audio
        self.tempo = tempo
        self.palette = palette
        self.signature = signature
        self.cues = cues
    }

    /// Checks invariants the decoder cannot express. Throws the first problem found.
    public func validate() throws(ShowValidationError) {
        guard formatVersion <= Self.currentFormatVersion else {
            throw .unsupportedFormatVersion(formatVersion)
        }
        guard tempo.bpm > 0 else { throw .invalidTempo }
        guard tempo.beatsPerBar > 0 else { throw .invalidTempo }
        guard !palette.colors.isEmpty else { throw .emptyPalette }
        guard !cues.isEmpty else { throw .noCues }
        for (previous, next) in zip(cues, cues.dropFirst()) where next.startBar <= previous.startBar {
            throw .cuesOutOfOrder(bar: next.startBar)
        }
        if let negative = cues.first(where: { $0.transitionBeats < 0 }) {
            throw .negativeTransition(bar: negative.startBar)
        }
    }
}

public enum ShowValidationError: Error, Equatable, Sendable {
    case unsupportedFormatVersion(Int)
    case invalidTempo
    case emptyPalette
    case noCues
    case cuesOutOfOrder(bar: Double)
    case negativeTransition(bar: Double)
}

/// Where a show's audio file lives.
public struct AudioReference: Codable, Sendable, Hashable {
    public enum Location: String, Codable, Sendable, Hashable {
        /// Shipped inside the app bundle.
        case bundled
        /// Supplied locally by the developer (copyrighted tracks that cannot be redistributed).
        case userSupplied
    }

    public var location: Location
    public var fileName: String

    public init(location: Location, fileName: String) {
        self.location = location
        self.fileName = fileName
    }
}

/// A single moment in the show where the pattern changes.
public struct Cue: Codable, Sendable, Hashable {
    /// Bar (zero-based, may be fractional) at which this cue begins.
    public var startBar: Double
    public var pattern: PatternSettings
    /// Beats spent cross-fading from the previous cue. Zero is a hard cut.
    public var transitionBeats: Double

    public static let defaultTransitionBeats = 2.0

    public init(startBar: Double, pattern: PatternSettings, transitionBeats: Double = Cue.defaultTransitionBeats) {
        self.startBar = startBar
        self.pattern = pattern
        self.transitionBeats = transitionBeats
    }

    private enum CodingKeys: String, CodingKey { case startBar, pattern, transitionBeats }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startBar = try container.decode(Double.self, forKey: .startBar)
        pattern = try container.decode(PatternSettings.self, forKey: .pattern)
        transitionBeats = try container.decodeIfPresent(Double.self, forKey: .transitionBeats) ?? Self.defaultTransitionBeats
    }
}
