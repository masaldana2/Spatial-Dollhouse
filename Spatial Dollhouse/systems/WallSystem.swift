//
//  WallSystem.swift
//  Spatial Dollhouse
//

import RealityKit
import Combine
import UIKit

public final class WallSystem: System {
    private enum WallTextureName {
        static let baseColor = "Poliigon_PlasterPainted_7664_BaseColor.jpg"
        static let roughness = "Poliigon_PlasterPainted_7664_Roughness.jpg"
        static let metallic = "Poliigon_PlasterPainted_7664_Metallic.jpg"
        static let normal = "Poliigon_PlasterPainted_7664_Normal.png"
        static let ambientOcclusion = "Poliigon_PlasterPainted_7664_AmbientOcclusion.jpg"
    }

    private var subscription: (any Cancellable)?
    private let wallMaterial: PhysicallyBasedMaterial = WallSystem.makeWallMaterial(
        fallbackTint: UIColor(red: 0.43, green: 0.31, blue: 0.23, alpha: 1.0)
    )

    required public init(scene: RealityKit.Scene) {
        subscription = scene.subscribe(
            to: ComponentEvents.DidAdd.self,
            componentType: WallRequestComponent.self
        ) { [weak self] event in
            self?.process(event: event)
        }
    }

    deinit {
        subscription?.cancel()
    }

    public func update(context: SceneUpdateContext) { }

    private func process(event: ComponentEvents.DidAdd) {
        guard let request = event.entity.components[WallRequestComponent.self] else { return }

        let mesh = MeshResource.generateBox(
            size: SIMD3<Float>(request.width, request.height, request.depth),
            cornerRadius: request.cornerRadius
        )

        event.entity.components.set(ModelComponent(mesh: mesh, materials: [wallMaterial]))
        event.entity.components.set(WallComponent(rect: request.rect))
        SpawnAnimationController.animateIfNeeded(event.entity)
        event.entity.components.remove(WallRequestComponent.self)
    }

    private static func makeWallMaterial(fallbackTint: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: fallbackTint)
        material.roughness = 0.97
        material.metallic = 0.0
        material.textureCoordinateTransform = .init(scale: .init(3.0, 3.0))

        if let baseColorTexture = try? TextureResource.load(named: WallTextureName.baseColor) {
            material.baseColor = .init(tint: .white, texture: .init(baseColorTexture))
        }

        if let roughnessTexture = try? TextureResource.load(named: WallTextureName.roughness) {
            material.roughness = .init(texture: .init(roughnessTexture))
        }

        if let metallicTexture = try? TextureResource.load(named: WallTextureName.metallic) {
            material.metallic = .init(texture: .init(metallicTexture))
        }

        if let normalTexture = try? TextureResource.load(named: WallTextureName.normal) {
            material.normal = .init(texture: .init(normalTexture))
        }

        if let occlusionTexture = try? TextureResource.load(named: WallTextureName.ambientOcclusion) {
            material.ambientOcclusion = .init(texture: .init(occlusionTexture))
        }

        return material
    }
}
