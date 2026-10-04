import Foundation
import Testing
@testable import ShowAudio

private let sampleRate = 44_100.0

private func sine(frequency: Double, seconds: Double, amplitude: Float = 0.5) -> [Float] {
    (0..<Int(seconds * sampleRate)).map { index in
        amplitude * Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
    }
}

/// Short noise bursts every `interval` seconds over a quiet bed.
private func clicks(every interval: Double, seconds: Double) -> [Float] {
    var generator = SystemRandomNumberGenerator()
    var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
    let burstLength = Int(0.01 * sampleRate)
    var start = interval
    while start < seconds {
        let first = Int(start * sampleRate)
        for index in first..<min(first + burstLength, samples.count) {
            samples[index] = Float.random(in: -0.8...0.8, using: &generator)
        }
        start += interval
    }
    return samples
}

@Suite struct AudioAnalyzerTests {
    @Test func lowSineLandsInBass() {
        let analysis = AudioAnalyzer.analyze(monoSamples: sine(frequency: 100, seconds: 2), sampleRate: sampleRate)
        let features = analysis.features(at: 1)
        #expect(features.bass > 0.9)
        #expect(features.energy > 0.9)
        #expect(features.treble < 0.2)
    }

    @Test func highSineLandsInTreble() {
        let analysis = AudioAnalyzer.analyze(monoSamples: sine(frequency: 5_000, seconds: 2), sampleRate: sampleRate)
        let features = analysis.features(at: 1)
        #expect(features.treble > 0.9)
        #expect(features.bass < 0.2)
    }

    @Test func silenceIsSilent() {
        let analysis = AudioAnalyzer.analyze(monoSamples: [Float](repeating: 0, count: Int(sampleRate)), sampleRate: sampleRate)
        #expect(analysis.onsetTimes.isEmpty)
        #expect(analysis.features(at: 0.5) == .silent)
    }

    @Test func clicksProduceOnsets() throws {
        let analysis = AudioAnalyzer.analyze(monoSamples: clicks(every: 0.5, seconds: 4), sampleRate: sampleRate)
        let expected = stride(from: 0.5, to: 4, by: 0.5).map { $0 }
        #expect(analysis.onsetTimes.count == expected.count)
        for (detected, actual) in zip(analysis.onsetTimes, expected) {
            #expect(abs(detected - actual) < 0.03, "onset at \(detected) expected near \(actual)")
        }
        let justAfter = analysis.features(at: try #require(analysis.onsetTimes.first) + 0.01)
        let longAfter = analysis.features(at: 0.95)
        #expect(justAfter.onsetPulse > 0.8)
        #expect(longAfter.onsetPulse < 0.1)
    }

    @Test func waveformSnapshotIsNormalized() {
        let analysis = AudioAnalyzer.analyze(monoSamples: sine(frequency: 220, seconds: 1), sampleRate: sampleRate)
        var waveform = [Float](repeating: .nan, count: AudioAnalysis.waveformLength)
        waveform.withUnsafeMutableBufferPointer { analysis.copyWaveform(at: 0.5, into: $0.baseAddress!) }
        #expect(waveform.allSatisfy { $0 >= -1 && $0 <= 1 })
        #expect(waveform.contains { abs($0) > 0.1 })
    }

    @Test func emptyInputIsSafe() {
        let analysis = AudioAnalyzer.analyze(monoSamples: [], sampleRate: sampleRate)
        #expect(analysis.frameCount == 0)
        #expect(analysis.features(at: 1) == .silent)
        var waveform = [Float](repeating: .nan, count: AudioAnalysis.waveformLength)
        waveform.withUnsafeMutableBufferPointer { analysis.copyWaveform(at: 0, into: $0.baseAddress!) }
        #expect(waveform.allSatisfy { $0 == 0 })
    }
}

@Suite struct PlaybackClockTests {
    @Test func holdsWhenStopped() {
        let clock = PlaybackClock()
        clock.hold(at: 12)
        #expect(!clock.isRunning)
        #expect(clock.currentTime(hostSeconds: 1_000) == 12)
    }

    @Test func advancesFromAnchor() {
        let clock = PlaybackClock()
        clock.run(from: 5, heardAtHostSeconds: 100)
        #expect(clock.currentTime(hostSeconds: 99) == 5, "holds before audio is heard")
        #expect(clock.currentTime(hostSeconds: 102.5) == 7.5)
    }
}
