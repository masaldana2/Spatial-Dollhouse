//
//  Spatial_DollhouseApp.swift
//  Spatial Dollhouse
//
//  Created by Miguel Saldana on 4/3/26.
//

import SwiftUI
import RealityKit
import SwiftData

@main
struct Spatial_DollhouseApp: App {
    private let appDataStore: AppDataStore
    @State private var appModel: AppModel
    @State private var projectsModel: ProjectsModel

    init() {
        do {
            let appDataStore = try AppDataStore()
            self.appDataStore = appDataStore
            _appModel = State(initialValue: AppModel())
            _projectsModel = State(
                initialValue: ProjectsModel(
                    repository: ProjectsRepository(appDataStore: appDataStore)
                )
            )
        } catch {
            fatalError("Failed to initialize app data store: \(error.localizedDescription)")
        }

        FurnitureComponent.registerComponent()
        FurnitureSelectionComponent.registerComponent()
        FurniturePanComponent.registerComponent()
        FurnitureFloorClampRequestComponent.registerComponent()
        SpawnAnimationComponent.registerComponent()
        FloorSystem.registerSystem()
        WallSystem.registerSystem()
        DoorSystem.registerSystem()
        WindowSystem.registerSystem()
        FurnitureSelectionSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: appModel.mainWindowID) {
            ContentView()
                .environment(appModel)
                .environment(projectsModel)
        }
        .modelContainer(appDataStore.modelContainer)

        WindowGroup(id: appModel.furnitureWindowID) {
            FurnitureWindowView()
                .environment(appModel)
        }
        .modelContainer(appDataStore.modelContainer)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.immersiveProject = nil
                    appModel.immersiveLoadErrorMessage = nil
                    appModel.isImmersiveModelLoading = false
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        .modelContainer(appDataStore.modelContainer)
    }
}
