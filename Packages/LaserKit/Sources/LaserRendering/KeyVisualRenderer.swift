import CoreGraphics
import Foundation
import LaserShaderTypes
import Metal
import ShowAudio
import ShowModel

/// Renders a still of a show's signature pattern for its library card, using the same GPU
/// kernels as the live dome so the card is an honest preview of the show.
@MainActor
public final class KeyVisualRenderer {
    public static let defaultImageSize = 512

    /// The backdrop behind card art: a deep night-sky gradient with a few stars.
    private static let cardSky = SkyStyle(
        zenithColor: LaserColor(hex: "#0B0E24")!,
        horizonColor: LaserColor(hex: "#1B1033")!,
        starIntensity: 0.5,
        seamIntensity: 0
    )
    /// A representative musical moment: lively audio, a quarter of the way into a beat.
    private static let representativeFeatures = AudioFeatures(energy: 0.8, bass: 0.6, mid: 0.5, treble: 0.4, onsetPulse: 0.6)
    private static let representativeBeat = 6.25
    /// Cycles of the synthetic waveform drawn by waveform-ring signatures.
    private static let representativeWaveformCycles: Float = 3
    private static let representativeWaveformAmplitude: Float = 0.6

    private let pipelines: LaserPipelines
    private var renderers: [Int: DomeImageRenderer] = [:]

    public init() throws {
        pipelines = try LaserPipelines.shared()
    }

    public func render(show: ShowDefinition, imageSize: Int = KeyVisualRenderer.defaultImageSize) throws -> CGImage {
        let renderer = try renderer(for: imageSize)
        let output = try makeOutputTexture(size: imageSize)

        let time = show.tempo.seconds(atBeat: Self.representativeBeat)
        let timeline = TimelineEvaluator(show: show).state(at: time)
        let uniforms = LaserFrameUniforms(
            outgoing: .disabled,
            current: LaserPatternUniforms(settings: show.signature, palette: show.palette, weight: 1),
            timeline: timeline,
            features: Self.representativeFeatures,
            settings: DomeFrameSettings(imageSize: imageSize, domeRadius: 1, projectorOrigin: .zero, beamCount: 0, beamIntensity: 0)
        )

        let waveform = (0..<Int(LASER_WAVEFORM_LENGTH)).map { index in
            let phase = Float(index) / Float(LASER_WAVEFORM_LENGTH) * 2 * .pi * Self.representativeWaveformCycles
            return Self.representativeWaveformAmplitude * sin(phase)
        }

        guard let commandBuffer = pipelines.commandQueue.makeCommandBuffer() else {
            throw LaserRenderingError.resourceCreationFailed("command buffer")
        }
        commandBuffer.label = "Key visual"
        waveform.withUnsafeBufferPointer { samples in
            renderer.encodeLasers(into: commandBuffer, uniforms: uniforms, waveform: samples.baseAddress!, decay: 0)
        }
        let sky = Self.cardSky.uniforms(laserBrightness: 1, time: time, encodeSRGB: true)
        renderer.encodeCompose(into: commandBuffer, sky: sky, output: output)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return try makeImage(from: output)
    }

    private func renderer(for size: Int) throws -> DomeImageRenderer {
        if let renderer = renderers[size] { return renderer }
        let renderer = try DomeImageRenderer(pipelines: pipelines, imageSize: size)
        renderers[size] = renderer
        return renderer
    }

    private func makeOutputTexture(size: Int) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = [.shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = pipelines.device.makeTexture(descriptor: descriptor) else {
            throw LaserRenderingError.resourceCreationFailed("key visual texture")
        }
        return texture
    }

    private func makeImage(from texture: any MTLTexture) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = texture.width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: texture.width,
                  height: texture.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8 * bytesPerPixel,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { throw LaserRenderingError.resourceCreationFailed("key visual image") }
        return image
    }
}
