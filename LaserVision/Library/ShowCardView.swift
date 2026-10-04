import ShowModel
import SwiftUI

/// One show in the library: its key visual, the music, and whether its audio is available.
struct ShowCardView: View {
    private static let cornerRadius: CGFloat = 32
    private static let userAudioFolder = "LaserVision/Resources/UserAudio"

    let entry: ShowEntry
    let keyVisual: CGImage?
    let action: () -> Void

    private var show: ShowDefinition { entry.definition }

    private var missingAudioMessage: String {
        switch show.audio.location {
        case .userSupplied:
            String(localized: "Add “\(show.audio.fileName)” to \(Self.userAudioFolder) to play")
        case .bundled:
            String(localized: "“\(show.audio.fileName)” is missing from the app bundle")
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                KeyVisualView(image: keyVisual)
                    .opacity(entry.isPlayable ? 1 : 0.4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(show.title)
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(show.artist)
                        .foregroundStyle(.secondary)
                    if let album = show.album {
                        Text(album)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }

                if entry.isPlayable {
                    Label("\(Int(show.tempo.bpm.rounded())) BPM", systemImage: "metronome")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label(missingAudioMessage, systemImage: "music.note")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.regularMaterial, in: .rect(cornerRadius: Self.cornerRadius))
            .contentShape(.hoverEffect, .rect(cornerRadius: Self.cornerRadius))
            .hoverEffect()
        }
        .buttonStyle(.plain)
        .accessibilityHint(entry.isPlayable ? Text("Opens the show in the planetarium") : Text("Audio file missing"))
    }
}
