import ShowModel
import SwiftUI

/// The launch window: a grid of shows. Choosing one opens the theater and steps this
/// window aside until the show ends.
struct ShowLibraryView: View {
    private static let minimumCardWidth: CGFloat = 300
    private static let spacing: CGFloat = 28

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isOpeningTheater = false

    var body: some View {
        NavigationStack {
            Group {
                if appModel.catalog.entries.isEmpty {
                    ContentUnavailableView("No Shows", systemImage: "rays", description: Text("No show files were found in the app bundle."))
                } else {
                    grid
                }
            }
            .navigationTitle("Laser Vision")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.minimumCardWidth), spacing: Self.spacing)], spacing: Self.spacing) {
                ForEach(appModel.catalog.entries) { entry in
                    ShowCardView(entry: entry, keyVisual: appModel.keyVisual(for: entry)) {
                        open(entry)
                    }
                    .disabled(!entry.isPlayable || isOpeningTheater)
                }
            }
            .padding(Self.spacing + 12)
        }
    }

    private func open(_ entry: ShowEntry) {
        isOpeningTheater = true
        appModel.beginShow(entry)
        Task {
            switch await openImmersiveSpace(id: SceneID.theater) {
            case .opened:
                dismissWindow(id: SceneID.library)
            default:
                appModel.endShow()
            }
            isOpeningTheater = false
        }
    }
}
