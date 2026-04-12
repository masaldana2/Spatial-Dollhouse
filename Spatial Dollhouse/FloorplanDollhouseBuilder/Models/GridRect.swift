//
//  GridRect.swift
//  Spatial Dollhouse
//

struct GridRect: Hashable, Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var area: Int {
        width * height
    }

    var maxDimension: Int {
        max(width, height)
    }

    var minDimension: Int {
        min(width, height)
    }
}
