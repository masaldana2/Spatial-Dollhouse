import SwiftUI

struct NewProjectTileView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.53, blue: 0.45),
                                    Color(red: 0.07, green: 0.38, blue: 0.37)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "plus")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(height: 170)

                VStack(alignment: .leading, spacing: 6) {
                    Text("New Project")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Import a floorplan from Files or Photos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                    .foregroundStyle(Color.primary.opacity(0.15))
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel("Create a new project")
    }
}
