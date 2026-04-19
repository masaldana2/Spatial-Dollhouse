//
//  ContentView.swift
//  Spatial Dollhouse
//
//  Created by Miguel Saldana on 4/3/26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ProjectsModel.self) private var projectsModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)
    ]

    var body: some View {
        @Bindable var projectsModel = projectsModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let importMessage = projectsModel.importMessage {
                        Text(importMessage)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        NewProjectTileView {
                            projectsModel.isImportOptionsPresented = true
                        }
                        ForEach(projectsModel.projects) { project in
                            ProjectTileView(project: project) {
                                openProjectInImmersiveSpace(project)
                            }
                        }
                    }
                }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 1180, alignment: .topLeading)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $projectsModel.isImportOptionsPresented) {
            ProjectImportOptionsSheet()
                .environment(projectsModel)
        }
        .fileImporter(
            isPresented: $projectsModel.isFileImporterPresented,
            allowedContentTypes: [.image],
            onCompletion: projectsModel.handleFileImportResult
        )
        .sheet(isPresented: $projectsModel.isNamingSheetPresented, onDismiss: {
            projectsModel.cancelDraftNaming()
        }) {
            ProjectNamingSheet()
                .environment(projectsModel)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Projects")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Start with the plus tile, import a floorplan image, and prepare a project workspace.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private func openProjectInImmersiveSpace(_ project: ProjectSummary) {
        guard project.isImmersiveReady else { return }
        guard let imageData = project.thumbnailData else {
            projectsModel.importMessage = "The project image could not be loaded."
            return
        }

        Task { @MainActor in
            appModel.loadFloorplan(data: imageData, filename: project.imageFileURL.lastPathComponent)
            appModel.immersiveProject = project
            appModel.immersiveLoadErrorMessage = nil
            appModel.isImmersiveModelLoading = true

            guard appModel.immersiveSpaceState == .closed else { return }

            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                break
            case .userCancelled, .error:
                appModel.immersiveSpaceState = .closed
                appModel.immersiveProject = nil
                appModel.isImmersiveModelLoading = false
                projectsModel.importMessage = "The immersive space could not be opened."
            @unknown default:
                appModel.immersiveSpaceState = .closed
                appModel.immersiveProject = nil
                appModel.isImmersiveModelLoading = false
                projectsModel.importMessage = "The immersive space could not be opened."
            }
        }
    }

}

#Preview(windowStyle: .automatic) {
    let appModel = AppModel()

    do {
        let appDataStore = try AppDataStore()
        let projectsModel = ProjectsModel(
            repository: ProjectsRepository(appDataStore: appDataStore)
        )

        return ContentView()
            .environment(appModel)
            .environment(projectsModel)
    } catch {
        print("[ContentView Preview] Failed to initialize AppDataStore: \(error.localizedDescription)")
        return Text("Failed to load preview.")
    }
}

//struct ContentView: View {
//    @Environment(AppModel.self) private var appModel
//
//    @State private var isImporterPresented = false
//    @State private var importError: String?
//
//    var body: some View {
//        VStack(spacing: 20) {
//            Text("Spatial Dollhouse")
//                .font(.largeTitle)
//                .fontWeight(.bold)
//
//            Text("Load a color-coded floorplan and open immersive mode to generate 3D walls, doors, and windows.")
//                .multilineTextAlignment(.center)
//                .foregroundStyle(.secondary)
//
//            legend
//
//            GroupBox("Current Floorplan") {
//                VStack(spacing: 12) {
//                    if let previewImage = appModel.previewImage {
//                        Image(uiImage: previewImage)
//                            .resizable()
//                            .scaledToFit()
//                            .frame(maxHeight: 260)
//                            .clipShape(RoundedRectangle(cornerRadius: 12))
//                    }
//
//                    Text(appModel.activeFloorplanLabel)
//                        .font(.footnote)
//                        .foregroundStyle(.secondary)
//                        .lineLimit(2)
//                }
//                .frame(maxWidth: .infinity)
//            }
//
//            HStack(spacing: 12) {
//                Button("Choose Floorplan Image") {
//                    isImporterPresented = true
//                }
//
//                Button("Use Bundled Test Image") {
//                    appModel.resetToBundledFloorplan()
//                    importError = nil
//                }
//
//                Spacer()
//            }
//
//            if let importError {
//                Text(importError)
//                    .font(.footnote)
//                    .foregroundStyle(.red)
//                    .multilineTextAlignment(.leading)
//                    .frame(maxWidth: .infinity, alignment: .leading)
//            }
//
//            ToggleImmersiveSpaceButton()
//        }
//        .padding(28)
//        .fileImporter(
//            isPresented: $isImporterPresented,
//            allowedContentTypes: [.image],
//            allowsMultipleSelection: false
//        ) { result in
//            switch result {
//                case .success(let urls):
//                    guard let url = urls.first else { return }
//                    do {
//                        try appModel.loadFloorplan(from: url)
//                        importError = nil
//                    } catch {
//                        importError = "Could not load image: \(error.localizedDescription)"
//                    }
//
//                case .failure(let error):
//                    importError = "Could not pick image: \(error.localizedDescription)"
//            }
//        }
//    }
//
//    private var legend: some View {
//        GroupBox("Legend") {
//            HStack(spacing: 18) {
//                legendItem(color: .red, label: "Walls")
//                legendItem(color: .green, label: "Doors")
//                legendItem(color: .blue, label: "Windows")
//            }
//            .frame(maxWidth: .infinity, alignment: .leading)
//        }
//    }
//
//    private func legendItem(color: Color, label: String) -> some View {
//        HStack(spacing: 8) {
//            RoundedRectangle(cornerRadius: 4)
//                .fill(color)
//                .frame(width: 24, height: 14)
//            Text(label)
//                .font(.subheadline)
//        }
//    }
//}
