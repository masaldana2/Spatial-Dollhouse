//
//  FloorplanSemanticModel.swift
//  Spatial Dollhouse
//

struct FloorplanSemanticModel {
    let gridWidth: Int
    let gridHeight: Int
    let walls: [GridRect]
    let doors: [GridRect]
    let windows: [GridRect]
}
