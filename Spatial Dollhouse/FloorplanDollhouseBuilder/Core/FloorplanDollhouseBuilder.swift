//
//  FloorplanDollhouseBuilder.swift
//  Spatial Dollhouse
//
//  Created by Codex on 4/3/26.
//

import CoreGraphics
import RealityKit

struct FloorplanDollhouseBuilder {
    static func build(from scene: StoredFloorplanScene) throws -> Entity {
        try DollhouseGenerationManager().build(
            from: scene.geometrySummary,
            canvasSize: scene.canvasSize
        )
    }

    /// Legacy prototype path kept only as reference while the scene builder is
    /// migrated away from direct image parsing. Production code should build
    /// from CoreML-derived geometry using `build(from scene:)`.
    @available(*, deprecated, message: "Legacy prototype. Build from StoredFloorplanScene instead.")
    static func build(from image: CGImage) throws -> Entity {
        try DollhouseGenerationManager().build(from: image)
    }
}
