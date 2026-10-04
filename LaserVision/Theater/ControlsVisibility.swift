import Foundation
import Observation

/// Shows the playback controls on demand and tucks them away while the show plays,
/// so nothing distracts from the dome.
@MainActor
@Observable
final class ControlsVisibility {
    /// Idle time before the controls hide during playback.
    static let autoHideDelay = Duration.seconds(6)

    private(set) var isVisible = true
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Shows the controls and restarts the auto-hide countdown.
    func reveal() {
        isVisible = true
        scheduleHide()
    }

    func toggle() {
        if isVisible { hide() } else { reveal() }
    }

    /// Keeps the controls up (e.g. while paused or loading).
    func pin() {
        hideTask?.cancel()
        isVisible = true
    }

    func hide() {
        hideTask?.cancel()
        isVisible = false
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoHideDelay)
            guard !Task.isCancelled else { return }
            self?.isVisible = false
        }
    }
}
