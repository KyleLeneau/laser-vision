import LaserShaderTypes
import Metal
import RealityKit

/// Volumetric beams from the projector to the current pattern's points. Geometry and the
/// per-beam color/profile texture are both rewritten on the GPU every frame.
@MainActor
final class BeamRenderer {
    let beamCount: Int
    let entity: ModelEntity

    private let pipelines: LaserPipelines
    private let mesh: LowLevelMesh
    private let texture: LowLevelTexture

    init(pipelines: LaserPipelines, beamCount: Int, domeRadius: Float) throws {
        self.pipelines = pipelines
        self.beamCount = beamCount

        let vertexCount = beamCount * Int(LASER_BEAM_VERTEX_COUNT)
        let indexCount = beamCount * Int(LASER_BEAM_INDEX_COUNT)
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: vertexCount,
            vertexAttributes: [
                .init(semantic: .position, format: .float3, offset: MemoryLayout<LaserBeamVertex>.offset(of: \.position)!),
                .init(semantic: .uv0, format: .float2, offset: MemoryLayout<LaserBeamVertex>.offset(of: \.uv)!),
            ],
            vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<LaserBeamVertex>.stride)],
            indexCapacity: indexCount,
            indexType: .uint32
        )
        mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableIndices { buffer in
            let indices = buffer.bindMemory(to: UInt32.self)
            // Two quads per beam (vertices 0–3 and 4–7), each split into two triangles.
            let quadIndices: [UInt32] = [0, 1, 2, 2, 1, 3]
            for beam in 0..<beamCount {
                for quad in 0..<2 {
                    for (offset, index) in quadIndices.enumerated() {
                        let base = UInt32(beam * Int(LASER_BEAM_VERTEX_COUNT) + quad * 4)
                        indices[beam * Int(LASER_BEAM_INDEX_COUNT) + quad * quadIndices.count + offset] = base + index
                    }
                }
            }
        }
        let bounds = BoundingBox(min: SIMD3(repeating: -domeRadius), max: SIMD3(repeating: domeRadius))
        mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: indexCount, topology: .triangle, bounds: bounds)])

        texture = try LowLevelTexture(descriptor: .init(
            pixelFormat: .rgba16Float,
            width: beamCount,
            height: Int(LASER_BEAM_PROFILE_ROWS),
            textureUsage: [.shaderRead, .shaderWrite]
        ))

        var material = UnlitMaterial()
        material.color = .init(texture: .init(try TextureResource(from: texture)))
        // Transparent blending applies the texture alpha (the beam cross-section × brightness).
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.writesDepth = false
        material.faceCulling = .none
        entity = ModelEntity(mesh: try MeshResource(from: mesh), materials: [material])
        entity.name = "Laser beams"
    }

    func encode(into commandBuffer: any MTLCommandBuffer, segments: any MTLBuffer, uniforms: LaserFrameUniforms) {
        var uniforms = uniforms
        let vertices = mesh.replace(bufferIndex: 0, using: commandBuffer)
        let beamTexture = texture.replace(using: commandBuffer)
        guard let compute = commandBuffer.makeComputeCommandEncoder() else { return }
        compute.label = "Update laser beams"
        compute.setComputePipelineState(pipelines.updateBeams)
        compute.setBuffer(vertices, offset: 0, index: 0)
        compute.setBuffer(segments, offset: 0, index: 1)
        compute.setBytes(&uniforms, length: MemoryLayout<LaserFrameUniforms>.stride, index: 2)
        compute.setTexture(beamTexture, index: 0)
        compute.dispatchThreads(
            MTLSize(width: beamCount, height: 1, depth: 1),
            threadsPerThreadgroup: LaserPipelines.linearThreadgroup(for: pipelines.updateBeams)
        )
        compute.endEncoding()
    }
}
