//
//  DollhouseBuildConfig.swift
//  Spatial Dollhouse
//

import simd

struct DollhouseBuildConfig {
    var cellSize: Int = 4
    var metersPerCell: Float = 0.04
    var wallHeight: Float = 2.6
    var floorThickness: Float = 0.03
    var doorHeight: Float = 2.1
    var windowHeight: Float = 1.05
    var windowBottom: Float = 0.95
    var dollhouseScale: Float = 0.1
    var rootPosition: SIMD3<Float> = [0, -1.12, -1.45]
}
