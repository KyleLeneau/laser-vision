import SwiftUI

@main
struct LaserVisionApp: App {
    @State private var appModel = AppModel()
    @State private var immersionStyle: any ImmersionStyle = .full

    var body: some Scene {
        WindowGroup(id: SceneID.library) {
            ShowLibraryView()
                .environment(appModel)
        }
        .defaultSize(width: 1_180, height: 760)

        // A system-placed utility panel: it appears near the viewer at a comfortable height,
        // seated or standing, and stays fully interactive inside the immersive space.
        WindowGroup(id: SceneID.controls) {
            TheaterControlsView()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.utilityPanel)
        }
        // Only meaningful alongside a playing show; never bring it back on relaunch.
        .restorationBehavior(.disabled)

        ImmersiveSpace(id: SceneID.theater) {
            TheaterView()
                .environment(appModel)
        }
        .immersionStyle(selection: $immersionStyle, in: .full)
    }
}
