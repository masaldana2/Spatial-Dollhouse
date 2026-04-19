import SwiftUI
import UIKit

struct ProjectNamingSheet: View {
    @Environment(ProjectsModel.self) private var projectsModel

    var body: some View {
        @Bindable var projectsModel = projectsModel

        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let draftImageData = projectsModel.draftImageData,
                    let image = UIImage(data: draftImageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Project Name")
                        .font(.headline)

                    TextField("Project name", text: $projectsModel.draftProjectName)
                        .textFieldStyle(.roundedBorder)

                    Text("Saving creates a UUID-named folder in Documents and stores the imported image inside it using the project name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Name Project")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        projectsModel.cancelDraftNaming()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue") {
                        projectsModel.completeDraftNaming()
                    }
                    .disabled(projectsModel.draftProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
