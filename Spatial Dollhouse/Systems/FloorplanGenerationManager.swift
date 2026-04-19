//
//  FloorplanGenerationManager.swift
//  Spatial Dollhouse
//

import CoreGraphics
import RealityKit

final class DollhouseGenerationManager {
    private let config: DollhouseBuildConfig
    private let parser: FloorplanSemanticParser

    init(
        config: DollhouseBuildConfig = .init(),
        parser: FloorplanSemanticParser = .init()
    ) {
        self.config = config
        self.parser = parser
    }

    func build(from geometrySummary: FloorplanGeometrySummary, canvasSize: CGSize) throws -> Entity {
        let model = FloorplanSemanticModel(
            summary: geometrySummary,
            canvasSize: canvasSize,
            cellSize: config.cellSize
        )
        return try build(from: model)
    }

    /// Legacy prototype path kept only as reference. The active product path is
    /// `CoreML -> geometry extraction -> DollhouseGenerationManager.build(from:canvasSize:)`.
    @available(*, deprecated, message: "Legacy prototype. Build from CoreML-derived geometry instead.")
    func build(from image: CGImage) throws -> Entity {
        let model = try parser.parse(image: image, config: config)
        return try build(from: model)
    }

    private func build(from model: FloorplanSemanticModel) throws -> Entity {
        guard !model.walls.isEmpty else {
            throw FloorplanDollhouseBuilderError.noWallsDetected
        }

        let root = Entity()
        root.position = config.rootPosition
        root.scale = [config.dollhouseScale, config.dollhouseScale, config.dollhouseScale]

        var spawnSequence = 0
        func enqueueWithSpawnAnimation(_ entity: Entity) {
            entity.components.set(SpawnAnimationComponent(sequenceIndex: spawnSequence))
            spawnSequence += 1
            root.addChild(entity)
        }

        enqueueWithSpawnAnimation(makeFloorRequest(for: model))

        for rect in model.walls {
            enqueueWithSpawnAnimation(makeWallRequest(for: rect, in: model))
        }

        for rect in model.doors where rect.area >= 4 && rect.maxDimension >= 4 {
            enqueueWithSpawnAnimation(makeDoorRequest(for: rect, in: model))
        }

        for rect in model.windows {
            enqueueWithSpawnAnimation(makeWindowRequest(for: rect, in: model))
        }

        return root
    }

    private func makeFloorRequest(for model: FloorplanSemanticModel) -> Entity {
        let floor = Entity()
        let floorWidth = Float(model.gridWidth) * config.metersPerCell
        let floorDepth = Float(model.gridHeight) * config.metersPerCell

        floor.position = [0, -config.floorThickness * 0.5, 0]
        floor.components.set(
            FloorRequestComponent(
                width: floorWidth,
                depth: floorDepth,
                thickness: config.floorThickness,
                cornerRadius: config.metersPerCell * 0.4
            )
        )

        return floor
    }

    private func makeWallRequest(for rect: GridRect, in model: FloorplanSemanticModel) -> Entity {
        let wall = Entity()
        let width = max(Float(rect.width) * config.metersPerCell, config.metersPerCell * 0.8)
        let depth = max(Float(rect.height) * config.metersPerCell, config.metersPerCell * 0.8)

        wall.position = worldPosition(
            for: rect,
            gridWidth: model.gridWidth,
            gridHeight: model.gridHeight,
            metersPerCell: config.metersPerCell,
            y: config.wallHeight * 0.5
        )

        wall.components.set(
            WallRequestComponent(
                width: width,
                depth: depth,
                height: config.wallHeight,
                cornerRadius: min(config.metersPerCell * 0.22, 0.02),
                rect: rect,
                outsideLeft: rect.x == 0,
                outsideRight: (rect.x + rect.width) >= model.gridWidth,
                outsideTop: rect.y == 0,
                outsideBottom: (rect.y + rect.height) >= model.gridHeight
            )
        )

        return wall
    }

