import PhotosUI
import SwiftUI

struct ProjectImportOptionsSheet: View {
    @Environment(ProjectsModel.self) private var projectsModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Start a new project by importing a floorplan image from Files or Photos.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(spacing: 14) {
                    Button {
                        dismiss()
                        projectsModel.startFileImport()
                    } label: {
                        importRow(
                            title: "Files",
                            subtitle: "Browse images stored in the Files app.",
                            systemImage: "folder.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        importRow(
                            title: "Photos",
                            subtitle: "Choose an image from your photo library.",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Import Image")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }

            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ProjectImportSheetError.invalidImage
                    }
                    dismiss()
                    projectsModel.handlePhotoSelection(data: data, fileExtension: "jpg")
                    selectedPhotoItem = nil
                } catch {
                    dismiss()
                    projectsModel.importMessage = error.localizedDescription
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func importRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private enum ProjectImportSheetError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected photo could not be loaded as an image."
        }
    }
}
