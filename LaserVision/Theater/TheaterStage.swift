import LaserRendering
import RealityKit

/// Marks the dome as the surface whose taps toggle the controls.
struct DomeTapTargetComponent: Component {}

/// Assembles the immersive scene: the laser dome (via `LaserShowRenderer`) inside the
/// chosen surrounding, and keeps both in sync with the app's settings.
@MainActor
final class TheaterStage {
    /// Seconds for one surrounding to fade into the next.
    private static let crossFadeSeconds = 0.8
    /// Registers the marker component once, before any stage uses it.
    private static let registerComponents: Void = DomeTapTargetComponent.registerComponent()

    let root = Entity()
    let renderer: LaserShowRenderer

    private let domeAnchor = Entity()
    private var scenery: Entity?
    private var surrounding: Surrounding?
    private var sourceSessionID: ShowSession.ID?

    init(surrounding: Surrounding) throws {
        _ = Self.registerComponents
        renderer = try LaserShowRenderer(sky: surrounding.sky, projectorOrigin: .zero)
        root.name = "Theater"
        domeAnchor.addChild(renderer.rootEntity)
        root.addChild(domeAnchor)
        show(surrounding, animated: false)
    }

    /// Lets the viewer tap anywhere on the dome (used to toggle the controls).
    func makeDomeTappable() async throws {
        guard let mesh = renderer.domeEntity.model?.mesh else { return }
        let shape = try await ShapeResource.generateStaticMesh(from: mesh)
        renderer.domeEntity.components.set(CollisionComponent(shapes: [shape], isStatic: true))
        renderer.domeEntity.components.set(InputTargetComponent())
        renderer.domeEntity.components.set(DomeTapTargetComponent())
    }

    func apply(surrounding: Surrounding, laserBrightness: Float, hazeEnabled: Bool, viewingHeight: Float, session: ShowSession?) {
        if surrounding != self.surrounding {
            show(surrounding, animated: true)
        }
        // Raising the viewer is the same as lowering the whole theater around them.
        root.position.y = -viewingHeight
        renderer.laserBrightness = laserBrightness
        if renderer.beamsEnabled != hazeEnabled {
            renderer.beamsEnabled = hazeEnabled
        }

        // Only hand the renderer a new source when the show changes or finishes loading.
        let source = session?.frameSource
        let readySessionID = source == nil ? nil : session?.id
        if readySessionID != sourceSessionID {
            renderer.source = source
            sourceSessionID = readySessionID
        }
    }

    private func show(_ surrounding: Surrounding, animated: Bool) {
        self.surrounding = surrounding
        let dome = surrounding.makeDomeFrame(radius: renderer.configuration.domeRadius)
        domeAnchor.position = dome.center
        domeAnchor.orientation = dome.orientation
        renderer.sky = surrounding.sky
        renderer.projectorOrigin = dome.domeLocal(fromWorld: surrounding.projectorPosition)

        let outgoing = scenery
        do {
            let incoming = try surrounding.makeScenery(dome: dome)
            root.addChild(incoming)
            scenery = incoming
            if animated { fade(incoming, from: 0, to: 1) }
        } catch {
            scenery = nil
        }

        guard let outgoing else { return }
        if animated {
            fade(outgoing, from: 1, to: 0)
            Task {
                try? await Task.sleep(for: .seconds(Self.crossFadeSeconds))
                outgoing.removeFromParent()
            }
        } else {
            outgoing.removeFromParent()
        }
    }

    private func fade(_ entity: Entity, from start: Float, to end: Float) {
        entity.components.set(OpacityComponent(opacity: start))
        let animation = FromToByAnimation<Float>(
            from: start,
            to: end,
            duration: Self.crossFadeSeconds,
            timing: .easeInOut,
            bindTarget: .opacity
        )
        if let resource = try? AnimationResource.generate(with: animation) {
            entity.playAnimation(resource)
        } else {
            entity.components.set(OpacityComponent(opacity: end))
        }
    }
}
