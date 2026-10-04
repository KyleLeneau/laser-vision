import RealityKit
import ShowAudio
import SwiftUI

/// The fully immersive planetarium. Owns the scene and the show's lifecycle: however the
/// space closes (Exit, Digital Crown…), the show stops, the controls window closes and the
/// library window comes back.
struct TheaterView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var stage: TheaterStage?

    var body: some View {
        RealityView { content in
            do {
                let stage = try TheaterStage(surrounding: appModel.surrounding)
                try await stage.makeDomeTappable()
                content.add(stage.root)
                self.stage = stage
            } catch {
                appModel.theaterError = error.localizedDescription
            }
        } update: { _ in
            stage?.apply(
                surrounding: appModel.surrounding,
                laserBrightness: appModel.laserBrightness,
                hazeEnabled: appModel.hazeEnabled,
                viewingHeight: appModel.viewingHeight,
                session: appModel.session
            )
        }
        .gesture(SpatialTapGesture().targetedToEntity(where: .has(DomeTapTargetComponent.self)).onEnded { _ in
            appModel.controls.toggle()
        })
        .task(id: appModel.session?.id) {
            await appModel.session?.prepareAndPlay()
        }
        .onAppear {
            if appModel.controls.isVisible { openWindow(id: SceneID.controls) }
        }
        .onChange(of: appModel.session?.player.isPlaying) { _, isPlaying in
            if isPlaying == true {
                appModel.controls.reveal()
            } else {
                appModel.controls.pin()
            }
        }
        // The controls window opens and closes with the visibility state.
        .onChange(of: appModel.controls.isVisible) { _, isVisible in
            if isVisible {
                openWindow(id: SceneID.controls)
            } else {
                dismissWindow(id: SceneID.controls)
            }
        }
        .onDisappear {
            dismissWindow(id: SceneID.controls)
            appModel.endShow()
            openWindow(id: SceneID.library)
        }
    }
}
