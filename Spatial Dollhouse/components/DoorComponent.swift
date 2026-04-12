//
//  DoorComponent.swift
//  Spatial Dollhouse
//

import RealityKit

struct DoorComponent: Component, Codable {
    var rect: GridRect
    var isOpen: Bool
}
