// Synthesizes the two royalty-free demo tracks bundled with Laser Vision.
//
// The output is deterministic, and the arrangements (bars, tempo) match the cue timelines in
// LaserVision/Resources/Shows/01-golden-angle.show.json and 02-pulse-field.show.json.
//
// Usage (from the repository root):
//   swiftc -O Tools/generate-demo-tracks.swift -o /tmp/generate-demo-tracks
//   /tmp/generate-demo-tracks LaserVision/Resources/Audio
//
// Writes golden-angle.m4a and pulse-field.m4a (AAC) into the given directory.

import AVFoundation
import Foundation

let sampleRate = 44_100.0

// MARK: - Mix buffer

struct StereoBuffer {
    var left: [Float]
    var right: [Float]

    init(seconds: Double) {
        let count = Int(seconds * sampleRate)
        left = [Float](repeating: 0, count: count)
        right = [Float](repeating: 0, count: count)
    }

    var count: Int { left.count }

    /// Renders `voice(t)` (t = seconds since note start) for `duration` seconds starting at `start`, panned (-1 left … 1 right).
    mutating func add(at start: Double, duration: Double, gain: Float, pan: Float = 0, voice: (Double) -> Float) {
        let first = Int(start * sampleRate)
        let last = min(count, first + Int(duration * sampleRate))
        guard first < last else { return }
        let leftGain = gain * min(1, 1 - pan)
        let rightGain = gain * min(1, 1 + pan)
        for index in first..<last {
            let sample = voice(Double(index - first) / sampleRate)
            left[index] += sample * leftGain
            right[index] += sample * rightGain
        }
    }

    /// Ping-pong feedback delay.
    mutating func applyDelay(seconds: Double, feedback: Float, mix: Float) {
        let offset = Int(seconds * sampleRate)
        guard offset > 0 else { return }
        var delayedLeft = [Float](repeating: 0, count: count)
        var delayedRight = [Float](repeating: 0, count: count)
        for index in offset..<count {
            delayedLeft[index] = right[index - offset] * mix + delayedRight[index - offset] * feedback
            delayedRight[index] = left[index - offset] * mix + delayedLeft[index - offset] * feedback
        }
        for index in 0..<count {
            left[index] += delayedLeft[index]
            right[index] += delayedRight[index]
        }
    }

    /// Soft-clips and fades in/out.
    mutating func master(gain: Float, fadeInSeconds: Double, fadeOutSeconds: Double) {
        let fadeIn = Int(fadeInSeconds * sampleRate)
        let fadeOut = Int(fadeOutSeconds * sampleRate)
        for index in 0..<count {
            var envelope: Float = 1
            if index < fadeIn { envelope = Float(index) / Float(fadeIn) }
            if index > count - fadeOut { envelope = min(envelope, Float(count - index) / Float(fadeOut)) }
            left[index] = tanh(left[index] * gain) * envelope
            right[index] = tanh(right[index] * gain) * envelope
        }
    }
}

// MARK: - Voices

struct Noise {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// Uniform white noise in -1…1 (64-bit LCG, top bits).
    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(state >> 40) / Float(1 << 23) - 1
    }
}

func midiToHz(_ note: Int) -> Double { 440 * pow(2, Double(note - 69) / 12) }

/// Sine kick sweeping 130 Hz → 45 Hz (phase is the integral of the pitch envelope).
func kick(_ t: Double) -> Float {
    let phase = 2 * Double.pi * (45 * t + 85 * (1 - exp(-t * 30)) / 30)
    return Float(sin(phase) * exp(-t * 7))
}

func makeHat(seed: UInt64, decay: Double) -> (Double) -> Float {
    var noise = Noise(seed: seed)
    var previous: Float = 0
    return { t in
        let sample = noise.next()
        let highPassed = sample - previous
        previous = sample
        return highPassed * Float(exp(-t * decay))
    }
}

