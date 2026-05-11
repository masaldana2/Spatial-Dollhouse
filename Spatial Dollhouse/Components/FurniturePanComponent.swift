//
//  FurniturePanComponent.swift
//  Spatial Dollhouse
//

import RealityKit

struct FurniturePanComponent: Component, Codable {
    var targetWorldPosition: SIMD3<Float>
    var offsetXZ: SIMD2<Float>
    var hasOffset: Bool
    var isActive: Bool

    init(
        targetWorldPosition: SIMD3<Float>,
        offsetXZ: SIMD2<Float> = .zero,
        hasOffset: Bool = false,
        isActive: Bool = true
    ) {
        self.targetWorldPosition = targetWorldPosition
        self.offsetXZ = offsetXZ
        self.hasOffset = hasOffset
        self.isActive = isActive
    }
}
