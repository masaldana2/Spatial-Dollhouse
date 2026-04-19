//
//  WindowSystem.swift
//  Spatial Dollhouse
//

import RealityKit
import Combine
import UIKit

public final class WindowSystem: System {
    private var subscription: (any Cancellable)?

    private let material = SimpleMaterial(
        color: UIColor(red: 0.18, green: 0.70, blue: 0.88, alpha: 0.5),
        isMetallic: false
    )

    required public init(scene: RealityKit.Scene) {
        subscription = scene.subscribe(
            to: ComponentEvents.DidAdd.self,
            componentType: WindowRequestComponent.self
        ) { [weak self] event in
            self?.process(event: event)
        }
    }

    deinit {
        subscription?.cancel()
    }

    public func update(context: SceneUpdateContext) { }

    private func process(event: ComponentEvents.DidAdd) {
        guard let request = event.entity.components[WindowRequestComponent.self] else { return }

        let mesh = MeshResource.generateBox(
            size: SIMD3<Float>(request.width, request.height, request.depth),
            cornerRadius: request.cornerRadius
        )

        event.entity.components.set(ModelComponent(mesh: mesh, materials: [material]))
        event.entity.components.set(WindowComponent(rect: request.rect, sillHeight: request.sillHeight))
        SpawnAnimationController.animateIfNeeded(event.entity)
        event.entity.components.remove(WindowRequestComponent.self)
    }
}