func makeClap(seed: UInt64) -> (Double) -> Float {
    var noise = Noise(seed: seed)
    var low: Float = 0
    return { t in
        let sample = noise.next()
        low += (sample - low) * 0.3
        return (sample - low) * Float(exp(-t * 18))
    }
}

func makeSawBass(note: Int, cutoff: Float, decay: Double) -> (Double) -> Float {
    let frequency = midiToHz(note)
    var filtered: Float = 0
    return { t in
        let saw = Float(2 * (t * frequency - floor(t * frequency + 0.5)))
        filtered += (saw - filtered) * cutoff
        return filtered * Float(exp(-t * decay))
    }
}

func pluck(note: Int, decay: Double) -> (Double) -> Float {
    let frequency = midiToHz(note)
    return { t in
        let tone = sin(2 * .pi * frequency * t) + 0.3 * sin(4 * .pi * frequency * t)
        return Float(tone * exp(-t * decay))
    }
}

func pad(notes: [Int], duration: Double, attack: Double) -> (Double) -> Float {
    let frequencies = notes.flatMap { note in [midiToHz(note) * 0.998, midiToHz(note) * 1.002] }
    let scale = 1 / Float(frequencies.count)
    return { t in
        let envelope = min(1, t / attack) * min(1, max(0, (duration - t) / attack))
        let tone = frequencies.reduce(0.0) { $0 + sin(2 * .pi * $1 * t) }
        return Float(tone * envelope) * scale
    }
}

// MARK: - Arrangements

struct Track {
    let fileName: String
    let bpm: Double
    let bars: Int
    var beat: Double { 60 / bpm }
    var bar: Double { beat * 4 }
    var seconds: Double { Double(bars) * bar }

    func time(bar: Int, beat: Double = 0) -> Double { Double(bar) * self.bar + beat * self.beat }
}

/// 90 BPM, 48 bars, A minor. Intro 0–8 pad + arp · groove 8–32 · breakdown 32–40 · finale 40–48.
func goldenAngle() -> (Track, StereoBuffer) {
    let track = Track(fileName: "golden-angle", bpm: 90, bars: 48)
    var mix = StereoBuffer(seconds: track.seconds)
    // Am – F – C – G, two bars each.
    let chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
    let isBreakdown = { (bar: Int) in (32..<40).contains(bar) }

    for bar in 0..<track.bars {
        let chord = chords[(bar / 2) % chords.count]
        if bar % 2 == 0 {
            mix.add(at: track.time(bar: bar), duration: track.bar * 2, gain: 0.35,
                    voice: pad(notes: chord.map { $0 - 12 } + chord, duration: track.bar * 2, attack: 0.8))
        }
        if !isBreakdown(bar) {
            let arpNotes = chord + chord.map { $0 + 12 } + [chord[0] + 24]
            for step in 0..<16 {
                let note = arpNotes[(step * 3 + bar) % arpNotes.count]
                mix.add(at: track.time(bar: bar, beat: Double(step) / 4), duration: 0.6, gain: 0.18,
                        pan: step.isMultiple(of: 2) ? -0.5 : 0.5, voice: pluck(note: note, decay: 9))
            }
        }
        if bar >= 8, !isBreakdown(bar) {
            for beat in [0.0, 2.0] {
                mix.add(at: track.time(bar: bar, beat: beat), duration: 0.6, gain: 0.7, voice: kick)
            }
            mix.add(at: track.time(bar: bar), duration: track.bar, gain: 0.25,
                    voice: makeSawBass(note: chord[0] - 24, cutoff: 0.05, decay: 1.2))
        }
        if bar >= 16, !isBreakdown(bar) {
            for eighth in 0..<8 {
                mix.add(at: track.time(bar: bar, beat: Double(eighth) / 2 + 0.25), duration: 0.1, gain: 0.08,
                        pan: 0.3, voice: makeHat(seed: UInt64(bar * 8 + eighth), decay: 60))
            }
        }
    }
    mix.applyDelay(seconds: track.beat * 0.75, feedback: 0.35, mix: 0.3)
    mix.master(gain: 1.4, fadeInSeconds: 0.05, fadeOutSeconds: track.bar * 2)
    return (track, mix)
}

