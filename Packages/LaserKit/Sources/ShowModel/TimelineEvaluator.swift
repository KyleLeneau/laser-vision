import Foundation

/// Where the show is at a given instant, resolved against the cue timeline.
public struct TimelineState: Sendable, Equatable {
    /// Continuous beats since the first downbeat (negative before it).
    public var beat: Double
    /// Fractional position inside the current beat, 0..<1.
    public var beatPhase: Double
    public var currentCueIndex: Int
    /// The cue being faded out, while a transition is in progress.
    public var outgoingCueIndex: Int?
    /// 0 at the start of a transition, 1 once the current cue is fully in.
    public var transitionProgress: Double
}

/// Resolves track time into cue and beat positions. Pure and allocation-free per call,
/// so it is safe to use from the render loop.
public struct TimelineEvaluator: Sendable {
    public let tempo: Tempo
    private let cueStartBeats: [Double]
    private let cueTransitionBeats: [Double]

    public init(show: ShowDefinition) {
        tempo = show.tempo
        cueStartBeats = show.cues.map { show.tempo.beats(inBars: $0.startBar) }
        cueTransitionBeats = show.cues.map(\.transitionBeats)
    }

    public func state(at time: Double) -> TimelineState {
        let beat = tempo.beat(at: time)
        let index = cueIndex(atBeat: beat)
        let beatsIntoCue = max(0, beat - cueStartBeats[index])
        let transitionBeats = cueTransitionBeats[index]

        var outgoing: Int?
        var progress = 1.0
        if index > 0, transitionBeats > 0, beatsIntoCue < transitionBeats {
            outgoing = index - 1
            progress = beatsIntoCue / transitionBeats
        }

        return TimelineState(
            beat: beat,
            beatPhase: beat - beat.rounded(.down),
            currentCueIndex: index,
            outgoingCueIndex: outgoing,
            transitionProgress: progress
        )
    }

    /// Index of the last cue starting at or before `beat`; the first cue covers any time before it.
    private func cueIndex(atBeat beat: Double) -> Int {
        var low = 0
        var high = cueStartBeats.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if cueStartBeats[mid] <= beat {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
