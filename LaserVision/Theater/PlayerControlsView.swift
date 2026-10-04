import ShowAudio
import ShowModel
import SwiftUI

/// Show title, transport buttons, progress and volume.
struct PlayerControlsView: View {
    private static let progressRefreshInterval = 0.25
    private static let volumeSliderWidth: CGFloat = 140

    let session: ShowSession
    @Binding var showsSettings: Bool
    /// Called on every interaction, to keep the controls from auto-hiding mid-use.
    let onInteraction: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.show.title)
                        .font(.title2.bold())
                    Text(session.show.artist)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                status
            }

            HStack(spacing: 16) {
                Button("Exit", systemImage: "xmark", action: onExit)
                Button("Restart", systemImage: "backward.end.fill") {
                    session.restart()
                    onInteraction()
                }
                .disabled(!isReady)
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    session.togglePlayback()
                    onInteraction()
                }
                .controlSize(.extraLarge)
                .disabled(!isReady)

                progress

                volume

                Toggle("Settings", systemImage: "slider.horizontal.3", isOn: $showsSettings)
                    .toggleStyle(.button)
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
        }
    }

    private var player: ShowPlayer { session.player }
    private var isPlaying: Bool { player.isPlaying }

    private var isReady: Bool {
        if case .ready = session.phase { true } else { false }
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .loading:
            ProgressView("Analyzing music…")
                .progressViewStyle(.circular)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .lineLimit(2)
        case .ready:
            EmptyView()
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: Self.progressRefreshInterval)) { _ in
            let duration = max(player.duration, 1)
            let elapsed = min(player.currentTime, duration)
            HStack(spacing: 10) {
                ProgressView(value: elapsed, total: duration)
                Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var volume: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { player.volume }, set: { player.volume = $0; onInteraction() }),
                in: 0...1
            )
            .frame(width: Self.volumeSliderWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume")
    }
}
