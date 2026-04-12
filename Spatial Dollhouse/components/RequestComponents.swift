//
//  RequestComponents.swift
//  Spatial Dollhouse
//

import RealityKit

struct FloorRequestComponent: Component, Codable {
    var width: Float
    var depth: Float
    var thickness: Float
    var cornerRadius: Float
}

struct WallRequestComponent: Component, Codable {
    var width: Float
    var depth: Float
    var height: Float
    var cornerRadius: Float
    var rect: GridRect
    var outsideLeft: Bool
    var outsideRight: Bool
    var outsideTop: Bool
    var outsideBottom: Bool
}

struct DoorRequestComponent: Component, Codable {
    var width: Float
    var depth: Float
    var height: Float
    var cornerRadius: Float
    var rect: GridRect
    var initiallyOpen: Bool
}

struct WindowRequestComponent: Component, Codable {
    var width: Float
    var depth: Float
    var height: Float
    var cornerRadius: Float
    var rect: GridRect
    var sillHeight: Float
}

struct SpawnAnimationComponent: Component, Codable {
    var sequenceIndex: Int
}
