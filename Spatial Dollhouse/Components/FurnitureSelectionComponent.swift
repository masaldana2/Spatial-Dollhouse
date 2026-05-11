//
//  FurnitureSelectionComponent.swift
//  Spatial Dollhouse
//

import Foundation
import RealityKit

struct FurnitureSelectionComponent: Component, Codable {
    var selectedAt: TimeInterval

    init(selectedAt: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        self.selectedAt = selectedAt
    }
}
