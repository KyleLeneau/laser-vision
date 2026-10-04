import Accelerate
import AVFoundation

/// Computes an `AudioAnalysis` for a whole track ahead of playback: FFT band energies,
/// RMS energy, spectral-flux onsets and waveform snapshots on a fixed hop grid.
public enum AudioAnalyzer {
    public struct Configuration: Sendable {
        /// FFT window length in samples (power of two).
        public var fftSize = 1024
        /// Samples between successive analysis frames.
        public var hopSize = 512
        public var bassBand: ClosedRange<Double> = 20...250
        public var midBand: ClosedRange<Double> = 250...2_000
        public var trebleBand: ClosedRange<Double> = 2_000...10_000
        /// Auto-gain: seconds for the running peak to decay by half. Lets quiet passages still react.
        public var autoGainHalfLifeSeconds = 6.0
        /// Auto-gain never boosts beyond this fraction of the track's loudest moment (keeps silence dark).
        public var autoGainFloorFraction: Float = 0.1
        /// Each band's auto-gain floor is also at least this fraction of the loudest band, so a band
        /// carrying only spectral leakage is not amplified to full scale.
        public var autoGainCrossBandFloorFraction: Float = 0.01
        /// Smoothing time constants for rising and falling feature values.
        public var attackSeconds = 0.01
        public var releaseSeconds = 0.15
        /// Onset detection: flux must exceed the local mean by this ratio…
        public var onsetThresholdRatio: Float = 1.5
        /// …over a window of this many seconds either side…
        public var onsetWindowSeconds = 0.5
        /// …and be above this fraction of the track's strongest flux.
        public var onsetFloorFraction: Float = 0.05
        /// Minimum spacing between onsets.
        public var onsetMinimumIntervalSeconds = 0.1
        /// Log compression applied to magnitudes before computing spectral flux.
        public var fluxCompression: Float = 100
        /// Waveform snapshots are scaled so a signal at its running-peak RMS spans ±1/this.
        public var waveformCrestFactor: Float = 3

        public static let standard = Configuration()

        public init() {}
    }

    public enum AnalysisError: Error {
        case unreadableFormat
    }

    /// Frames read from disk per chunk while streaming a file through the analyzer.
    private static let readChunkFrames: AVAudioFrameCount = 65_536

    /// Decodes and analyzes an audio file off the calling actor.
    @concurrent
    public static func analyze(fileAt url: URL, configuration: Configuration = .standard) async throws -> AudioAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: readChunkFrames)
        else { throw AnalysisError.unreadableFormat }

        var extractor = RawFeatureExtractor(sampleRate: format.sampleRate, configuration: configuration)
        var mono = [Float](repeating: 0, count: Int(readChunkFrames))
        let channelCount = Int(format.channelCount)
        let channelScale = 1 / Float(channelCount)

        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0, let channels = buffer.floatChannelData else { break }
            mono.withUnsafeMutableBufferPointer { output in
                vDSP.fill(&output, with: 0)
                for channel in 0..<channelCount {
                    let input = UnsafeBufferPointer(start: channels[channel], count: frameCount)
                    vDSP_vadd(input.baseAddress!, 1, output.baseAddress!, 1, output.baseAddress!, 1, vDSP_Length(frameCount))
                }
                vDSP_vsmul(output.baseAddress!, 1, [channelScale], output.baseAddress!, 1, vDSP_Length(frameCount))
            }
            mono.withUnsafeBufferPointer { extractor.append(UnsafeBufferPointer(rebasing: $0[0..<frameCount])) }
        }
        return extractor.finish()
    }

    /// Analyzes mono samples already in memory.
    public static func analyze(monoSamples: [Float], sampleRate: Double, configuration: Configuration = .standard) -> AudioAnalysis {
        var extractor = RawFeatureExtractor(sampleRate: sampleRate, configuration: configuration)
        monoSamples.withUnsafeBufferPointer { extractor.append($0) }
        return extractor.finish()
    }
}

// MARK: - Raw extraction

