import SwiftUI

struct ProjectTileView: View {
    let project: ProjectSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    if let thumbnailData = project.thumbnailData,
                        let image = UIImage(data: thumbnailData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    Color(red: 0.78, green: 0.85, blue: 0.92),
                                    Color(red: 0.87, green: 0.90, blue: 0.95)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            Image(systemName: "house.lodge.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(Color(red: 0.25, green: 0.34, blue: 0.44))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(8)
        .disabled(!project.isImmersiveReady)
        .accessibilityHint(project.isImmersiveReady ? "Opens the model in immersive space." : "Immersive preview is available after the model finishes generating.")
        .opacity(project.isImmersiveReady ? 1 : 0.96)
        .overlay {
            if project.generationState == .generating {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)

                            Text("Generating 3D Model")
                                .font(.headline)

                            Text("You can keep using the rest of the screen.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if project.isImmersiveReady {
                Label("Immersive", systemImage: "visionpro")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(14)
            }
        }
    }

    private var statusLine: String {
        switch project.generationState {
        case .idle:
            return "Pending 3D generation."
        case .generating:
            return "Generating 3D model..."
        case .ready:
            return "3D model exported as OBJ in the project folder."
        case let .failed(message):
            return message.isEmpty ? "3D model generation failed." : message
        }
    }

    private var statusColor: Color {
        switch project.generationState {
        case .failed:
            return .red
        case .idle, .generating, .ready:
            return .secondary
        }
    }
}
