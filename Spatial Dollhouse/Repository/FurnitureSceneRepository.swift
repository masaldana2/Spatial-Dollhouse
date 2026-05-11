//
//  FurnitureSceneRepository.swift
//  Spatial Dollhouse
//

import Foundation
import RealityKit
import RealityKitContent

@MainActor
final class FurnitureSceneRepository {
    static let shared = FurnitureSceneRepository()
    private let previewFurnitureTargetMaxExtent: Float = 0.12
    private let placedFurnitureTargetMaxExtent: Float = 0.10

    private enum PivotPlacement {
        case floorCenter
        case volumeCenter
    }

    private struct TemplateRecord {
        let entity: Entity
        let transformInScene: simd_float4x4
    }

    private var furnitureScene: Entity?
    private var templateRecords: [String: TemplateRecord] = [:]

    func makePlacedFurniture(named entityName: String) async throws -> Entity {
        let template = try await templateRecord(named: entityName)
        let source = template.entity.clone(recursive: true)
        let container = Entity()
        container.name = "furniture_\(entityName)_\(UUID().uuidString)"
        container.components.set(FurnitureComponent(modelName: entityName))
        container.addChild(source)

        source.setTransformMatrix(template.transformInScene, relativeTo: container)
        normalizePivotAndScale(
            source: source,
            in: container,
            targetMaxExtent: placedFurnitureTargetMaxExtent,
            pivotPlacement: .volumeCenter
        )
        configureCollision(for: container, using: source)
        container.components.set(InputTargetComponent(allowedInputTypes: .all))
        container.components.set(HoverEffectComponent(.highlight(.default)))

        return container
    }

    func makePreviewFurniture(named entityName: String) async throws -> Entity {
        let template = try await templateRecord(named: entityName)
        let source = template.entity.clone(recursive: true)
        let container = Entity()
        container.addChild(source)

        source.setTransformMatrix(template.transformInScene, relativeTo: container)
        normalizePivotAndScale(source: source, in: container, targetMaxExtent: previewFurnitureTargetMaxExtent)
        container.position = [0, 0, 0]

        return container
    }

    private func normalizePivotAndScale(
        source: Entity,
        in container: Entity,
        targetMaxExtent: Float,
        pivotPlacement: PivotPlacement = .floorCenter
    ) {
        switch pivotPlacement {
            case .floorCenter:
                recenterOnFloor(source: source, in: container)
            case .volumeCenter:
                recenterOnVolumeCenter(source: source, in: container)
        }

        let fittedBounds = source.visualBounds(relativeTo: container)
        let maxExtent = max(max(fittedBounds.extents.x, fittedBounds.extents.y), fittedBounds.extents.z)
        let safeExtent = max(maxExtent, 0.0001)
        let scale = targetMaxExtent / safeExtent
        container.scale = SIMD3<Float>(repeating: scale)
    }

    private func recenterOnFloor(source: Entity, in container: Entity) {
        let bounds = source.visualBounds(relativeTo: container)
        source.position -= [bounds.center.x, bounds.min.y, bounds.center.z]
    }

    private func recenterOnVolumeCenter(source: Entity, in container: Entity) {
        let bounds = source.visualBounds(relativeTo: container)
        source.position -= bounds.center
    }

    private func configureCollision(for container: Entity, using source: Entity) {
        let bounds = source.visualBounds(relativeTo: container)
        let collisionSize = SIMD3<Float>(
            max(bounds.extents.x, 0.03),
            max(bounds.extents.y, 0.03),
            max(bounds.extents.z, 0.03)
        )
        let collisionShape = ShapeResource.generateBox(size: collisionSize)
            .offsetBy(translation: bounds.center)
        container.components.set(CollisionComponent(shapes: [collisionShape]))
    }

    private func templateRecord(named entityName: String) async throws -> TemplateRecord {
        if let cached = templateRecords[entityName] {
            return cached
        }

        let scene = try await loadFurnitureScene()
        guard let found = lookupEntity(named: entityName, in: scene) else {
            throw FurnitureSceneRepositoryError.missingModel(entityName)
        }

        let record = TemplateRecord(
            entity: found,
            transformInScene: found.transformMatrix(relativeTo: scene)
        )
        templateRecords[entityName] = record
        return record
    }

    private func lookupEntity(named entityName: String, in scene: Entity) -> Entity? {
        if let exact = scene.findEntity(named: entityName) {
            return exact
        }

        let normalizedTarget = normalizedName(entityName)
        return firstEntity(in: scene) { candidate in
            normalizedName(candidate.name) == normalizedTarget
        }
    }

    private func firstEntity(in root: Entity, matching predicate: (Entity) -> Bool) -> Entity? {
        if predicate(root) {
            return root
        }

        for child in root.children {
            if let match = firstEntity(in: child, matching: predicate) {
                return match
            }
        }

        return nil
    }

    private func normalizedName(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func loadFurnitureScene() async throws -> Entity {
        if let furnitureScene {
            return furnitureScene
        }

        if let loaded = try? await Entity(named: "FurnitureSet", in: realityKitContentBundle) {
            furnitureScene = loaded
            return loaded
        }

        if let loaded = try? await Entity(named: "Furniture_set", in: realityKitContentBundle) {
            furnitureScene = loaded
            return loaded
        }

        let loaded = try loadFurnitureSceneFromBundleURL()
        furnitureScene = loaded
        return loaded
    }

    private func loadFurnitureSceneFromBundleURL() throws -> Entity {
        let candidateURLs: [URL] = [
            realityKitContentBundle.url(forResource: "FurnitureSet", withExtension: "usda", subdirectory: "RealityKitContent.rkassets"),
            realityKitContentBundle.url(forResource: "Furniture_set", withExtension: "usdz", subdirectory: "RealityKitContent.rkassets"),
            realityKitContentBundle.url(forResource: "FurnitureSet", withExtension: "usda"),
            realityKitContentBundle.url(forResource: "Furniture_set", withExtension: "usdz")
        ]
        .compactMap { $0 }

        for url in candidateURLs {
            if let loaded = try? Entity.load(contentsOf: url) {
                return loaded
            }
            if let loadedModel = try? Entity.loadModel(contentsOf: url) {
                return loadedModel
            }
        }

        throw FurnitureSceneRepositoryError.missingAsset
    }
}

enum FurnitureSceneRepositoryError: LocalizedError {
    case missingModel(String)
    case missingAsset

    var errorDescription: String? {
        switch self {
            case .missingModel(let modelName):
                return "Model named '\(modelName)' was not found in FurnitureSet."
            case .missingAsset:
                return "Could not load FurnitureSet resources from RealityKitContent bundle."
        }
    }
}
