import RealityKit

/// A classic planetarium: carpeted floor, rows of seats facing the tilted dome, a glowing
/// cove strip around the spring line and the star projector out front.
enum PlanetariumSurrounding {
    private enum Colors {
        static let floor = "#08080D"
        /// Alternating row shades, so rows read as rows under flat unlit shading.
        static let seatRows = ["#2B0B12", "#1C070C"]
        static let cove = "#13264D"
        static let wall = "#06060A"
        static let projector = "#15151C"
    }

    private enum Seating {
        /// Generous spacing leaves room for the controls console in front of the viewer.
        static let rowSpacing: Float = 1.35
        /// Rows in front of (negative) and behind (positive) the viewer's row.
        static let rows = -5...3
        static let seatPitch: Float = 0.62
        static let seatsPerSide = 9
        /// Seats this close to the projector are left out to give it room.
        static let projectorClearance: Float = 1
        static let cushion = SIMD3<Float>(0.54, 0.1, 0.5)
        static let cushionHeight: Float = 0.42
        /// Low, reclined-style backs that stay below a seated viewer's eye line.
        static let backrest = SIMD3<Float>(0.54, 0.5, 0.08)
        static let backrestHeight: Float = 0.7
    }

    /// Zenith angles of the cove light strip and the wall below the dome's edge.
    private static let coveZenithDegrees: ClosedRange<Float> = 84...88
    private static let coveInset: Float = 0.995
    private static let wallZenithDegrees: ClosedRange<Float> = 90...130
    private static let projectorRadius: Float = 0.32
    private static let pedestalRadius: Float = 0.12

    @MainActor
    static func make(dome: DomeFrame, projectorPosition: SIMD3<Float>) throws -> Entity {
        let root = Entity()

        let floor = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: dome.radius), materials: [ProceduralMeshes.material(Colors.floor)])
        floor.position.y = -0.01
        root.addChild(floor)

        for (parity, color) in Colors.seatRows.enumerated() {
            let rows = Seating.rows.filter { abs($0) % Colors.seatRows.count == parity }
            root.addChild(ModelEntity(mesh: try seats(inRows: rows, avoiding: projectorPosition), materials: [ProceduralMeshes.material(color)]))
        }

        let domeAnchor = dome.makeAnchor()
        let cove = try ProceduralMeshes.sphericalZone(radius: dome.radius * coveInset, zenithDegrees: coveZenithDegrees)
        domeAnchor.addChild(ModelEntity(mesh: cove, materials: [ProceduralMeshes.material(Colors.cove)]))
        let wall = try ProceduralMeshes.sphericalZone(radius: dome.radius, zenithDegrees: wallZenithDegrees)
        domeAnchor.addChild(ModelEntity(mesh: wall, materials: [ProceduralMeshes.material(Colors.wall)]))
        root.addChild(domeAnchor)

        let projectorMaterial = ProceduralMeshes.material(Colors.projector)
        let projector = ModelEntity(mesh: .generateSphere(radius: projectorRadius), materials: [projectorMaterial])
        projector.position = projectorPosition
        root.addChild(projector)
        let pedestal = ModelEntity(mesh: .generateCylinder(height: projectorPosition.y, radius: pedestalRadius), materials: [projectorMaterial])
        pedestal.position = SIMD3(projectorPosition.x, projectorPosition.y / 2, projectorPosition.z)
        root.addChild(pedestal)

        return root
    }

    @MainActor
    private static func seats(inRows rows: [Int], avoiding projectorPosition: SIMD3<Float>) throws -> MeshResource {
        var boxes: [(center: SIMD3<Float>, size: SIMD3<Float>)] = []
        for row in rows {
            let z = Float(row) * Seating.rowSpacing
            for column in -Seating.seatsPerSide...Seating.seatsPerSide {
                // The viewer's own seat.
                if row == 0 && column == 0 { continue }
                let x = Float(column) * Seating.seatPitch
                if simd_distance(SIMD2(x, z), SIMD2(projectorPosition.x, projectorPosition.z)) < Seating.projectorClearance { continue }
                boxes.append((SIMD3(x, Seating.cushionHeight, z), Seating.cushion))
                // Backrests sit behind the cushion; everyone faces the front (-z).
                let backrestZ = z + (Seating.cushion.z + Seating.backrest.z) / 2
                boxes.append((SIMD3(x, Seating.backrestHeight, backrestZ), Seating.backrest))
            }
        }
        return try ProceduralMeshes.boxes(boxes)
    }
}
