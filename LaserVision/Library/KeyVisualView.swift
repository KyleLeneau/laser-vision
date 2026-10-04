import SwiftUI

/// A show's signature pattern as it appears on the dome (a circular domemaster frame).
struct KeyVisualView: View {
    let image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Circle()
                    .fill(.black.opacity(0.6))
                    .overlay {
                        Image(systemName: "rays")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.circle)
        .frame(maxWidth: .infinity)
    }
}
