import RealityKit
import simd

/// Swift side of the disk-space conventions documented in LaserShaderTypes.h.
enum DomeProjection {
    /// Unit direction in dome-local space for a disk point (radius 1 = horizon).
    static func direction(forDisk disk: SIMD2<Float>) -> SIMD3<Float> {
        let zenith = simd_length(disk) * .pi / 2
        let azimuth = atan2(disk.x, disk.y)
        return SIMD3(sin(zenith) * sin(azimuth), cos(zenith), -sin(zenith) * cos(azimuth))
    }

    /// Mesh texture coordinate that samples the dome image at `disk`.
    /// The image's top row is the front of the dome; RealityKit's v axis points up the image.
    static func textureCoordinate(forDisk disk: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(0.5 + 0.5 * disk.x, 0.5 + 0.5 * disk.y)
    }
}

/// The hemisphere the dome image is projected onto, seen from inside.
enum DomeMesh {
    /// Rings from zenith to horizon and segments around; dense enough that the fisheye
    /// mapping stays smooth across the large dome.
    private static let ringCount = 48
    private static let segmentCount = 128

    @MainActor
    static func make(radius: Float) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []
        let rowLength = segmentCount + 1
        positions.reserveCapacity((ringCount + 1) * rowLength)
        textureCoordinates.reserveCapacity((ringCount + 1) * rowLength)

        for ring in 0...ringCount {
            let diskRadius = Float(ring) / Float(ringCount)
            for segment in 0...segmentCount {
                let azimuth = Float(segment) / Float(segmentCount) * 2 * .pi
                let disk = diskRadius * SIMD2(sin(azimuth), cos(azimuth))
                positions.append(DomeProjection.direction(forDisk: disk) * radius)
                textureCoordinates.append(DomeProjection.textureCoordinate(forDisk: disk))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(ringCount * segmentCount * 6)
        for ring in 0..<ringCount {
            for segment in 0..<segmentCount {
                let a = UInt32(ring * rowLength + segment)
                let b = a + UInt32(rowLength)
                // Counter-clockwise as seen from the center, so the faces point inward.
                indices += [a, b, a + 1, b, b + 1, a + 1]
            }
        }

        var descriptor = MeshDescriptor(name: "Dome")
        descriptor.positions = MeshBuffer(positions)
        descriptor.textureCoordinates = MeshBuffer(textureCoordinates)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
