import CoreGraphics
import RealityKit
import ShowModel
import UIKit

/// Geometry and materials built in code, so surroundings need no authored assets.
enum ProceduralMeshes {
    private static let zoneSegments = 128
    private static let ringSegments = 192

    /// An unlit, double-sided material. Surroundings are lit only by the lasers, so flat
    /// unlit colors read as dim, darkened forms and cost almost nothing to render.
    static func material(_ hex: String) -> UnlitMaterial {
        var material = UnlitMaterial(color: color(hex))
        material.faceCulling = .none
        return material
    }

    static func color(_ hex: String) -> UIColor {
        guard let color = LaserColor(hex: hex) else { preconditionFailure("Invalid color literal \(hex)") }
        return UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }

    /// A band of a sphere between two zenith angles, in dome-local space (+y up, -z front).
    static func sphericalZone(radius: Float, zenithDegrees: ClosedRange<Float>, rings: Int = 4) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        for ring in 0...rings {
            let zenith = (zenithDegrees.lowerBound + (zenithDegrees.upperBound - zenithDegrees.lowerBound) * Float(ring) / Float(rings)) * .pi / 180
            for segment in 0...zoneSegments {
                let azimuth = Float(segment) / Float(zoneSegments) * 2 * .pi
                positions.append(radius * SIMD3(sin(zenith) * sin(azimuth), cos(zenith), -sin(zenith) * cos(azimuth)))
            }
        }
        return try gridMesh(name: "Spherical zone", positions: positions, rows: rings, columns: zoneSegments)
    }

    /// A vertical wall around the viewer whose top edge follows `height(azimuth)`.
    static func ring(radius: Float, base: Float = 0, height: (Float) -> Float) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        for row in 0...1 {
            for segment in 0...ringSegments {
                let azimuth = Float(segment) / Float(ringSegments) * 2 * .pi
                let y = row == 0 ? base : height(azimuth)
                positions.append(SIMD3(radius * sin(azimuth), y, -radius * cos(azimuth)))
            }
        }
        return try gridMesh(name: "Ring", positions: positions, rows: 1, columns: ringSegments)
    }

    /// Many axis-aligned boxes merged into one mesh (one draw call for a whole seating area).
    static func boxes(_ boxes: [(center: SIMD3<Float>, size: SIMD3<Float>)]) throws -> MeshResource {
        // Corner signs for the 8 vertices and the 12 triangles of a box.
        let corners: [SIMD3<Float>] = [
            [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
            [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1],
        ]
        let faces: [UInt32] = [
            0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
            3, 6, 2, 3, 7, 6, 0, 4, 7, 0, 7, 3, 1, 2, 6, 1, 6, 5,
        ]
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for box in boxes {
            let base = UInt32(positions.count)
            positions += corners.map { box.center + $0 * box.size / 2 }
            indices += faces.map { base + $0 }
        }
        var descriptor = MeshDescriptor(name: "Boxes")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Triangulates a (rows + 1) × (columns + 1) vertex grid.
    private static func gridMesh(name: String, positions: [SIMD3<Float>], rows: Int, columns: Int) throws -> MeshResource {
        var indices: [UInt32] = []
        let rowLength = columns + 1
        for row in 0..<rows {
            for column in 0..<columns {
                let a = UInt32(row * rowLength + column)
                let b = a + UInt32(rowLength)
                indices += [a, b, a + 1, b, b + 1, a + 1]
            }
        }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

/// Deterministic random numbers, so procedural scenery looks the same every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// An equirectangular star field with faint nebula clouds, for skies below the dome.
enum StarFieldTexture {
    private static let width = 2_048
    private static let height = 1_024
    private static let starCount = 4_000
    private static let nebulaCount = 6

    @MainActor
    static func make(seed: UInt64) throws -> TextureResource {
        var random = SeededGenerator(seed: seed)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CocoaError(.featureUnsupported) }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0.01, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let nebulaColors = [CGColor(red: 0.25, green: 0.05, blue: 0.35, alpha: 0.35), CGColor(red: 0.05, green: 0.15, blue: 0.35, alpha: 0.35)]
        for index in 0..<nebulaCount {
            let center = CGPoint(x: .random(in: 0...Double(width), using: &random), y: .random(in: 0...Double(height), using: &random))
            let radius = Double.random(in: 120...360, using: &random)
            let colors = [nebulaColors[index % nebulaColors.count], CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
            if let gradient = CGGradient(colorsSpace: context.colorSpace, colors: colors, locations: [0, 1]) {
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
        }

        for _ in 0..<starCount {
            let brightness = pow(Double.random(in: 0...1, using: &random), 4)
            let size = 0.8 + 2.2 * brightness
            let warmth = Double.random(in: 0...1, using: &random)
            context.setFillColor(CGColor(red: 0.8 + 0.2 * warmth, green: 0.85, blue: 1 - 0.2 * warmth, alpha: 0.25 + 0.75 * brightness))
            let x = Double.random(in: 0...Double(width), using: &random)
            let y = Double.random(in: 0...Double(height), using: &random)
            context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }

        guard let image = context.makeImage() else { throw CocoaError(.featureUnsupported) }
        return try TextureResource(image: image, options: .init(semantic: .color))
    }
}
