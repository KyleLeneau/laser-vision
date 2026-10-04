import LaserShaderTypes
import ShowAudio
import ShowModel
import simd

/// How many segments (and repeated elements) each pattern kind draws. The GPU kernels read
/// these counts from the uniforms, so this is the single source of truth for pattern density.
enum PatternBudget {
    static let maxSegmentsPerSlot = 2048

    private static let phyllotaxisDots = 300...1_800
    private static let lissajousSegments = 720
    private static let tunnelRings = 4...16
    private static let tunnelSegmentsPerRing = 64
    private static let spirographSegments = 1_440
    private static let burstSpokesPerFold = 2...12
    private static let burstMaxSpokes = 256
    private static let waveformLayers = 2
    private static let waveformSegmentsPerLayer = 256
    private static let fanBeamsPerFan = 4...16

    static func layout(for settings: PatternSettings) -> (segmentCount: Int, elementCount: Int) {
        let parameters = settings.parameters
        let density = min(max(parameters.density, 0), 1)
        let symmetry = max(parameters.symmetry, 1)
        func lerp(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int((Double(range.upperBound - range.lowerBound) * density).rounded())
        }

        let layout: (Int, Int)
        switch settings.kind {
        case .phyllotaxis:
            layout = (lerp(phyllotaxisDots), 1)
        case .lissajous:
            layout = (lissajousSegments, 1)
        case .tunnel:
            let rings = lerp(tunnelRings)
            layout = (rings * tunnelSegmentsPerRing, rings)
        case .spirograph:
            layout = (spirographSegments, 1)
        case .radialBurst:
            let spokes = min(symmetry * lerp(burstSpokesPerFold), burstMaxSpokes)
            layout = (spokes, spokes)
        case .waveformRing:
            layout = (waveformLayers * waveformSegmentsPerLayer, waveformLayers)
        case .beamFan:
            layout = (symmetry * lerp(fanBeamsPerFan), symmetry)
        }
        return (min(layout.0, maxSegmentsPerSlot), layout.1)
    }
}

extension PatternKind {
    /// Kernel selector; see the LASER_PATTERN_* constants in LaserShaderTypes.h.
    var shaderKind: UInt32 {
        let kind = switch self {
        case .phyllotaxis: LASER_PATTERN_PHYLLOTAXIS
        case .lissajous: LASER_PATTERN_LISSAJOUS
        case .tunnel: LASER_PATTERN_TUNNEL
        case .spirograph: LASER_PATTERN_SPIROGRAPH
        case .radialBurst: LASER_PATTERN_RADIAL_BURST
        case .waveformRing: LASER_PATTERN_WAVEFORM_RING
        case .beamFan: LASER_PATTERN_BEAM_FAN
        }
        return UInt32(kind)
    }

    /// How strongly the pattern lights the volumetric beams. Fans exist for the beams;
    /// other patterns cast fainter beams so the dome imagery stays the focus.
    var beamGain: Float {
        self == .beamFan ? 1 : 0.3
    }
}

extension LaserColor {
    /// The color with the sRGB transfer curve removed, for additive blending in linear light.
    var linear: SIMD3<Float> {
        func decode(_ channel: Float) -> Float {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return SIMD3(decode(red), decode(green), decode(blue))
    }
}

extension LaserPatternUniforms {
    init(settings: PatternSettings, palette: ColorPalette, weight: Double) {
        let parameters = settings.parameters
        let layout = PatternBudget.layout(for: settings)
        self.init()
        primaryColor = palette.color(at: parameters.primaryColor).linear
        secondaryColor = palette.color(at: parameters.secondaryColor).linear
        kind = settings.kind.shaderKind
        segmentCount = UInt32(layout.segmentCount)
        elementCount = UInt32(layout.elementCount)
        symmetry = UInt32(max(parameters.symmetry, 1))
        self.weight = Float(weight)
        speed = Float(parameters.speed)
        scale = Float(parameters.scale)
        variation = Float(parameters.variation)
        audioReactivity = Float(parameters.audioReactivity)
        beamGain = settings.kind.beamGain
    }

    /// A slot that draws nothing.
    static let disabled = LaserPatternUniforms()

    var isActive: Bool { segmentCount > 0 && weight > 0 }
}

/// Dome geometry and beam settings that stay fixed for a renderer.
struct DomeFrameSettings {
    var imageSize: Int
    var domeRadius: Float
    var projectorOrigin: SIMD3<Float>
    var beamCount: Int
    var beamIntensity: Float
}

extension LaserFrameUniforms {
    init(show: ShowDefinition, timeline: TimelineState, features: AudioFeatures, settings: DomeFrameSettings) {
        let current = LaserPatternUniforms(
            settings: show.cues[timeline.currentCueIndex].pattern,
            palette: show.palette,
            weight: timeline.transitionProgress
        )
        let outgoing = timeline.outgoingCueIndex.map {
            LaserPatternUniforms(settings: show.cues[$0].pattern, palette: show.palette, weight: 1 - timeline.transitionProgress)
        } ?? .disabled

        self.init(outgoing: outgoing, current: current, timeline: timeline, features: features, settings: settings)
    }

    init(
        outgoing: LaserPatternUniforms,
        current: LaserPatternUniforms,
        timeline: TimelineState,
        features: AudioFeatures,
        settings: DomeFrameSettings
    ) {
        self.init()
        patterns = (outgoing, current)
        projectorOrigin = settings.projectorOrigin
        targetSize = SIMD2(Float(settings.imageSize), Float(settings.imageSize))
        beat = Float(timeline.beat)
        beatPhase = Float(timeline.beatPhase)
        energy = features.energy
        bass = features.bass
        mid = features.mid
        treble = features.treble
        onsetPulse = features.onsetPulse
        domeRadius = settings.domeRadius
        beamIntensity = settings.beamIntensity
        maxSegmentsPerSlot = UInt32(PatternBudget.maxSegmentsPerSlot)
        beamCount = UInt32(settings.beamCount)
    }

    func pattern(inSlot slot: Int) -> LaserPatternUniforms {
        slot == Int(LASER_OUTGOING_SLOT) ? patterns.0 : patterns.1
    }
}
