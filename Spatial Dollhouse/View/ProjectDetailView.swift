import SwiftUI

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    let project: ProjectSummary

    var body: some View {
        Group {
            if appModel.isImmersiveModelLoading {
                loadingOverlay
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(project.name)
                            .font(.system(size: 34, weight: .bold, design: .rounded))

                        ImageCardView(
                            title: "Imported Floorplan",
                            image: project.thumbnailData.flatMap(UIImage.init(data:))
                        )

                        projectInfoCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 1180, alignment: .topLeading)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !appModel.isImmersiveModelLoading {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .onDisappear {
            closeImmersiveIfNeeded()
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)

                VStack(spacing: 6) {
                    Text("Loading immersive model")
                        .font(.headline)
                    Text("Back navigation is disabled until the model is ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
    }

    private var projectInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Details")
                .font(.headline)

            detailRow(title: "Status", value: project.generationState.description)
            detailRow(title: "Folder", value: project.directoryURL.lastPathComponent)
            detailRow(title: "Image File", value: project.imageFileURL.lastPathComponent)
            detailRow(title: "Model File", value: project.modelFileURL?.lastPathComponent ?? "Not available")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(width: 90, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func closeImmersiveIfNeeded() {
        guard appModel.immersiveProject?.id == project.id else { return }
        guard appModel.immersiveSpaceState == .open else {
            appModel.immersiveProject = nil
            appModel.immersiveLoadErrorMessage = nil
            return
        }

        Task { @MainActor in
            appModel.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
        }
    }
}
