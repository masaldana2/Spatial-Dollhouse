//
//  FloorplanDollhouseBuilder.swift
//  Spatial Dollhouse
//
//  Created by Codex on 4/3/26.
//

import CoreGraphics
import RealityKit

struct FloorplanDollhouseBuilder {
    static func build(from image: CGImage) throws -> Entity {
        try DollhouseGenerationManager().build(from: image)
    }
}
