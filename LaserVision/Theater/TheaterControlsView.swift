import SwiftUI

/// The controls window shown while in the theater: playback controls, with the experience
/// settings panel stacked above when opened. The system places it near the viewer as a
/// utility panel; it closes itself during playback, and tapping the dome brings it back.
struct TheaterControlsView: View {
    private static let width: CGFloat = 760

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var showsSettings = false

    var body: some View {
        let controls = appModel.controls
        VStack(spacing: 16) {
            if showsSettings {
                ExperienceSettingsView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Group {
                if let session = appModel.session {
                    PlayerControlsView(
                        session: session,
                        showsSettings: $showsSettings,
                        onInteraction: controls.reveal,
                        onExit: exit
                    )
                } else {
                    unavailable(message: appModel.theaterError ?? String(localized: "No show selected."))
                }
            }
            .padding(24)
            .glassBackgroundEffect()
        }
        .frame(width: Self.width)
        .animation(.spring, value: showsSettings)
        .onChange(of: showsSettings) { _, isOpen in
            if isOpen { controls.pin() } else { controls.reveal() }
        }
        // Closed with the window's own close button: keep the visibility state honest.
        .onDisappear { controls.hide() }
    }

    private func exit() {
        Task { await dismissImmersiveSpace() }
    }

    private func unavailable(message: String) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle")
            Spacer()
            Button("Exit", systemImage: "xmark", action: exit)
        }
    }
}
