import SwiftUI

/// Choose where to watch from and tune the lasers.
struct ExperienceSettingsView: View {
    private static let tileSize = CGSize(width: 200, height: 96)

    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        VStack(alignment: .leading, spacing: 20) {
            Text("Surroundings")
                .font(.headline)
            HStack(spacing: 16) {
                ForEach(Surrounding.allCases) { surrounding in
                    surroundingTile(surrounding)
                }
            }

            HStack(spacing: 24) {
                Label("Laser brightness", systemImage: "sun.max.fill")
                Slider(value: $appModel.laserBrightness, in: AppModel.brightnessRange)
            }

            HStack(spacing: 24) {
                Label("Seat height", systemImage: "arrow.up.and.down")
                Slider(value: $appModel.viewingHeight, in: AppModel.viewingHeightRange)
            }

            Toggle(isOn: $appModel.hazeEnabled) {
                Label("Haze beams", systemImage: "rays")
            }
        }
        .padding(24)
        .glassBackgroundEffect()
    }

    private func surroundingTile(_ surrounding: Surrounding) -> some View {
        let isSelected = appModel.surrounding == surrounding
        return Button {
            appModel.surrounding = surrounding
        } label: {
            VStack(spacing: 8) {
                Image(systemName: surrounding.symbolName)
                    .font(.title)
                Text(surrounding.displayName)
                    .font(.callout)
            }
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        }
        .buttonBorderShape(.roundedRectangle(radius: 20))
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 20))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
