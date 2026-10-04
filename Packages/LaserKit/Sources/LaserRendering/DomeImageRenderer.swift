import LaserShaderTypes
import Metal

/// Encodes the GPU work that produces one domemaster image:
/// pattern segments → additive splat into an HDR history (with afterglow) → compose over the sky.
@MainActor
final class DomeImageRenderer {
    let pipelines: LaserPipelines
    let imageSize: Int
    /// Segments for both pattern slots, written by `generateSegments` and read by the splat
    /// and beam passes later in the same command buffer.
    let segmentBuffer: any MTLBuffer

    private let history: any MTLTexture
    private var historyNeedsClear = true

    init(pipelines: LaserPipelines, imageSize: Int) throws {
        self.pipelines = pipelines
        self.imageSize = imageSize

        let segmentBytes = MemoryLayout<LaserSegment>.stride * PatternBudget.maxSegmentsPerSlot * Int(LASER_PATTERN_SLOT_COUNT)
        guard let segmentBuffer = pipelines.device.makeBuffer(length: segmentBytes, options: .storageModePrivate) else {
            throw LaserRenderingError.resourceCreationFailed("segment buffer")
        }
        segmentBuffer.label = "Laser segments"
        self.segmentBuffer = segmentBuffer

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: LaserPipelines.historyPixelFormat,
            width: imageSize,
            height: imageSize,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let history = pipelines.device.makeTexture(descriptor: descriptor) else {
            throw LaserRenderingError.resourceCreationFailed("laser history texture")
        }
        history.label = "Laser history"
        self.history = history
    }

    /// Generates this frame's segments and splats them into the history.
    /// - Parameter decay: Multiplier applied to the previous history first (0 clears, 1 keeps).
    func encodeLasers(
        into commandBuffer: any MTLCommandBuffer,
        uniforms: LaserFrameUniforms,
        waveform: UnsafePointer<Float>,
        decay: Float
    ) {
        var uniforms = uniforms
        precondition(Int(uniforms.targetSize.x) == imageSize, "Uniforms target a different image size")

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.label = "Generate laser segments"
            compute.setComputePipelineState(pipelines.generateSegments)
            compute.setBuffer(segmentBuffer, offset: 0, index: 0)
            compute.setBytes(&uniforms, length: MemoryLayout<LaserFrameUniforms>.stride, index: 1)
            compute.setBytes(waveform, length: MemoryLayout<Float>.stride * Int(LASER_WAVEFORM_LENGTH), index: 2)
            compute.dispatchThreads(
                MTLSize(width: PatternBudget.maxSegmentsPerSlot * Int(LASER_PATTERN_SLOT_COUNT), height: 1, depth: 1),
                threadsPerThreadgroup: LaserPipelines.linearThreadgroup(for: pipelines.generateSegments)
            )
            compute.endEncoding()
        }

        let shouldClear = historyNeedsClear || decay <= 0
        historyNeedsClear = false
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = history
        pass.colorAttachments[0].loadAction = shouldClear ? .clear : .load
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        render.label = "Splat laser segments"

        if !shouldClear && decay < 1 {
            render.setRenderPipelineState(pipelines.decayHistory)
            render.setBlendColor(red: decay, green: decay, blue: decay, alpha: decay)
            render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        render.setRenderPipelineState(pipelines.splatSegments)
        render.setVertexBuffer(segmentBuffer, offset: 0, index: 0)
        render.setVertexBytes(&uniforms, length: MemoryLayout<LaserFrameUniforms>.stride, index: 1)
        for slot in 0..<Int(LASER_PATTERN_SLOT_COUNT) {
            let pattern = uniforms.pattern(inSlot: slot)
            guard pattern.isActive else { continue }
            render.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: Int(pattern.segmentCount),
                baseInstance: slot * PatternBudget.maxSegmentsPerSlot
            )
        }
        render.endEncoding()
    }

    /// Erases all lasers (used when no show is loaded).
    func encodeClear(into commandBuffer: any MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = history
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        historyNeedsClear = false
    }

    /// Composes the sky and the current laser history into `output` (same size as the history).
    func encodeCompose(into commandBuffer: any MTLCommandBuffer, sky: LaserSkyUniforms, output: any MTLTexture) {
        precondition(output.width == imageSize && output.height == imageSize, "Output must match the history size")
        guard let compute = commandBuffer.makeComputeCommandEncoder() else { return }
        var sky = sky
        compute.label = "Compose dome image"
        compute.setComputePipelineState(pipelines.composeDome)
        compute.setTexture(history, index: 0)
        compute.setTexture(output, index: 1)
        compute.setBytes(&sky, length: MemoryLayout<LaserSkyUniforms>.stride, index: 0)
        compute.dispatchThreads(
            MTLSize(width: imageSize, height: imageSize, depth: 1),
            threadsPerThreadgroup: LaserPipelines.imageThreadgroup(for: pipelines.composeDome)
        )
        compute.endEncoding()
    }
}
