//
//  WallComponent.swift
//  Spatial Dollhouse
//

import RealityKit
import UIKit

struct WallComponent: Component, Codable {
    var rect: GridRect // rect and bounds are the same, remove one
    let bounds: CGRect
    let pixelCount: Int
    
    init(rect: GridRect = GridRect(x: 0, y: 0, width: 0, height: 0), bounds: CGRect = .zero, pixelCount: Int = 0) {
        self.rect = rect
        self.bounds = bounds
        self.pixelCount = pixelCount
    }

    var isPrimarilyVertical: Bool {
        bounds.height >= max(bounds.width * 2, 12)
    }

    var isPrimarilyHorizontal: Bool {
        bounds.width >= max(bounds.height * 2, 12)
    }

    var isMostlyVertical: Bool {
        bounds.height >= max(bounds.width * 1.35, 10)
    }

    var isMostlyHorizontal: Bool {
        bounds.width >= max(bounds.height * 1.35, 10)
    }
}
