import Foundation

/// Music features at one instant, each normalized to roughly 0…1.
public struct AudioFeatures: Sendable, Equatable {
    /// Overall loudness (RMS), auto-gain normalized.
    public var energy: Float
    /// Low band (kick, bass line).
    public var bass: Float
    /// Middle band (vocals, chords).
    public var mid: Float
    /// High band (hats, cymbals, air).
    public var treble: Float
    /// 1 at a detected onset, decaying exponentially towards 0 afterwards.
    public var onsetPulse: Float

    public static let silent = AudioFeatures(energy: 0, bass: 0, mid: 0, treble: 0, onsetPulse: 0)

    public init(energy: Float, bass: Float, mid: Float, treble: Float, onsetPulse: Float) {
        self.energy = energy
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.onsetPulse = onsetPulse
    }
}

/// A track's features sampled on a fixed hop grid, computed ahead of playback by
/// `AudioAnalyzer`. Looked up by playback time, so visuals stay sample-locked to the audio
/// with none of the latency of a live tap.
public struct AudioAnalysis: Sendable {
    /// Points in each per-frame waveform snapshot (used by the waveform-ring pattern).
    public static let waveformLength = 64
    /// Seconds for the onset pulse to fall to 1/e.
    public static let onsetPulseDecaySeconds = 0.12

    struct Frame: Sendable {
        var energy: Float
        var bass: Float
        var mid: Float
        var treble: Float
    }

    /// Seconds between consecutive frames.
    public let hopDuration: Double
    /// Track time at the center of frame 0.
    let firstFrameTime: Double
    let frames: [Frame]
    /// `frames.count * waveformLength` samples in -1…1.
    let waveforms: [Float]
    /// Ascending onset times in seconds.
    public let onsetTimes: [Double]

    init(hopDuration: Double, firstFrameTime: Double, frames: [Frame], waveforms: [Float], onsetTimes: [Double]) {
        precondition(waveforms.count == frames.count * Self.waveformLength)
        self.hopDuration = hopDuration
        self.firstFrameTime = firstFrameTime
        self.frames = frames
        self.waveforms = waveforms
        self.onsetTimes = onsetTimes
    }

    public var frameCount: Int { frames.count }

    /// Interpolated features at a track time. Times outside the track clamp to the ends.
    public func features(at time: Double) -> AudioFeatures {
        guard !frames.isEmpty else { return .silent }
        let position = (time - firstFrameTime) / hopDuration
        let clamped = min(max(position, 0), Double(frames.count - 1))
        let lowerIndex = Int(clamped)
        let upperIndex = min(lowerIndex + 1, frames.count - 1)
        let t = Float(clamped - Double(lowerIndex))
        let lower = frames[lowerIndex]
        let upper = frames[upperIndex]

        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }

        return AudioFeatures(
            energy: mix(lower.energy, upper.energy),
            bass: mix(lower.bass, upper.bass),
            mid: mix(lower.mid, upper.mid),
            treble: mix(lower.treble, upper.treble),
            onsetPulse: onsetPulse(at: time)
        )
    }

    /// Copies the waveform snapshot nearest `time` into `destination`
    /// (which must hold `waveformLength` floats). Writes silence if there is no audio.
    public func copyWaveform(at time: Double, into destination: UnsafeMutablePointer<Float>) {
        guard !frames.isEmpty else {
            destination.update(repeating: 0, count: Self.waveformLength)
            return
        }
        let position = ((time - firstFrameTime) / hopDuration).rounded()
        let index = Int(min(max(position, 0), Double(frames.count - 1)))
        waveforms.withUnsafeBufferPointer { samples in
            destination.update(from: samples.baseAddress! + index * Self.waveformLength, count: Self.waveformLength)
        }
    }

    private func onsetPulse(at time: Double) -> Float {
        guard let lastOnset = lastOnsetTime(atOrBefore: time) else { return 0 }
        return Float(exp(-(time - lastOnset) / Self.onsetPulseDecaySeconds))
    }

    private func lastOnsetTime(atOrBefore time: Double) -> Double? {
        var low = 0
        var high = onsetTimes.count
        while low < high {
            let mid = (low + high) / 2
            if onsetTimes[mid] <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low > 0 ? onsetTimes[low - 1] : nil
    }
}
