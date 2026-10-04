import RealityKit

/// Floating in space on a small glowing platform, with stars and nebulae all around and the
/// lasers fired up from a beacon below.
enum DeepSpaceSurrounding {
    private enum Colors {
        static let platform = "#0E1022"
        static let platformRim = "#3A5BFF"
        static let beacon = "#6A7CFF"
    }

    private static let starSphereRadius: Float = 40
    private static let starSeed: UInt64 = 42
    private static let platformRadius: Float = 1
    private static let platformThickness: Float = 0.03
    private static let rimHeight: Float = 0.04
    private static let beaconRadius: Float = 0.15

    @MainActor
    static func make(dome: DomeFrame, projectorPosition: SIMD3<Float>) throws -> Entity {
        let root = Entity()

        var stars = UnlitMaterial()
        stars.color = .init(texture: .init(try StarFieldTexture.make(seed: starSeed)))
        // Seen from inside: hide the sphere's outward-facing side.
        stars.faceCulling = .front
        root.addChild(ModelEntity(mesh: .generateSphere(radius: starSphereRadius), materials: [stars]))

        let platform = ModelEntity(
            mesh: .generateCylinder(height: platformThickness, radius: platformRadius),
            materials: [ProceduralMeshes.material(Colors.platform)]
        )
        platform.position.y = -platformThickness / 2
        root.addChild(platform)

        let rim = try ProceduralMeshes.ring(radius: platformRadius) { _ in rimHeight }
        root.addChild(ModelEntity(mesh: rim, materials: [ProceduralMeshes.material(Colors.platformRim)]))

        let beacon = ModelEntity(mesh: .generateSphere(radius: beaconRadius), materials: [ProceduralMeshes.material(Colors.beacon)])
        beacon.position = projectorPosition
        root.addChild(beacon)

        return root
    }
}
