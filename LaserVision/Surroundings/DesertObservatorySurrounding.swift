import Foundation
import RealityKit

/// Open desert at night: dark sand, a ring of mountain silhouettes and the whole sky as the
/// projection surface, with the laser rig set out on the ground in front.
enum DesertObservatorySurrounding {
    private enum Colors {
        static let ground = "#0D0A0F"
        static let mountains = "#040308"
        static let horizonBand = "#0A0812"
        static let projector = "#121014"
    }

    private static let groundInset: Float = 0.98
    private static let mountainInset: Float = 0.96
    private static let mountainHeights: ClosedRange<Float> = 0.4...2.2
    /// Layered sine waves (frequency in peaks per full turn, weight) shaping the ridge line.
    private static let ridgeWaves: [(frequency: Float, weight: Float)] = [(3, 0.5), (7, 0.3), (17, 0.15), (41, 0.05)]
    private static let ridgeSeed: UInt64 = 7
    /// Fills the gap between the ground's edge and the sky's horizon.
    private static let horizonZenithDegrees: ClosedRange<Float> = 90...115
    private static let projectorSize = SIMD3<Float>(0.5, 0.3, 0.5)

    @MainActor
    static func make(dome: DomeFrame, projectorPosition: SIMD3<Float>) throws -> Entity {
        let root = Entity()

        let ground = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: dome.radius * groundInset),
            materials: [ProceduralMeshes.material(Colors.ground)]
        )
        ground.position.y = -0.01
        root.addChild(ground)

        var random = SeededGenerator(seed: ridgeSeed)
        let phases = ridgeWaves.map { _ in Float.random(in: 0...(2 * .pi), using: &random) }
        let ridge = try ProceduralMeshes.ring(radius: dome.radius * mountainInset) { azimuth in
            ridgeHeight(at: azimuth, phases: phases)
        }
        root.addChild(ModelEntity(mesh: ridge, materials: [ProceduralMeshes.material(Colors.mountains)]))

        let domeAnchor = dome.makeAnchor()
        let horizon = try ProceduralMeshes.sphericalZone(radius: dome.radius, zenithDegrees: horizonZenithDegrees)
        domeAnchor.addChild(ModelEntity(mesh: horizon, materials: [ProceduralMeshes.material(Colors.horizonBand)]))
        root.addChild(domeAnchor)

        let projector = ModelEntity(
            mesh: .generateBox(size: projectorSize, cornerRadius: 0.04),
            materials: [ProceduralMeshes.material(Colors.projector)]
        )
        projector.position = SIMD3(projectorPosition.x, projectorSize.y / 2, projectorPosition.z)
        root.addChild(projector)

        return root
    }

    private static func ridgeHeight(at azimuth: Float, phases: [Float]) -> Float {
        var shape: Float = 0
        for (wave, phase) in zip(ridgeWaves, phases) {
            shape += wave.weight * (0.5 + 0.5 * sin(azimuth * wave.frequency + phase))
        }
        let span = mountainHeights.upperBound - mountainHeights.lowerBound
        return mountainHeights.lowerBound + span * shape
    }
}
