//
//  Spatial_DollhouseApp.swift
//  Spatial Dollhouse
//
//  Created by Miguel Saldana on 4/3/26.
//

import SwiftUI
import RealityKit

@main
struct Spatial_DollhouseApp: App {

    @State private var appModel = AppModel()

    init() {
        FurnitureComponent.registerComponent()
        SpawnAnimationComponent.registerComponent()
        FloorSystem.registerSystem()
        WallSystem.registerSystem()
        DoorSystem.registerSystem()
        WindowSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: appModel.mainWindowID) {
            ContentView()
                .environment(appModel)
        }

        WindowGroup(id: appModel.furnitureWindowID) {
            FurnitureWindowView()
                .environment(appModel)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
