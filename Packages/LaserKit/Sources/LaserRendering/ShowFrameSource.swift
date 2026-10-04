import ShowAudio
import ShowModel

/// Everything the renderer needs to draw a show at the moment the listener is hearing.
public struct ShowFrameSource: Sendable {
    public let show: ShowDefinition
    public let analysis: AudioAnalysis
    public let clock: PlaybackClock
    let evaluator: TimelineEvaluator

    public init(show: ShowDefinition, analysis: AudioAnalysis, clock: PlaybackClock) {
        self.show = show
        self.analysis = analysis
        self.clock = clock
        evaluator = TimelineEvaluator(show: show)
    }
}
