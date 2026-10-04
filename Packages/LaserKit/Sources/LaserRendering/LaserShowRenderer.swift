import LaserShaderTypes
import Metal
import RealityKit
import ShowAudio
import ShowModel

/// Owns the dome and beam entities and redraws them every frame from the playing show.
///
/// Add `rootEntity` to a scene; `LaserShowSystem` drives `update(deltaTime:)` once per frame.
/// While nothing changes (paused, settings untouched) no GPU work is submitted at all.
@MainActor
public final class LaserShowRenderer {
    public struct Configuration: Sendable {
        /// Dome radius in meters.
        public var domeRadius: Float = 12
        /// Width and height of the domemaster image in pixels.
        public var imageSize = 2_048
        public var beamCount = 64
        /// Seconds for the laser afterglow to fall to 1/e.
        public var afterglowSeconds = 0.07

        public static let standard = Configuration()

        public init() {}
    }

    /// Parent of the dome and beams, in dome-local space (origin at the dome center, +y up).
    public let rootEntity = Entity()
    /// The projection surface, exposed so apps can make it a gesture target.
    public let domeEntity: ModelEntity
    public let configuration: Configuration

    /// The show to draw. `nil` shows the empty sky.
    public var source: ShowFrameSource? {
        didSet { needsLaserRedraw = true }
    }

    public var sky: SkyStyle {
        didSet { needsCompose = sky != oldValue || needsCompose }
    }

    /// Multiplier on laser brightness before tone mapping.
    public var laserBrightness: Float = 1 {
        didSet { needsCompose = true }
    }

    /// Volumetric beams through haze.
    public var beamsEnabled = true {
        didSet {
            beams.entity.isEnabled = beamsEnabled
            needsLaserRedraw = true
        }
    }

    /// Where beams originate, in dome-local meters.
    public var projectorOrigin: SIMD3<Float> {
        didSet { needsLaserRedraw = true }
    }

    private static var isSystemRegistered = false

    private let pipelines: LaserPipelines
    private let domeImage: DomeImageRenderer
    private let domeTexture: LowLevelTexture
    private let beams: BeamRenderer
    private var waveform = [Float](repeating: 0, count: Int(LASER_WAVEFORM_LENGTH))
    private var lastLaserTime: Double?
    private var needsLaserRedraw = true
    private var needsCompose = true
    private var elapsedTime: Double = 0

    public init(sky: SkyStyle, projectorOrigin: SIMD3<Float>, configuration: Configuration = .standard) throws {
        Self.registerSystemIfNeeded()
        self.sky = sky
        self.projectorOrigin = projectorOrigin
        self.configuration = configuration
        pipelines = try LaserPipelines.shared()
        domeImage = try DomeImageRenderer(pipelines: pipelines, imageSize: configuration.imageSize)
        beams = try BeamRenderer(pipelines: pipelines, beamCount: configuration.beamCount, domeRadius: configuration.domeRadius)

        domeTexture = try LowLevelTexture(descriptor: .init(
            pixelFormat: .rgba16Float,
            width: configuration.imageSize,
            height: configuration.imageSize,
            textureUsage: [.shaderRead, .shaderWrite]
        ))
        var domeMaterial = UnlitMaterial()
        domeMaterial.color = .init(texture: .init(try TextureResource(from: domeTexture)))
        domeMaterial.faceCulling = .none
        domeEntity = ModelEntity(mesh: try DomeMesh.make(radius: configuration.domeRadius), materials: [domeMaterial])
        domeEntity.name = "Dome"

        rootEntity.name = "Laser show"
        rootEntity.addChild(domeEntity)
        rootEntity.addChild(beams.entity)
        rootEntity.components.set(LaserShowComponent(renderer: self))
    }

    private static func registerSystemIfNeeded() {
        guard !isSystemRegistered else { return }
        LaserShowComponent.registerComponent()
        LaserShowSystem.registerSystem()
        isSystemRegistered = true
    }

    func update(deltaTime: Double) {
        elapsedTime += deltaTime
        let laserTime = source?.clock.currentTime()
        let lasersChanged = needsLaserRedraw || laserTime != lastLaserTime
        guard lasersChanged || needsCompose,
              let commandBuffer = pipelines.commandQueue.makeCommandBuffer()
        else { return }
        commandBuffer.label = "Laser show frame"

        if lasersChanged {
            if let source, let laserTime {
                encodeLasers(source: source, time: laserTime, deltaTime: deltaTime, into: commandBuffer)
            } else {
                domeImage.encodeClear(into: commandBuffer)
            }
            lastLaserTime = laserTime
            needsLaserRedraw = false
        }

        let skyUniforms = sky.uniforms(laserBrightness: laserBrightness, time: elapsedTime, encodeSRGB: false)
        domeImage.encodeCompose(into: commandBuffer, sky: skyUniforms, output: domeTexture.replace(using: commandBuffer))
        needsCompose = false
        commandBuffer.commit()
    }

    private func encodeLasers(source: ShowFrameSource, time: Double, deltaTime: Double, into commandBuffer: any MTLCommandBuffer) {
        let uniforms = LaserFrameUniforms(
            show: source.show,
            timeline: source.evaluator.state(at: time),
            features: source.analysis.features(at: time),
            settings: DomeFrameSettings(
                imageSize: configuration.imageSize,
                domeRadius: configuration.domeRadius,
                projectorOrigin: projectorOrigin,
                beamCount: configuration.beamCount,
                beamIntensity: beamsEnabled ? 1 : 0
            )
        )
        let decay = Float(exp(-deltaTime / configuration.afterglowSeconds))

        waveform.withUnsafeMutableBufferPointer { samples in
            let pointer = samples.baseAddress!
            source.analysis.copyWaveform(at: time, into: pointer)
            domeImage.encodeLasers(into: commandBuffer, uniforms: uniforms, waveform: pointer, decay: decay)
        }
        if beamsEnabled {
            beams.encode(into: commandBuffer, segments: domeImage.segmentBuffer, uniforms: uniforms)
        }
    }
}

/// Marks the entity whose renderer `LaserShowSystem` updates each frame.
struct LaserShowComponent: Component {
    /// Weak: the renderer owns the entity, not the other way round.
    weak var renderer: LaserShowRenderer?
}

/// Drives every live `LaserShowRenderer` once per rendered frame.
struct LaserShowSystem: System {
    private static let query = EntityQuery(where: .has(LaserShowComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            entity.components[LaserShowComponent.self]?.renderer?.update(deltaTime: context.deltaTime)
        }
    }
}
