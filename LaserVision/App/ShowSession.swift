import Foundation
import LaserRendering
import Observation
import ShowAudio
import ShowModel

/// One viewing of a show: loads and analyzes its audio, then plays it.
@MainActor
@Observable
final class ShowSession: Identifiable {
    enum Phase {
        case loading
        case ready(ShowFrameSource)
        case failed(String)
    }

    let id = UUID()
    let entry: ShowEntry
    let player = ShowPlayer()
    private(set) var phase = Phase.loading

    init(entry: ShowEntry) {
        self.entry = entry
    }

    var show: ShowDefinition { entry.definition }

    var frameSource: ShowFrameSource? {
        if case .ready(let source) = phase { source } else { nil }
    }

    /// Analyzes the track (about a second per few minutes of audio) and starts playback.
    func prepareAndPlay() async {
        guard case .loading = phase else { return }
        guard let audioURL = entry.audioURL else {
            phase = .failed(String(localized: "The audio file \(show.audio.fileName) is missing."))
            return
        }
        do {
            async let analysis = AudioAnalyzer.analyze(fileAt: audioURL)
            try await player.load(url: audioURL)
            let source = ShowFrameSource(show: show, analysis: try await analysis, clock: player.clock)
            try Task.checkCancellation()
            phase = .ready(source)
            try player.play()
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func togglePlayback() {
        perform { try player.togglePlayback() }
    }

    func restart() {
        perform { try player.restart() }
    }

    func end() {
        player.unload()
    }

    /// Runs a player command; an audio engine failure ends the session with a message.
    private func perform(_ command: () throws -> Void) {
        do {
            try command()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
