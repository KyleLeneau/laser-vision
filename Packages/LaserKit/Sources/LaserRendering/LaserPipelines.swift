import Metal

public enum LaserRenderingError: Error {
    case noMetalDevice
    case missingShaderLibrary(underlying: any Error)
    case missingShaderFunction(String)
    case resourceCreationFailed(String)
}

/// The Metal device, queue and compiled pipeline states shared by every laser renderer.
@MainActor
final class LaserPipelines {
    /// Pixel format of the HDR laser history target.
    static let historyPixelFormat = MTLPixelFormat.rgba16Float

    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    let generateSegments: any MTLComputePipelineState
    let composeDome: any MTLComputePipelineState
    let updateBeams: any MTLComputePipelineState
    /// Additive splatting of segment quads into the history target.
    let splatSegments: any MTLRenderPipelineState
    /// Multiplies the history target by the blend color (afterglow decay).
    let decayHistory: any MTLRenderPipelineState

    private static var sharedInstance: LaserPipelines?

    /// Pipelines are expensive to build; every renderer shares one set.
    static func shared() throws -> LaserPipelines {
        if let sharedInstance { return sharedInstance }
        let pipelines = try LaserPipelines()
        sharedInstance = pipelines
        return pipelines
    }

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw LaserRenderingError.noMetalDevice }
        guard let commandQueue = device.makeCommandQueue() else {
            throw LaserRenderingError.resourceCreationFailed("command queue")
        }
        self.device = device
        self.commandQueue = commandQueue

        let library: any MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .module)
        } catch {
            throw LaserRenderingError.missingShaderLibrary(underlying: error)
        }

        func function(_ name: String) throws -> any MTLFunction {
            guard let function = library.makeFunction(name: name) else {
                throw LaserRenderingError.missingShaderFunction(name)
            }
            return function
        }

        generateSegments = try device.makeComputePipelineState(function: function("generateSegments"))
        composeDome = try device.makeComputePipelineState(function: function("composeDome"))
        updateBeams = try device.makeComputePipelineState(function: function("updateBeams"))

        let splat = MTLRenderPipelineDescriptor()
        splat.label = "Splat laser segments"
        splat.vertexFunction = try function("segmentVertex")
        splat.fragmentFunction = try function("segmentFragment")
        let splatColor = splat.colorAttachments[0]!
        splatColor.pixelFormat = Self.historyPixelFormat
        splatColor.isBlendingEnabled = true
        splatColor.rgbBlendOperation = .add
        splatColor.alphaBlendOperation = .add
        splatColor.sourceRGBBlendFactor = .one
        splatColor.destinationRGBBlendFactor = .one
        splatColor.sourceAlphaBlendFactor = .one
        splatColor.destinationAlphaBlendFactor = .one
        splatSegments = try device.makeRenderPipelineState(descriptor: splat)

        let decay = MTLRenderPipelineDescriptor()
        decay.label = "Decay laser history"
        decay.vertexFunction = try function("fullscreenVertex")
        decay.fragmentFunction = try function("decayFragment")
        let decayColor = decay.colorAttachments[0]!
        decayColor.pixelFormat = Self.historyPixelFormat
        decayColor.isBlendingEnabled = true
        decayColor.sourceRGBBlendFactor = .zero
        decayColor.destinationRGBBlendFactor = .blendColor
        decayColor.sourceAlphaBlendFactor = .zero
        decayColor.destinationAlphaBlendFactor = .blendAlpha
        decayHistory = try device.makeRenderPipelineState(descriptor: decay)
    }

    /// Threadgroup size for a 1D compute dispatch.
    static func linearThreadgroup(for pipeline: any MTLComputePipelineState) -> MTLSize {
        MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1)
    }

    /// Threadgroup size for a 2D compute dispatch over an image.
    static func imageThreadgroup(for pipeline: any MTLComputePipelineState) -> MTLSize {
        let width = pipeline.threadExecutionWidth
        return MTLSize(width: width, height: pipeline.maxTotalThreadsPerThreadgroup / width, depth: 1)
    }
}
