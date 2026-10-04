import CoreGraphics
import Foundation
import LaserRendering
import Observation
import os
import ShowModel

/// App-wide state: the show catalog, the show being watched, and the viewer's
/// experience settings (which persist across shows).
@MainActor
@Observable
final class AppModel {
    static let brightnessRange: ClosedRange<Float> = 0.4...1.6
    /// How far the viewer sits above the theater's floor level, in meters (a raised seat).
    static let viewingHeightRange: ClosedRange<Float> = 0...0.8
    static let defaultViewingHeight: Float = 0.3
    private static let viewingHeightKey = "viewingHeight"

    let catalog: ShowCatalog
    /// The show currently open in the theater, if any.
    private(set) var session: ShowSession?

    var surrounding = Surrounding.planetarium
    var laserBrightness: Float = 1
    var hazeEnabled = true
    /// A body preference, so it's remembered between launches.
    var viewingHeight: Float = AppModel.storedViewingHeight() {
        didSet { UserDefaults.standard.set(viewingHeight, forKey: Self.viewingHeightKey) }
    }
    let controls = ControlsVisibility()
    /// Why the theater couldn't be built, shown in the controls window.
    var theaterError: String?

    @ObservationIgnored private var keyVisuals: [ShowEntry.ID: CGImage] = [:]
    @ObservationIgnored private lazy var keyVisualRenderer: KeyVisualRenderer? = {
        do {
            return try KeyVisualRenderer()
        } catch {
            Self.logger.error("Key visuals unavailable: \(String(describing: error))")
            return nil
        }
    }()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LaserVision", category: "App")

    init() {
        catalog = ShowCatalog(resourceRoot: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        for issue in catalog.issues {
            Self.logger.error("Skipped show \(issue.fileName): \(issue.reason)")
        }
    }

    private static func storedViewingHeight() -> Float {
        guard let stored = UserDefaults.standard.object(forKey: viewingHeightKey) as? Float else {
            return defaultViewingHeight
        }
        return min(max(stored, viewingHeightRange.lowerBound), viewingHeightRange.upperBound)
    }

    /// Prepares `entry` for the theater. Playback starts once the theater has loaded it.
    func beginShow(_ entry: ShowEntry) {
        session?.end()
        session = ShowSession(entry: entry)
        controls.reveal()
    }

    /// Stops playback and releases the show. Safe to call more than once.
    func endShow() {
        session?.end()
        session = nil
        theaterError = nil
    }

    /// The card art for a show, rendered once with the live laser kernels and cached.
    func keyVisual(for entry: ShowEntry) -> CGImage? {
        if let image = keyVisuals[entry.id] { return image }
        guard let renderer = keyVisualRenderer else { return nil }
        do {
            let image = try renderer.render(show: entry.definition)
            keyVisuals[entry.id] = image
            return image
        } catch {
            Self.logger.error("Key visual for \(entry.id) failed: \(String(describing: error))")
            return nil
        }
    }
}
