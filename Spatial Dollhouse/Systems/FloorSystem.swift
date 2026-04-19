//
//  FloorSystem.swift
//  Spatial Dollhouse
//

import RealityKit
import Combine
import UIKit

public final class FloorSystem: System {
    private enum FloorTextureName {
        static let baseColor = "wood_floor_diff_2k.jpg"
        static let roughness = "wood_floor_rough_2k.exr"
        static let normal = "wood_floor_nor_gl_2k.exr"
    }

    private var subscription: (any Cancellable)?

    private let material: PhysicallyBasedMaterial = FloorSystem.makeFloorMaterial(
        fallbackTint: UIColor(red: 0.88, green: 0.84, blue: 0.74, alpha: 1.0),
        textureRepeatScale: 6.0
    )

    required public init(scene: RealityKit.Scene) {
        subscription = scene.subscribe(
            to: ComponentEvents.DidAdd.self,
            componentType: FloorRequestComponent.self
        ) { [weak self] event in
            self?.process(event: event)
        }
    }

    deinit {
        subscription?.cancel()
    }

    public func update(context: SceneUpdateContext) { }

    private func process(event: ComponentEvents.DidAdd) {
        guard let request = event.entity.components[FloorRequestComponent.self] else { return }

        let mesh = MeshResource.generateBox(
            size: SIMD3<Float>(request.width, request.thickness, request.depth),
            cornerRadius: request.cornerRadius
        )
        let collisionShape = ShapeResource.generateBox(
            size: SIMD3<Float>(request.width, request.thickness, request.depth)
        )

        event.entity.components.set(ModelComponent(mesh: mesh, materials: [material]))
        event.entity.components.set(CollisionComponent(shapes: [collisionShape]))
        event.entity.components.set(FloorComponent(widthMeters: request.width, depthMeters: request.depth))
        SpawnAnimationController.animateIfNeeded(event.entity)
        event.entity.components.remove(FloorRequestComponent.self)
    }

    private static func makeFloorMaterial(
        fallbackTint: UIColor,
        textureRepeatScale: Float
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: fallbackTint)
        material.roughness = 0.92
        material.metallic = 0.0
        material.textureCoordinateTransform = .init(scale: .init(textureRepeatScale, textureRepeatScale))

        if let baseColorTexture = try? TextureResource.load(named: FloorTextureName.baseColor) {
            material.baseColor = .init(tint: .white, texture: .init(baseColorTexture))
        }

        if let roughnessTexture = try? TextureResource.load(named: FloorTextureName.roughness) {
            material.roughness = .init(texture: .init(roughnessTexture))
        }

        if let normalTexture = try? TextureResource.load(named: FloorTextureName.normal) {
            material.normal = .init(texture: .init(normalTexture))
        }

        return material
    }
}
