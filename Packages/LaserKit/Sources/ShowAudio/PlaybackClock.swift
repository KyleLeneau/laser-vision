import AVFoundation
import Synchronization

/// Thread-safe track time, readable from the render loop without touching the audio engine.
///
/// The clock is anchored to the host time at which audio actually starts (including output
/// latency), so `currentTime()` reports what the listener is hearing right now.
public final class PlaybackClock: Sendable {
    private struct State {
        /// Track time at the anchor.
        var anchorTrackTime: Double = 0
        /// Host time (seconds) when `anchorTrackTime` is heard; `nil` while stopped.
        var anchorHostSeconds: Double?
    }

    private let state = Mutex(State())

    public init() {}

    public static func hostSecondsNow() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    public var isRunning: Bool {
        state.withLock { $0.anchorHostSeconds != nil }
    }

    /// Track time being heard now. Holds still before a scheduled start and while stopped.
    public func currentTime(hostSeconds: Double = PlaybackClock.hostSecondsNow()) -> Double {
        state.withLock { state in
            guard let anchor = state.anchorHostSeconds else { return state.anchorTrackTime }
            return state.anchorTrackTime + max(0, hostSeconds - anchor)
        }
    }

    func run(from trackTime: Double, heardAtHostSeconds hostSeconds: Double) {
        state.withLock { $0 = State(anchorTrackTime: trackTime, anchorHostSeconds: hostSeconds) }
    }

    func hold(at trackTime: Double) {
        state.withLock { $0 = State(anchorTrackTime: trackTime, anchorHostSeconds: nil) }
    }
}
