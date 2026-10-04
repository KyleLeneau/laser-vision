import Foundation

/// The musical grid a show is choreographed against.
public struct Tempo: Codable, Sendable, Hashable {
    private static let secondsPerMinute = 60.0

    public var bpm: Double
    /// Time in the audio file of the first downbeat (beat 0, bar 0).
    public var firstBeatSeconds: Double
    public var beatsPerBar: Int

    public init(bpm: Double, firstBeatSeconds: Double = 0, beatsPerBar: Int = 4) {
        self.bpm = bpm
        self.firstBeatSeconds = firstBeatSeconds
        self.beatsPerBar = beatsPerBar
    }

    public var secondsPerBeat: Double { Self.secondsPerMinute / bpm }

    /// Continuous beat position for a time in the track. Negative before the first downbeat.
    public func beat(at seconds: Double) -> Double {
        (seconds - firstBeatSeconds) / secondsPerBeat
    }

    public func beats(inBars bars: Double) -> Double {
        bars * Double(beatsPerBar)
    }

    public func seconds(atBeat beat: Double) -> Double {
        firstBeatSeconds + beat * secondsPerBeat
    }
}