    private func makeDoorRequest(for rect: GridRect, in model: FloorplanSemanticModel) -> Entity {
        let door = Entity()
        let openingSpan = Float(max(rect.width, rect.height)) * config.metersPerCell
        let wallThickness = nearestWallThickness(for: rect, walls: model.walls)
            ?? (config.metersPerCell * 0.8)
        let isVerticalRect = rect.height > rect.width
        let width = isVerticalRect ? wallThickness : openingSpan
        let depth = isVerticalRect ? openingSpan : wallThickness

        door.position = worldPosition(
            for: rect,
            gridWidth: model.gridWidth,
            gridHeight: model.gridHeight,
            metersPerCell: config.metersPerCell,
            y: config.wallHeight * 0.5
        )
        let axisAngle = isVerticalRect ? (Float.pi * 0.5) : 0.0
        door.orientation = simd_quatf(angle: axisAngle, axis: [0, 1, 0])

        door.components.set(
            DoorRequestComponent(
                width: width,
                depth: depth,
                height: config.wallHeight,
                cornerRadius: min(config.metersPerCell * 0.15, 0.015),
                rect: rect,
                initiallyOpen: false
            )
        )

        return door
    }

    private func makeWindowRequest(for rect: GridRect, in model: FloorplanSemanticModel) -> Entity {
        let window = Entity()
        let width = max(Float(rect.width) * config.metersPerCell, config.metersPerCell * 0.7)
        let depth = max(Float(rect.height) * config.metersPerCell, config.metersPerCell * 0.7)

        window.position = worldPosition(
            for: rect,
            gridWidth: model.gridWidth,
            gridHeight: model.gridHeight,
            metersPerCell: config.metersPerCell,
            y: config.wallHeight * 0.5
        )

        window.components.set(
            WindowRequestComponent(
                width: width,
                depth: depth,
                height: config.wallHeight,
                cornerRadius: min(config.metersPerCell * 0.15, 0.015),
                rect: rect,
                sillHeight: config.windowBottom
            )
        )

        return window
    }

    private func nearestWallThickness(for doorRect: GridRect, walls: [GridRect]) -> Float? {
        guard !walls.isEmpty else { return nil }

        let center = SIMD2<Float>(
            Float(doorRect.x) + (Float(doorRect.width) * 0.5),
            Float(doorRect.y) + (Float(doorRect.height) * 0.5)
        )

        var bestThickness: Float?
        var bestDistanceSquared = Float.greatestFiniteMagnitude

        for wall in walls {
            let minX = Float(wall.x)
            let maxX = Float(wall.x + wall.width)
            let minY = Float(wall.y)
            let maxY = Float(wall.y + wall.height)

            let dx: Float
            if center.x < minX {
                dx = minX - center.x
            } else if center.x > maxX {
                dx = center.x - maxX
            } else {
                dx = 0
            }

            let dy: Float
            if center.y < minY {
                dy = minY - center.y
            } else if center.y > maxY {
                dy = center.y - maxY
            } else {
                dy = 0
            }

            let distanceSquared = (dx * dx) + (dy * dy)
            guard distanceSquared < bestDistanceSquared else { continue }

            let wallWidth = max(Float(wall.width) * config.metersPerCell, config.metersPerCell * 0.8)
            let wallDepth = max(Float(wall.height) * config.metersPerCell, config.metersPerCell * 0.8)
            bestThickness = min(wallWidth, wallDepth)
            bestDistanceSquared = distanceSquared
        }

        return bestThickness
    }
}

private func worldPosition(
    for rect: GridRect,
    gridWidth: Int,
    gridHeight: Int,
    metersPerCell: Float,
    y: Float
) -> SIMD3<Float> {
    let centerX = (Float(rect.x) + Float(rect.width) * 0.5) - (Float(gridWidth) * 0.5)
    let centerZ = (Float(gridHeight) * 0.5) - (Float(rect.y) + Float(rect.height) * 0.5)

    return [centerX * metersPerCell, y, centerZ * metersPerCell]
}
