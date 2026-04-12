//
//  DoorSystem.swift
//  Spatial Dollhouse
//

import RealityKit
import Combine
import UIKit

public final class DoorSystem: System {
    private enum DoorModelName {
        static let base = "Door_with_frame"
        static let ext = "usdz"
        static let file = "\(base).\(ext)"
        static let subdirectory = "Models/Doors"
    }

    private var subscription: (any Cancellable)?
    private var doorPrototype: Entity?
    private let fallbackMaterial = SimpleMaterial(
        color: UIColor(red: 0.18, green: 0.65, blue: 0.20, alpha: 1.0),
        isMetallic: false
    )

    required public init(scene: RealityKit.Scene) {
        subscription = scene.subscribe(
            to: ComponentEvents.DidAdd.self,
            componentType: DoorRequestComponent.self
        ) { [weak self] event in
            self?.process(event: event)
        }
    }

    deinit {
        subscription?.cancel()
    }

    public func update(context: SceneUpdateContext) { }

    private func process(event: ComponentEvents.DidAdd) {
        guard let request = event.entity.components[DoorRequestComponent.self] else { return }

        if let doorEntity = makeDoorEntity(for: request) {
            event.entity.addChild(doorEntity)
        } else {
            let mesh = MeshResource.generateBox(
                size: SIMD3<Float>(request.width, request.height, request.depth),
                cornerRadius: request.cornerRadius
            )

            event.entity.components.set(ModelComponent(mesh: mesh, materials: [fallbackMaterial]))
        }
        event.entity.components.set(DoorComponent(rect: request.rect, isOpen: request.initiallyOpen))
        SpawnAnimationController.animateIfNeeded(event.entity)
        event.entity.components.remove(DoorRequestComponent.self)
    }

    private func makeDoorEntity(for request: DoorRequestComponent) -> Entity? {
        guard let prototype = loadDoorPrototype() else { return nil }

        let door = prototype.clone(recursive: true)
        fit(door: door, to: request)
        guard !door.visualBounds(relativeTo: door).isEmpty else { return nil }
        return door
    }

    private func loadDoorPrototype() -> Entity? {
        if let cached = doorPrototype {
            return cached
        }

        if let modelURL = Bundle.main.url(
            forResource: DoorModelName.base,
            withExtension: DoorModelName.ext,
            subdirectory: DoorModelName.subdirectory
        ) ?? Bundle.main.url(
            forResource: DoorModelName.base,
            withExtension: DoorModelName.ext
        ) {
            if let loadedFromURL = try? Entity.load(contentsOf: modelURL) {
                doorPrototype = loadedFromURL
                return loadedFromURL
            }

            if let loadedModelFromURL = try? Entity.loadModel(contentsOf: modelURL) {
                doorPrototype = loadedModelFromURL
                return loadedModelFromURL
            }
        }

        if let loadedByName = try? Entity.load(named: DoorModelName.file) {
            doorPrototype = loadedByName
            return loadedByName
        }

        if let loadedModelByName = try? Entity.loadModel(named: DoorModelName.file) {
            doorPrototype = loadedModelByName
            return loadedModelByName
        }

        return nil
    }

    private func fit(door: Entity, to request: DoorRequestComponent) {
        let sourceBounds = door.visualBounds(relativeTo: door)
        guard !sourceBounds.isEmpty else { return }

        let safeSourceWidth = max(sourceBounds.extents.x, 0.0001)
        let safeSourceHeight = max(sourceBounds.extents.y, 0.0001)
        let safeSourceDepth = max(sourceBounds.extents.z, 0.0001)

        // Parent door entity rotates 90 degrees for vertical door rects, which swaps world X/Z.
        let isVerticalRect = request.rect.height > request.rect.width
        let targetLocalWidth = isVerticalRect ? request.depth : request.width
        let targetLocalDepth = isVerticalRect ? request.width : request.depth

        let scaleX = targetLocalWidth / safeSourceWidth
        let scaleY = request.height / safeSourceHeight
        let scaleZ = targetLocalDepth / safeSourceDepth
        door.scale = [scaleX, scaleY, scaleZ]

        let fitSpace = Entity()
        fitSpace.addChild(door)
        let transformedBounds = door.visualBounds(relativeTo: fitSpace)
        door.position -= transformedBounds.center
    }
}
