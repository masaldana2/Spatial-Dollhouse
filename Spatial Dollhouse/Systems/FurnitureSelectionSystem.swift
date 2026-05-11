//
//  FurnitureSelectionSystem.swift
//  Spatial Dollhouse
//

import RealityKit
import UIKit

public final class FurnitureSelectionSystem: System {
    private static let selectedFurnitureQuery = EntityQuery(
        where: .has(FurnitureComponent.self) && .has(FurnitureSelectionComponent.self)
    )
    private static let floorClampRequestQuery = EntityQuery(
        where: .has(FurnitureComponent.self) && .has(FurnitureFloorClampRequestComponent.self)
    )
    private static let floorQuery = EntityQuery(where: .has(FloorComponent.self))

    private var selectionIndicator: ModelEntity?
    private var selectionIndicatorSize: Float = 0

    required public init(scene: RealityKit.Scene) { }

    public func update(context: SceneUpdateContext) {
        let selectedFurniture = Array(context.scene.performQuery(Self.selectedFurnitureQuery))
        guard let activeSelection = mostRecentSelection(in: selectedFurniture) else {
            selectionIndicator?.removeFromParent()
            processFloorClampRequests(in: context.scene)
            return
        }

        clearStaleSelections(selectedFurniture, keeping: activeSelection)
        updatePanIfNeeded(for: activeSelection, in: context.scene)
        processFloorClampRequests(in: context.scene)
        updateSelectionIndicator(for: activeSelection, in: context.scene)
    }

    private func mostRecentSelection(in entities: [Entity]) -> Entity? {
        entities.max { lhs, rhs in
            let lhsTime = lhs.components[FurnitureSelectionComponent.self]?.selectedAt ?? 0
            let rhsTime = rhs.components[FurnitureSelectionComponent.self]?.selectedAt ?? 0
            return lhsTime < rhsTime
        }
    }

    private func clearStaleSelections(_ entities: [Entity], keeping activeSelection: Entity) {
        for entity in entities where entity !== activeSelection {
            entity.components.remove(FurnitureSelectionComponent.self)
            entity.components.remove(FurniturePanComponent.self)
        }
    }

    private func updatePanIfNeeded(for furniture: Entity, in scene: RealityKit.Scene) {
        guard var pan = furniture.components[FurniturePanComponent.self] else { return }

        if !pan.isActive {
            clampFurnitureToFloor(furniture, in: scene)
            furniture.components.remove(FurniturePanComponent.self)
            return
        }

        let currentPosition = furniture.position(relativeTo: nil)
        if !pan.hasOffset {
            pan.offsetXZ = SIMD2<Float>(
                currentPosition.x - pan.targetWorldPosition.x,
                currentPosition.z - pan.targetWorldPosition.z
            )
            pan.hasOffset = true
        }

        var proposedPosition = currentPosition
        proposedPosition.x = pan.targetWorldPosition.x + pan.offsetXZ.x
        proposedPosition.z = pan.targetWorldPosition.z + pan.offsetXZ.y
        clampFurnitureToFloor(furniture, in: scene, proposedPosition: proposedPosition)
        furniture.components.set(pan)
    }

    private func processFloorClampRequests(in scene: RealityKit.Scene) {
        for furniture in scene.performQuery(Self.floorClampRequestQuery) {
            clampFurnitureToFloor(furniture, in: scene)
            furniture.components.remove(FurnitureFloorClampRequestComponent.self)
        }
    }

    @discardableResult
    private func clampFurnitureToFloor(
        _ furniture: Entity,
        in scene: RealityKit.Scene,
        proposedPosition: SIMD3<Float>? = nil
    ) -> SIMD3<Float> {
        var worldPosition = proposedPosition ?? furniture.position(relativeTo: nil)
        if let placement = placementLimits(for: furniture, in: scene) {
            worldPosition.x = min(max(worldPosition.x, placement.minX), placement.maxX)
            worldPosition.z = min(max(worldPosition.z, placement.minZ), placement.maxZ)
            worldPosition.y = placement.y
        }
        furniture.setPosition(worldPosition, relativeTo: nil)
        return worldPosition
    }

    private func placementLimits(
        for entity: Entity,
        in scene: RealityKit.Scene
    ) -> (minX: Float, maxX: Float, minZ: Float, maxZ: Float, y: Float)? {
        guard let floorEntity = firstFloorEntity(in: scene) else { return nil }

        let floorBounds = floorEntity.visualBounds(relativeTo: nil)
        let entityBounds = entity.visualBounds(relativeTo: nil)

        let halfX = max(entityBounds.extents.x * 0.5, 0.02)
        let halfZ = max(entityBounds.extents.z * 0.5, 0.02)
        let bottomOffset = max(entity.position(relativeTo: nil).y - entityBounds.min.y, 0)

        let minX = floorBounds.min.x + halfX
        let maxX = floorBounds.max.x - halfX
        let minZ = floorBounds.min.z + halfZ
        let maxZ = floorBounds.max.z - halfZ
        let y = floorBounds.max.y + bottomOffset

        guard minX <= maxX, minZ <= maxZ else { return nil }
        return (minX, maxX, minZ, maxZ, y)
    }

    private func updateSelectionIndicator(for furniture: Entity, in scene: RealityKit.Scene) {
        let bounds = furniture.visualBounds(relativeTo: nil)
        guard !bounds.isEmpty else { return }

        let footprintSize = max(max(bounds.extents.x, bounds.extents.z) * 1.35, 0.08)
        let indicator = selectionIndicator ?? makeSelectionIndicator(size: footprintSize)
        if selectionIndicator == nil {
            selectionIndicator = indicator
        }

        if abs(selectionIndicatorSize - footprintSize) > 0.001 {
            indicator.model = ModelComponent(
                mesh: MeshResource.generatePlane(
                    width: footprintSize,
                    depth: footprintSize,
                    cornerRadius: min(footprintSize * 0.12, 0.03)
                ),
                materials: [selectionIndicatorMaterial()]
            )
            selectionIndicatorSize = footprintSize
        }

        if indicator.parent == nil {
            indicatorParent(for: furniture, in: scene)?.addChild(indicator)
        }

        let floorY = firstFloorEntity(in: scene)?.visualBounds(relativeTo: nil).max.y ?? bounds.min.y
        indicator.setPosition(
            SIMD3<Float>(bounds.center.x, floorY + 0.004, bounds.center.z),
            relativeTo: nil
        )
    }

    private func makeSelectionIndicator(size: Float) -> ModelEntity {
        let indicator = ModelEntity(
            mesh: MeshResource.generatePlane(
                width: size,
                depth: size,
                cornerRadius: min(size * 0.12, 0.03)
            ),
            materials: [selectionIndicatorMaterial()]
        )
        indicator.name = "furniture_selection_indicator"
        selectionIndicatorSize = size
        return indicator
    }

    private func selectionIndicatorMaterial() -> UnlitMaterial {
        UnlitMaterial(color: UIColor.systemCyan.withAlphaComponent(0.32))
    }

    private func indicatorParent(for furniture: Entity, in scene: RealityKit.Scene) -> Entity? {
        if let floorParent = firstFloorEntity(in: scene)?.parent {
            return floorParent
        }
        return furniture.parent
    }

    private func firstFloorEntity(in scene: RealityKit.Scene) -> Entity? {
        for floor in scene.performQuery(Self.floorQuery) {
            return floor
        }
        return nil
    }
}
