//
//  AppModel.swift
//  Spatial-Dollhouse
//
//  Created by Dario Suarez on 14/04/2026.
//

import SwiftUI
import RealityKit
import Spatial

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    let mainWindowID = "MainWindow"
    let furnitureWindowID = "FurnitureWindow"
    
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    var immersiveProject: ProjectSummary?
    var immersiveLoadErrorMessage: String?
    var isImmersiveModelLoading = false
    private(set) var floorplanData: Data?
    private(set) var floorplanFilename: String?
    private(set) var floorplanRevision = 0

    @MainActor
    var immersiveSpaceToSceneTransform: AffineTransform3D = .identity

    private weak var dollhouseRootEntity: Entity?
    private var menuDragEntity: Entity?
    private let dragBubble = DragBubble()
    private var menuDragModelName: String?
    private var menuDragTargetPoint: Point3D?
    private var menuDragTargetPose: Pose3D?
    private var menuDragStartSceneOrientation: simd_quatf?
    private var menuDragSessionID: UUID?

    private let bundledFloorplanAssetName = "FloorplanTest"

    var activeFloorplanLabel: String {
        floorplanFilename ?? "\(bundledFloorplanAssetName) (Bundled)"
    }

    var previewImage: UIImage? {
        if let floorplanData, let loaded = UIImage(data: floorplanData) {
            return loaded
        }
        return UIImage(named: bundledFloorplanAssetName)
    }

    func activeFloorplanCGImage() -> CGImage? {
        previewImage?.cgImage
    }

    func loadFloorplan(from url: URL) throws {
        let hadAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hadAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        floorplanData = try Data(contentsOf: url)
        floorplanFilename = url.lastPathComponent
        floorplanRevision += 1
    }

    func loadFloorplan(data: Data, filename: String?) {
        floorplanData = data
        floorplanFilename = filename
        floorplanRevision += 1
    }

    func resetToBundledFloorplan() {
        floorplanData = nil
        floorplanFilename = nil
        floorplanRevision += 1
    }

    func configureImmersiveContext(rootEntity: Entity, transform: AffineTransform3D) {
        dollhouseRootEntity = rootEntity
        immersiveSpaceToSceneTransform = transform
    }

    func clearImmersiveContext() {
        dollhouseRootEntity = nil
        menuDragEntity = nil
        dragBubble.remove()
        menuDragModelName = nil
        menuDragTargetPoint = nil
        menuDragTargetPose = nil
        menuDragStartSceneOrientation = nil
        menuDragSessionID = nil
    }

    func beginFurnitureMenuDrag(named modelName: String, at immersivePoint: Point3D, inputDevicePose: Pose3D?) {
        menuDragTargetPoint = immersivePoint
        menuDragTargetPose = inputDevicePose
        menuDragStartSceneOrientation = inputDevicePose.map(sceneOrientationFromImmersivePose)

        if let root = dollhouseRootEntity {
            let bubble = dragBubble.ensureAttached(to: root)
            applyMenuDragTarget(to: bubble, constrainingTo: nil, applyingOrientation: false)
        }

        if let menuDragEntity {
            applyMenuDragTarget(to: menuDragEntity, constrainingTo: nil)
            return
        }

        guard let root = dollhouseRootEntity else { return }
        guard menuDragModelName == nil else { return }

        let sessionID = UUID()
        menuDragSessionID = sessionID
        menuDragModelName = modelName

        Task { @MainActor in
            do {
                let newEntity = try await FurnitureSceneRepository.shared.makePlacedFurniture(named: modelName)

                guard menuDragSessionID == sessionID else { return }

                root.addChild(newEntity)
                preserveWorldScaleForPlacedFurniture(newEntity, in: root)
                menuDragEntity = newEntity
                newEntity.setOrientation(.init(angle: 0, axis: [0, 1, 0]), relativeTo: nil)
                applyMenuDragTarget(to: newEntity, constrainingTo: nil)
            } catch {
                print("Failed to start furniture drag for \(modelName): \(error.localizedDescription)")
                guard menuDragSessionID == sessionID else { return }
                menuDragModelName = nil
                menuDragSessionID = nil
            }
        }
    }

    func updateFurnitureMenuDrag(at immersivePoint: Point3D, inputDevicePose: Pose3D?) {
        menuDragTargetPoint = immersivePoint
        menuDragTargetPose = inputDevicePose
        if menuDragStartSceneOrientation == nil, let inputDevicePose {
            menuDragStartSceneOrientation = sceneOrientationFromImmersivePose(inputDevicePose)
        }

        if let debugSphere = dragBubble.entity {
            applyMenuDragTarget(to: debugSphere, constrainingTo: nil, applyingOrientation: false)
        }
        if let menuDragEntity {
            applyMenuDragTarget(to: menuDragEntity, constrainingTo: nil)
        }
    }

    func endFurnitureMenuDrag() {
        if let menuDragEntity {
            dropDraggedFurnitureToFloor(menuDragEntity, resetRotationToZero: true)
        }
        menuDragEntity = nil
        dragBubble.remove()
        menuDragModelName = nil
        menuDragTargetPoint = nil
        menuDragTargetPose = nil
        menuDragStartSceneOrientation = nil
        menuDragSessionID = nil
    }

    func placeFurnitureFromMenu(named modelName: String, at immersivePoint: Point3D) {
        guard let root = dollhouseRootEntity else {
            print("Place furniture skipped for \(modelName): immersive context is not ready.")
            return
        }

        var scenePoint = immersivePoint
        scenePoint.apply(immersiveSpaceToSceneTransform)
        let desiredWorldPosition = SIMD3<Float>(scenePoint.vector)

        Task { @MainActor in
            do {
                let furniture = try await FurnitureSceneRepository.shared.makePlacedFurniture(named: modelName)
                root.addChild(furniture)
                preserveWorldScaleForPlacedFurniture(furniture, in: root)

                var clamped = desiredWorldPosition
                if let placement = placementLimits(for: furniture) {
                    clamped.x = min(max(clamped.x, placement.minX), placement.maxX)
                    clamped.z = min(max(clamped.z, placement.minZ), placement.maxZ)
                    clamped.y = placement.y
                }
                furniture.setPosition(clamped, relativeTo: nil)
            } catch {
                print("Failed to place furniture for \(modelName): \(error.localizedDescription)")
            }
        }
    }

    func updateFurnitureManipulation(_ furniture: Entity) {
        guard furniture.components[FurnitureComponent.self] != nil else { return }
        guard menuDragEntity !== furniture else { return }
        guard let placement = placementLimits(for: furniture) else { return }

        var worldPosition = furniture.position(relativeTo: nil)
        worldPosition.x = min(max(worldPosition.x, placement.minX), placement.maxX)
        worldPosition.z = min(max(worldPosition.z, placement.minZ), placement.maxZ)
        worldPosition.y = placement.y
        furniture.setPosition(worldPosition, relativeTo: nil)
    }

    func endFurnitureManipulation(_ furniture: Entity) {
        guard furniture.components[FurnitureComponent.self] != nil else { return }
        guard menuDragEntity !== furniture else { return }
        dropDraggedFurnitureToFloor(furniture)
    }

    private func applyMenuDragTarget(
        to entity: Entity,
        constrainingTo placementEntity: Entity? = nil,
        applyingOrientation: Bool = true
    ) {
        guard let target = resolvedMenuDragTarget(constrainingTo: placementEntity) else { return }
        entity.setPosition(target.position, relativeTo: nil)
        if applyingOrientation, let orientation = target.orientation {
            entity.setOrientation(orientation, relativeTo: nil)
        }
    }

    private func resolvedMenuDragTarget(
        constrainingTo entity: Entity?
    ) -> (position: SIMD3<Float>, orientation: simd_quatf?)? {
        guard var scenePoint = menuDragTargetPoint else { return nil }
        scenePoint.apply(immersiveSpaceToSceneTransform)

        var position = SIMD3<Float>(scenePoint.vector)
        if let entity, let placement = placementLimits(for: entity) {
            position.x = min(max(position.x, placement.minX), placement.maxX)
            position.z = min(max(position.z, placement.minZ), placement.maxZ)
            position.y = placement.y
        }

        let orientation = resolvedMenuDragOrientation()
        return (position, orientation)
    }

    private func resolvedMenuDragOrientation() -> simd_quatf? {
        guard let menuDragTargetPose else { return nil }
        let currentSceneOrientation = sceneOrientationFromImmersivePose(menuDragTargetPose)
        guard let startSceneOrientation = menuDragStartSceneOrientation else {
            return .init(angle: 0, axis: [0, 1, 0])
        }
        return simd_normalize(currentSceneOrientation * simd_inverse(startSceneOrientation))
    }

    private func sceneOrientationFromImmersivePose(_ immersivePose: Pose3D) -> simd_quatf {
        let deviceOrientation = simd_quatf(immersivePose.rotation)
        guard let sceneFromImmersiveRotation = immersiveSpaceToSceneTransform.rotation else {
            return simd_normalize(deviceOrientation)
        }

        let sceneFromImmersiveOrientation = simd_quatf(sceneFromImmersiveRotation)
        return simd_normalize(sceneFromImmersiveOrientation * deviceOrientation)
    }

    private func dropDraggedFurnitureToFloor(
        _ furniture: Entity,
        resetRotationToZero: Bool = false
    ) {
        guard
            let root = dollhouseRootEntity,
            let scene = root.scene,
            let floorEntity = firstEntity(in: root, where: { candidate in
                candidate.components[FloorComponent.self] != nil
            })
        else {
            return
        }

        let furnitureBounds = furniture.visualBounds(relativeTo: nil)
        let currentPosition = furniture.position(relativeTo: nil)
        let bottomOffset = max(currentPosition.y - furnitureBounds.min.y, 0)
        let castOriginY = max(currentPosition.y + 0.5, furnitureBounds.max.y + 0.25)
        let castOrigin = SIMD3<Float>(currentPosition.x, castOriginY, currentPosition.z)

        let hits = scene.raycast(
            origin: castOrigin,
            direction: [0, -1, 0],
            length: 10.0,
            query: .all,
            mask: .all,
            relativeTo: nil
        )

        if let floorHit = hits.first(where: { hit in
            hit.entity === floorEntity || isEntity(hit.entity, descendantOf: floorEntity)
        }) {
            var droppedPosition = currentPosition
            droppedPosition.x = floorHit.position.x
            droppedPosition.z = floorHit.position.z
            droppedPosition.y = floorHit.position.y + bottomOffset
            animateFurnitureDrop(
                furniture,
                to: droppedPosition,
                resetRotationToZero: resetRotationToZero
            )

            print(
                "Dropped furniture to floor via raycast at x:\(droppedPosition.x), y:\(droppedPosition.y), z:\(droppedPosition.z)"
            )
            return
        }

        if let placement = placementLimits(for: furniture) {
            var fallbackPosition = currentPosition
            fallbackPosition.y = placement.y
            animateFurnitureDrop(
                furniture,
                to: fallbackPosition,
                resetRotationToZero: resetRotationToZero
            )

            print(
                "Raycast miss; used fallback floor height y:\(fallbackPosition.y)"
            )
        }
    }

    private func animateFurnitureDrop(
        _ furniture: Entity,
        to worldPosition: SIMD3<Float>,
        resetRotationToZero: Bool = false
    ) {
        let targetRotation: simd_quatf
        if resetRotationToZero {
            targetRotation = .init(angle: 0, axis: [0, 1, 0])
        } else {
            targetRotation = furniture.orientation(relativeTo: nil)
        }

        let targetTransform = Transform(
            scale: furniture.scale(relativeTo: nil),
            rotation: targetRotation,
            translation: worldPosition
        )
        furniture.move(
            to: targetTransform,
            relativeTo: nil,
            duration: 1.0,
            timingFunction: .linear
        )
    }

    private func preserveWorldScaleForPlacedFurniture(_ furniture: Entity, in root: Entity) {
        let rootScale = root.scale(relativeTo: nil)
        let safeRootScale = SIMD3<Float>(
            max(abs(rootScale.x), 0.0001),
            max(abs(rootScale.y), 0.0001),
            max(abs(rootScale.z), 0.0001)
        )
        let currentLocalScale = furniture.scale
        furniture.scale = SIMD3<Float>(
            currentLocalScale.x / safeRootScale.x,
            currentLocalScale.y / safeRootScale.y,
            currentLocalScale.z / safeRootScale.z
        )
    }

    private func placementLimits(
        for entity: Entity
    ) -> (minX: Float, maxX: Float, minZ: Float, maxZ: Float, y: Float)? {
        guard let root = dollhouseRootEntity else { return nil }

        let floorEntity = firstEntity(in: root) { candidate in
            candidate.components[FloorComponent.self] != nil
        }
        let floorBounds = (floorEntity ?? root).visualBounds(relativeTo: nil)
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

    private func firstEntity(
        in root: Entity,
        where predicate: (Entity) -> Bool
    ) -> Entity? {
        if predicate(root) { return root }
        for child in root.children {
            if let found = firstEntity(in: child, where: predicate) {
                return found
            }
        }
        return nil
    }

    private func isEntity(_ entity: Entity, descendantOf ancestor: Entity) -> Bool {
        var cursor: Entity? = entity
        while let current = cursor {
            if current === ancestor { return true }
            cursor = current.parent
        }
        return false
    }
}