/// 124 BPM, 72 bars, E minor. Intro 0–8 hats + bass · build 8–16 kick · main 16–40 ·
/// breakdown 40–48 (no drums, riser) · drop 48–64 · outro 64–72.
func pulseField() -> (Track, StereoBuffer) {
    let track = Track(fileName: "pulse-field", bpm: 124, bars: 72)
    var mix = StereoBuffer(seconds: track.seconds)
    // Em – C – D – Bm, two bars each.
    let chords = [[52, 55, 59], [48, 52, 55], [50, 54, 57], [47, 50, 54]]
    let isBreakdown = { (bar: Int) in (40..<48).contains(bar) }
    let hasKick = { (bar: Int) in bar >= 8 && !isBreakdown(bar) }
    let isPeak = { (bar: Int) in (16..<40).contains(bar) || (48..<64).contains(bar) }

    for bar in 0..<track.bars {
        let chord = chords[(bar / 2) % chords.count]
        if hasKick(bar) {
            for beat in 0..<4 {
                mix.add(at: track.time(bar: bar, beat: Double(beat)), duration: 0.5, gain: 0.9, voice: kick)
            }
        }
        if isPeak(bar) {
            for beat in [1.0, 3.0] {
                mix.add(at: track.time(bar: bar, beat: beat), duration: 0.3, gain: 0.35,
                        voice: makeClap(seed: UInt64(bar * 4) + UInt64(beat)))
            }
            for stab in [0.0, 1.5, 3.0] {
                mix.add(at: track.time(bar: bar, beat: stab), duration: 0.4, gain: 0.22,
                        voice: pad(notes: chord.map { $0 + 12 }, duration: 0.4, attack: 0.01))
            }
        }
        if !isBreakdown(bar) {
            for eighth in 0..<8 {
                let isOffbeat = !eighth.isMultiple(of: 2)
                mix.add(at: track.time(bar: bar, beat: Double(eighth) / 2), duration: 0.12,
                        gain: isOffbeat ? 0.16 : 0.06, pan: isOffbeat ? 0.25 : -0.25,
                        voice: makeHat(seed: UInt64(bar * 8 + eighth), decay: isOffbeat ? 30 : 70))
                if isOffbeat {
                    let opening = Float(min(1, Double(bar) / 16))
                    mix.add(at: track.time(bar: bar, beat: Double(eighth) / 2), duration: track.beat / 2, gain: 0.3,
                            voice: makeSawBass(note: chord[0] - 24, cutoff: 0.03 + 0.12 * opening, decay: 6))
                }
            }
        } else {
            if bar % 2 == 0 {
                mix.add(at: track.time(bar: bar), duration: track.bar * 2, gain: 0.4,
                        voice: pad(notes: chord + chord.map { $0 + 12 }, duration: track.bar * 2, attack: 0.6))
            }
            let progress = Float(bar - 40) / 8
            mix.add(at: track.time(bar: bar), duration: track.bar, gain: 0.04 + 0.12 * progress,
                    voice: makeHat(seed: UInt64(bar), decay: 0.5))
        }
    }
    mix.master(gain: 1.2, fadeInSeconds: 0.01, fadeOutSeconds: track.bar * 4)
    return (track, mix)
}

// MARK: - Output

func write(_ mix: StereoBuffer, to url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mix.count))!
    buffer.frameLength = AVAudioFrameCount(mix.count)
    mix.left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: mix.count) }
    mix.right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: mix.count) }

    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 192_000,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
for (track, mix) in [goldenAngle(), pulseField()] {
    let url = outputDirectory.appendingPathComponent("\(track.fileName).m4a")
    try write(mix, to: url)
    print("Wrote \(url.path) — \(Int(track.seconds)) s at \(Int(track.bpm)) BPM")
}