/// Streams mono samples through windowed FFTs and records un-normalized per-hop measurements.
private struct RawFeatureExtractor {
    let sampleRate: Double
    let configuration: AudioAnalyzer.Configuration

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let bassBins: Range<Int>
    private let midBins: Range<Int>
    private let trebleBins: Range<Int>
    private let samplesPerWaveformPoint: Int

    private var pending: [Float] = []
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]
    private var logMagnitude: [Float]
    private var previousLogMagnitude: [Float]

    private var rms: [Float] = []
    private var bass: [Float] = []
    private var mid: [Float] = []
    private var treble: [Float] = []
    private var flux: [Float] = []
    private var waveforms: [Float] = []

    init(sampleRate: Double, configuration: AudioAnalyzer.Configuration) {
        self.sampleRate = sampleRate
        self.configuration = configuration
        let size = configuration.fftSize
        precondition(size.nonzeroBitCount == 1, "FFT size must be a power of two")
        precondition(size % AudioAnalysis.waveformLength == 0, "FFT size must be a multiple of the waveform length")

        fft = vDSP.FFT(log2n: vDSP_Length(size.trailingZeroBitCount), radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        power = [Float](repeating: 0, count: size / 2)
        logMagnitude = [Float](repeating: 0, count: size / 2)
        previousLogMagnitude = [Float](repeating: 0, count: size / 2)
        samplesPerWaveformPoint = size / AudioAnalysis.waveformLength

        let binWidth = sampleRate / Double(size)
        func bins(_ band: ClosedRange<Double>) -> Range<Int> {
            let lower = max(1, Int((band.lowerBound / binWidth).rounded()))
            let upper = min(size / 2, max(lower + 1, Int((band.upperBound / binWidth).rounded())))
            return lower..<upper
        }
        bassBins = bins(configuration.bassBand)
        midBins = bins(configuration.midBand)
        trebleBins = bins(configuration.trebleBand)
    }

    mutating func append(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        var start = 0
        while pending.count - start >= configuration.fftSize {
            analyzeWindow(startingAt: start)
            start += configuration.hopSize
        }
        pending.removeFirst(start)
    }

    private mutating func analyzeWindow(startingAt start: Int) {
        let size = configuration.fftSize
        let frame = pending[start..<(start + size)]

        rms.append(vDSP.rootMeanSquare(frame))

        for point in 0..<AudioAnalysis.waveformLength {
            let first = start + point * samplesPerWaveformPoint
            waveforms.append(vDSP.mean(pending[first..<(first + samplesPerWaveformPoint)]))
        }

        vDSP.multiply(frame, window, result: &windowed)
        computePowerSpectrum()

        func bandAmplitude(_ bins: Range<Int>) -> Float {
            (vDSP.mean(power[bins])).squareRoot()
        }
        bass.append(bandAmplitude(bassBins))
        mid.append(bandAmplitude(midBins))
        treble.append(bandAmplitude(trebleBins))

        // Spectral flux: summed positive change in log-compressed magnitude.
        for bin in power.indices {
            logMagnitude[bin] = log1p(configuration.fluxCompression * power[bin].squareRoot())
        }
        var frameFlux: Float = 0
        for bin in logMagnitude.indices {
            frameFlux += max(0, logMagnitude[bin] - previousLogMagnitude[bin])
        }
        flux.append(rms.count == 1 ? 0 : frameFlux)
        swap(&logMagnitude, &previousLogMagnitude)
    }

    private mutating func computePowerSpectrum() {
        let halfSize = configuration.fftSize / 2
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBytes { bytes in
                    vDSP_ctoz(bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(halfSize))
                }
                fft.forward(input: split, output: &split)
                power.withUnsafeMutableBufferPointer { powerPointer in
                    vDSP_zvmags(&split, 1, powerPointer.baseAddress!, 1, vDSP_Length(halfSize))
                }
            }
        }
        // Bin 0 packs DC and Nyquist together; neither is musically useful.
        power[0] = 0
    }

    // MARK: Post-processing

    func finish() -> AudioAnalysis {
        let hopDuration = Double(configuration.hopSize) / sampleRate
        let firstFrameTime = Double(configuration.fftSize / 2) / sampleRate

        let (energy, energyPeaks) = autoGain(rms, hopDuration: hopDuration)
        let loudestBand = [bass, mid, treble].compactMap { $0.max() }.max() ?? 0
        let bandFloor = loudestBand * configuration.autoGainCrossBandFloorFraction
        func process(_ values: [Float]) -> [Float] {
            smooth(autoGain(values, hopDuration: hopDuration, minimumFloor: bandFloor).normalized, hopDuration: hopDuration)
        }
        let smoothedEnergy = smooth(energy, hopDuration: hopDuration)
        let smoothedBass = process(bass)
        let smoothedMid = process(mid)
        let smoothedTreble = process(treble)
        let frames = rms.indices.map { index in
            AudioAnalysis.Frame(
                energy: smoothedEnergy[index],
                bass: smoothedBass[index],
                mid: smoothedMid[index],
                treble: smoothedTreble[index]
            )
        }

        var scaledWaveforms = waveforms
        for frameIndex in energyPeaks.indices {
            let scale = 1 / (energyPeaks[frameIndex] * configuration.waveformCrestFactor)
            let range = (frameIndex * AudioAnalysis.waveformLength)..<((frameIndex + 1) * AudioAnalysis.waveformLength)
            for sample in range {
                scaledWaveforms[sample] = min(max(scaledWaveforms[sample] * scale, -1), 1)
            }
        }

        let onsetTimes = detectOnsets(hopDuration: hopDuration).map { firstFrameTime + Double($0) * hopDuration }

        return AudioAnalysis(
            hopDuration: hopDuration,
            firstFrameTime: firstFrameTime,
            frames: frames,
            waveforms: scaledWaveforms,
            onsetTimes: onsetTimes
        )
    }

    /// Divides by a slowly decaying running peak so every section of the track uses the full 0…1 range.
    /// Returns the normalized values and the divisor used for each frame (never zero).
    private func autoGain(_ values: [Float], hopDuration: Double, minimumFloor: Float = 0) -> (normalized: [Float], peaks: [Float]) {
        let decay = Float(pow(0.5, hopDuration / configuration.autoGainHalfLifeSeconds))
        let floor = max((values.max() ?? 0) * configuration.autoGainFloorFraction, minimumFloor, .leastNormalMagnitude)
        var peak = floor
        var normalized = [Float]()
        var peaks = [Float]()
        normalized.reserveCapacity(values.count)
        peaks.reserveCapacity(values.count)
        for value in values {
            peak = max(value, peak * decay, floor)
            peaks.append(peak)
            normalized.append(min(value / peak, 1))
        }
        return (normalized, peaks)
    }

    /// One-pole smoothing with separate attack and release time constants.
    private func smooth(_ values: [Float], hopDuration: Double) -> [Float] {
        let attack = Float(1 - exp(-hopDuration / configuration.attackSeconds))
        let release = Float(1 - exp(-hopDuration / configuration.releaseSeconds))
        var current: Float = 0
        return values.map { value in
            current += (value - current) * (value > current ? attack : release)
            return current
        }
    }

    /// Frame indices whose flux is a local peak above an adaptive (centered moving mean) threshold.
    private func detectOnsets(hopDuration: Double) -> [Int] {
        guard flux.count > 2, let maxFlux = flux.max(), maxFlux > 0 else { return [] }
        let radius = max(1, Int(configuration.onsetWindowSeconds / hopDuration))
        let minimumGap = max(1, Int((configuration.onsetMinimumIntervalSeconds / hopDuration).rounded(.up)))
        let floor = maxFlux * configuration.onsetFloorFraction

        var prefix = [Float](repeating: 0, count: flux.count + 1)
        for index in flux.indices { prefix[index + 1] = prefix[index] + flux[index] }

        var onsets: [Int] = []
        for index in 1..<(flux.count - 1) {
            let value = flux[index]
            guard value > floor, value >= flux[index - 1], value > flux[index + 1] else { continue }
            let lower = max(0, index - radius)
            let upper = min(flux.count, index + radius + 1)
            let localMean = (prefix[upper] - prefix[lower]) / Float(upper - lower)
            guard value > localMean * configuration.onsetThresholdRatio else { continue }
            if let last = onsets.last, index - last < minimumGap { continue }
            onsets.append(index)
        }
        return onsets
    }
}
