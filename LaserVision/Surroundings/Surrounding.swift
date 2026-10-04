import Foundation
import LaserRendering
import RealityKit
import ShowModel

/// Where the dome sits relative to the viewer. The immersive space's origin is the floor
/// beneath the viewer, who sits facing -z.
struct DomeFrame {
    /// Height of the dome's center: roughly a seated viewer's eye level.
    static let centerHeight: Float = 1.2

    let radius: Float
    /// How far the dome's zenith leans toward the front, like a modern tilted planetarium dome,
    /// so the main action sits comfortably above the horizon.
    let tiltDegrees: Float

    var center: SIMD3<Float> { SIMD3(0, Self.centerHeight, 0) }

    var orientation: simd_quatf {
        simd_quatf(angle: -tiltDegrees * .pi / 180, axis: SIMD3(1, 0, 0))
    }

    /// Converts a point in the immersive space into the dome's local frame.
    func domeLocal(fromWorld point: SIMD3<Float>) -> SIMD3<Float> {
        orientation.inverse.act(point - center)
    }

    /// An entity aligned with the dome; children are placed in dome-local coordinates.
    func makeAnchor() -> Entity {
        let anchor = Entity()
        anchor.position = center
        anchor.orientation = orientation
        return anchor
    }
}

/// The places a show can be watched from.
enum Surrounding: String, CaseIterable, Identifiable {
    case planetarium
    case desertObservatory
    case deepSpace

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .planetarium: "Planetarium"
        case .desertObservatory: "Desert Observatory"
        case .deepSpace: "Deep Space"
        }
    }

    var symbolName: String {
        switch self {
        case .planetarium: "building.columns.fill"
        case .desertObservatory: "mountain.2.fill"
        case .deepSpace: "sparkles"
        }
    }

    var sky: SkyStyle {
        switch self {
        case .planetarium: SkyStyle(zenith: "#04050C", horizon: "#0A0A18", starIntensity: 0.8, seamIntensity: 0.03)
        case .desertObservatory: SkyStyle(zenith: "#02030A", horizon: "#1A1430", starIntensity: 1, seamIntensity: 0)
        case .deepSpace: SkyStyle(zenith: "#000002", horizon: "#050314", starIntensity: 1, seamIntensity: 0)
        }
    }

    var domeTiltDegrees: Float {
        switch self {
        case .planetarium, .deepSpace: 25
        // Open sky: a strong tilt would drop the horizon behind the mountains.
        case .desertObservatory: 8
        }
    }

    /// Where the laser projector stands, in immersive-space meters.
    var projectorPosition: SIMD3<Float> {
        switch self {
        case .planetarium: SIMD3(0, 0.8, -3.2)
        case .desertObservatory: SIMD3(0, 0.3, -7)
        // Far enough ahead and below that beams to the back of the dome clear the viewer.
        case .deepSpace: SIMD3(0, -4, -3)
        }
    }

    func makeDomeFrame(radius: Float) -> DomeFrame {
        DomeFrame(radius: radius, tiltDegrees: domeTiltDegrees)
    }

    /// Builds the scenery around the dome (seats, ground, horizon…).
    func makeScenery(dome: DomeFrame) throws -> Entity {
        let scenery: Entity = switch self {
        case .planetarium: try PlanetariumSurrounding.make(dome: dome, projectorPosition: projectorPosition)
        case .desertObservatory: try DesertObservatorySurrounding.make(dome: dome, projectorPosition: projectorPosition)
        case .deepSpace: try DeepSpaceSurrounding.make(dome: dome, projectorPosition: projectorPosition)
        }
        scenery.name = rawValue
        return scenery
    }
}

private extension SkyStyle {
    init(zenith: String, horizon: String, starIntensity: Float, seamIntensity: Float) {
        guard let zenithColor = LaserColor(hex: zenith), let horizonColor = LaserColor(hex: horizon) else {
            preconditionFailure("Invalid sky color literal")
        }
        self.init(zenithColor: zenithColor, horizonColor: horizonColor, starIntensity: starIntensity, seamIntensity: seamIntensity)
    }
}
