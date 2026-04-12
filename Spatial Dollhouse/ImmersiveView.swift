//
//  ImmersiveView.swift
//  Spatial Dollhouse
//
//  Created by Miguel Saldana on 4/3/26.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var manipulationWillBeginSubscription: EventSubscription?
    @State private var manipulationDidUpdateSubscription: EventSubscription?
    @State private var manipulationWillEndSubscription: EventSubscription?

    var body: some View {
        RealityView { content in
            do {
                guard let floorplanImage = appModel.activeFloorplanCGImage() else {
                    return
                }

                let dollhouse = try FloorplanDollhouseBuilder.build(from: floorplanImage)
                dollhouse.position.y += 1.0
                content.add(dollhouse)

                let immersiveToScene = content.transform(from: .immersiveSpace, to: .scene)
                appModel.configureImmersiveContext(rootEntity: dollhouse, transform: immersiveToScene)
                subscribeToManipulationCallbacksIfNeeded(in: content)
            } catch {
                print("Failed to generate dollhouse: \(error.localizedDescription)")
            }
        } update: { content in
            if let root = content.entities.first {
                let immersiveToScene = content.transform(from: .immersiveSpace, to: .scene)
                appModel.configureImmersiveContext(rootEntity: root, transform: immersiveToScene)
                subscribeToManipulationCallbacksIfNeeded(in: content)
            }
        }
        .onDisappear {
            manipulationWillBeginSubscription?.cancel()
            manipulationDidUpdateSubscription?.cancel()
            manipulationWillEndSubscription?.cancel()
            manipulationWillBeginSubscription = nil
            manipulationDidUpdateSubscription = nil
            manipulationWillEndSubscription = nil
            dismissWindow(id: appModel.furnitureWindowID)
            openWindow(id: appModel.mainWindowID)
            appModel.endFurnitureMenuDrag()
            appModel.clearImmersiveContext()
        }
        .onAppear {
            dismissWindow(id: appModel.mainWindowID)
            openWindow(id: appModel.furnitureWindowID)
        }
        .id(appModel.floorplanRevision)
    }

    private func subscribeToManipulationCallbacksIfNeeded(in content: RealityViewContent) {
        if manipulationWillBeginSubscription == nil {
            manipulationWillBeginSubscription = content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                guard event.entity.components[FurnitureComponent.self] != nil else { return }
                print("picked up \(event.entity.name)")
            }
        }

        if manipulationDidUpdateSubscription == nil {
            manipulationDidUpdateSubscription = content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { event in
                guard event.entity.components[FurnitureComponent.self] != nil else { return }
                appModel.updateFurnitureManipulation(event.entity)
            }
        }

        if manipulationWillEndSubscription == nil {
            manipulationWillEndSubscription = content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                guard event.entity.components[FurnitureComponent.self] != nil else { return }
                print("dropped \(event.entity.name)")
                appModel.endFurnitureManipulation(event.entity)
            }
        }
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
