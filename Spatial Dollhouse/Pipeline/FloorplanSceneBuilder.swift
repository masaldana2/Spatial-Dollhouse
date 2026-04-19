import CoreGraphics
import RealityKit
import simd
import UIKit

enum FloorplanSceneBuilder {
    static func makeRootEntity(summary: FloorplanGeometrySummary, canvasSize: CGSize) -> Entity {
        let root = Entity()
        makeScenePrimitives(summary: summary, canvasSize: canvasSize)
            .map(\.entity)
            .forEach { root.addChild($0) }

        return root
    }

    static func makeExportPrimitives(summary: FloorplanGeometrySummary, canvasSize: CGSize) -> [FloorplanScenePrimitive] {
        makeScenePrimitives(summary: summary, canvasSize: canvasSize)
    }

    static func cameraTransform(for canvasSize: CGSize) -> Transform {
        cameraTransform(for: canvasSize, preset: .isometric)
    }

    static func presentationTransform(for canvasSize: CGSize, preset: FloorplanCameraPreset) -> Transform {
        Transform(matrix: simd_inverse(cameraTransform(for: canvasSize, preset: preset).matrix))
    }
}

private extension FloorplanSceneBuilder {
    static let minimumWallPieceLength: CGFloat = 0.08
    static let doorClearHeight: CGFloat = 2.15
    static let windowSillHeight: CGFloat = 0.92
    static let windowOpeningHeight: CGFloat = 1.12

    static func makeScenePrimitives(summary: FloorplanGeometrySummary, canvasSize: CGSize) -> [FloorplanScenePrimitive] {
        let planScale = scaleFactor(for: canvasSize)
        let wallHeight = CGFloat(2.8)
        let floorThickness = CGFloat(0.04)
        let openingsByWallID = Dictionary(grouping: summary.openings.compactMap { opening -> FloorplanOpeningCandidate? in
            guard opening.attachedWallID != nil else { return nil }
            return opening
        }, by: \.attachedWallID!)
        var primitives: [FloorplanScenePrimitive] = []

        primitives.append(makeFloorPrimitive(canvasSize: canvasSize, scale: planScale, thickness: floorThickness))

        primitives.append(contentsOf:
            summary.regions
                .filter { $0.kind == .room }
                .map { makeRoomPrimitive(region: $0, canvasSize: canvasSize, scale: planScale) }
        )

        primitives.append(contentsOf:
            summary.wallSegments
                .flatMap { segment in
                    makeWallPrimitives(
                        segment: segment,
                        openings: openingsByWallID[segment.id] ?? [],
                        canvasSize: canvasSize,
                        scale: planScale,
                        height: wallHeight
                    )
                }
        )

        if let mask = summary.segmentationMask {
            primitives.append(contentsOf:
                supplementalMaskWallPrimitives(
                    mask: mask,
                    existingSegments: summary.wallSegments,
                    canvasSize: canvasSize,
                    scale: planScale,
                    height: wallHeight
                )
            )
        }

        primitives.append(contentsOf:
            summary.openings.compactMap { opening in
                guard opening.attachedWallID == nil || opening.kind == .door else { return nil }
                return makeOpeningAccentPrimitive(
                    opening: opening,
                    canvasSize: canvasSize,
                    scale: planScale,
                    wallHeight: wallHeight,
                    preferSnappedPlacement: true
                )
            }
        )

        return primitives
    }

    static func scaleFactor(for canvasSize: CGSize) -> CGFloat {
        let maxDimension = max(canvasSize.width, canvasSize.height, 1)
        return 12.0 / maxDimension
    }

    static func cameraTransform(for canvasSize: CGSize, preset: FloorplanCameraPreset) -> Transform {
        let planScale = scaleFactor(for: canvasSize)
        let halfWidth = canvasSize.width * planScale / 2
        let halfLength = canvasSize.height * planScale / 2
        let distance = max(halfWidth, halfLength) * 1.8

        switch preset {
        case .isometric:
            let pitch = simd_quatf(angle: -.pi / 5.4, axis: SIMD3<Float>(1, 0, 0))
            let yaw = simd_quatf(angle: .pi / 4.5, axis: SIMD3<Float>(0, 1, 0))
            return Transform(
                scale: SIMD3<Float>(repeating: 1),
                rotation: simd_mul(yaw, pitch),
                translation: SIMD3<Float>(
                    Float(distance * 0.78),
                    Float(distance * 1.18),
                    Float(distance * 1.28)
                )
            )
        case .top:
            let pitch = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            return Transform(
                scale: SIMD3<Float>(repeating: 1),
                rotation: pitch,
                translation: SIMD3<Float>(0, Float(distance * 1.65), 0.001)
            )
        case .front:
            return Transform(
                scale: SIMD3<Float>(repeating: 1),
                rotation: simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0)),
                translation: SIMD3<Float>(0, Float(distance * 0.48), Float(distance * 1.72))
            )
        }
    }

    static func makeFloorEntity(canvasSize: CGSize, scale: CGFloat, thickness: CGFloat) -> ModelEntity {
        makeFloorPrimitive(canvasSize: canvasSize, scale: scale, thickness: thickness).entity
    }

    static func makeFloorPrimitive(canvasSize: CGSize, scale: CGFloat, thickness: CGFloat) -> FloorplanScenePrimitive {
        let width = max(canvasSize.width * scale, 0.4)
        let depth = max(canvasSize.height * scale, 0.4)
        return FloorplanScenePrimitive(
            name: "floor",
            size: SIMD3(Float(width), Float(thickness), Float(depth)),
            position: SIMD3(0, Float(-thickness / 2), 0),
            color: UIColor.secondarySystemBackground
        )
    }

    static func makeRoomEntity(region: FloorplanDetectedRegion, canvasSize: CGSize, scale: CGFloat) -> ModelEntity {
        makeRoomPrimitive(region: region, canvasSize: canvasSize, scale: scale).entity
    }

    static func makeRoomPrimitive(region: FloorplanDetectedRegion, canvasSize: CGSize, scale: CGFloat) -> FloorplanScenePrimitive {
        let width = max(region.boundingBox.width * scale, 0.05)
        let depth = max(region.boundingBox.height * scale, 0.05)
        return FloorplanScenePrimitive(
            name: "room-\(region.id)",
            size: SIMD3(Float(width), 0.02, Float(depth)),
            position: position(for: region.boundingBox.center, canvasSize: canvasSize, scale: scale, elevation: 0.01),
            color: UIColor.systemMint.withAlphaComponent(0.35)
        )
    }

    static func makeWallEntities(
        segment: FloorplanWallSegment,
        openings: [FloorplanOpeningCandidate],
        canvasSize: CGSize,
        scale: CGFloat,
        height: CGFloat
    ) -> [ModelEntity] {
        makeWallPrimitives(
            segment: segment,
            openings: openings,
            canvasSize: canvasSize,
            scale: scale,
            height: height
        ).map(\.entity)
    }

    static func makeWallPrimitives(
        segment: FloorplanWallSegment,
        openings: [FloorplanOpeningCandidate],
        canvasSize: CGSize,
        scale: CGFloat,
        height: CGFloat
    ) -> [FloorplanScenePrimitive] {
        let minimumPieceLengthInSource = minimumWallPieceLength / max(scale, 0.0001)
        let attachedOpenings = openingCuts(for: segment, openings: openings, scale: scale)
        guard !attachedOpenings.isEmpty else {
            return [makeWallPrismPrimitive(
                axis: segment.axis,
                center: segment.center,
                primaryLength: segment.length * scale,
                thickness: segment.thickness * scale,
                height: height,
                canvasSize: canvasSize,
                scale: scale,
                color: UIColor(red: 0.19, green: 0.40, blue: 0.24, alpha: 1.0),
                name: "wall-\(segment.id)"
            )]
        }

        let wallRange = primaryRange(for: segment)
        let orderedOpenings = attachedOpenings.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var cursor = wallRange.lowerBound
        var primitives: [FloorplanScenePrimitive] = []

        for opening in orderedOpenings {
            if opening.range.lowerBound - cursor >= minimumPieceLengthInSource {
                let midpoint = (cursor + opening.range.lowerBound) / 2
                let center = point(
                    on: segment,
                    primaryValue: midpoint
                )
                primitives.append(
                    makeWallPrismPrimitive(
                        axis: segment.axis,
                        center: center,
                        primaryLength: (opening.range.lowerBound - cursor) * scale,
                        thickness: segment.thickness * scale,
                        height: height,
                        canvasSize: canvasSize,
                        scale: scale,
                        color: UIColor(red: 0.19, green: 0.40, blue: 0.24, alpha: 1.0),
                        name: "wall-\(segment.id)-\(opening.id)-leading"
                    )
                )
            }

            primitives.append(contentsOf:
                contentsForOpeningPrimitives(
                    opening,
                    on: segment,
                    canvasSize: canvasSize,
                    scale: scale,
                    wallHeight: height
                )
            )

            cursor = max(cursor, opening.range.upperBound)
        }

        if wallRange.upperBound - cursor >= minimumPieceLengthInSource {
            let midpoint = (cursor + wallRange.upperBound) / 2
            let center = point(on: segment, primaryValue: midpoint)
            primitives.append(
                makeWallPrismPrimitive(
                    axis: segment.axis,
                    center: center,
                    primaryLength: (wallRange.upperBound - cursor) * scale,
                    thickness: segment.thickness * scale,
                    height: height,
                    canvasSize: canvasSize,
                    scale: scale,
                    color: UIColor(red: 0.19, green: 0.40, blue: 0.24, alpha: 1.0),
                    name: "wall-\(segment.id)-tail"
                )
            )
        }

        return primitives
    }

    static func makeWallPrism(
        axis: WallAxis,
        center: CGPoint,
        primaryLength: CGFloat,
        thickness: CGFloat,
        height: CGFloat,
        canvasSize: CGSize,
        scale: CGFloat,
        color: UIColor
    ) -> ModelEntity {
        makeWallPrismPrimitive(
            axis: axis,
            center: center,
            primaryLength: primaryLength,
            thickness: thickness,
            height: height,
            canvasSize: canvasSize,
            scale: scale,
            color: color,
            name: "wall-prism"
        ).entity
    }

    static func makeWallPrismPrimitive(
        axis: WallAxis,
        center: CGPoint,
        primaryLength: CGFloat,
        thickness: CGFloat,
        height: CGFloat,
        canvasSize: CGSize,
        scale: CGFloat,
        color: UIColor,
        name: String
    ) -> FloorplanScenePrimitive {
        let jointOverlap = max(thickness * 0.6, 0.02)
        let width: CGFloat
        let depth: CGFloat

        switch axis {
        case .horizontal:
            width = max(primaryLength + jointOverlap, 0.04)
            depth = max(thickness, 0.05)
        case .vertical:
            width = max(thickness, 0.05)
            depth = max(primaryLength + jointOverlap, 0.04)
        }

        return FloorplanScenePrimitive(
            name: name,
            size: SIMD3(Float(width), Float(height), Float(depth)),
            position: position(for: center, canvasSize: canvasSize, scale: scale, elevation: height / 2),
            color: color
        )
    }

    static func supplementalMaskWallEntities(
        mask: FloorplanSegmentationMask,
        existingSegments: [FloorplanWallSegment],
        canvasSize: CGSize,
        scale: CGFloat,
        height: CGFloat
    ) -> [ModelEntity] {
        supplementalMaskWallPrimitives(
            mask: mask,
            existingSegments: existingSegments,
            canvasSize: canvasSize,
            scale: scale,
            height: height
        ).map(\.entity)
    }

    static func supplementalMaskWallPrimitives(
        mask: FloorplanSegmentationMask,
        existingSegments: [FloorplanWallSegment],
        canvasSize: CGSize,
        scale: CGFloat,
        height: CGFloat
    ) -> [FloorplanScenePrimitive] {
        let scaleX = canvasSize.width / CGFloat(mask.width)
        let scaleY = canvasSize.height / CGFloat(mask.height)
        let horizontalRuns = collectMaskRuns(in: mask, axis: .horizontal, minimumLength: 12)
        let verticalRuns = collectMaskRuns(in: mask, axis: .vertical, minimumLength: 12)

        let supplementalHorizontal = horizontalRuns.compactMap { run -> FloorplanScenePrimitive? in
            let centerY = (CGFloat(run.cross) + 0.5) * scaleY
            let startX = CGFloat(run.start) * scaleX
            let endX = CGFloat(run.end + 1) * scaleX
            let center = CGPoint(x: (startX + endX) / 2, y: centerY)
            let length = endX - startX
            let thickness = max(scaleY, 1)

            guard !isCoveredByExistingWall(
                axis: .horizontal,
                center: center,
                primaryRange: startX ... endX,
                thickness: thickness,
                segments: existingSegments
            ) else { return nil }

            return makeWallPrismPrimitive(
                axis: .horizontal,
                center: center,
                primaryLength: length * scale,
                thickness: thickness * scale,
                height: height,
                canvasSize: canvasSize,
                scale: scale,
                color: UIColor(red: 0.19, green: 0.40, blue: 0.24, alpha: 1.0),
                name: "mask-wall-h-\(run.cross)-\(run.start)-\(run.end)"
            )
        }

        let supplementalVertical = verticalRuns.compactMap { run -> FloorplanScenePrimitive? in
            let centerX = (CGFloat(run.cross) + 0.5) * scaleX
            let startY = CGFloat(run.start) * scaleY
            let endY = CGFloat(run.end + 1) * scaleY
            let center = CGPoint(x: centerX, y: (startY + endY) / 2)
            let length = endY - startY
            let thickness = max(scaleX, 1)

            guard !isCoveredByExistingWall(
                axis: .vertical,
                center: center,
                primaryRange: startY ... endY,
                thickness: thickness,
                segments: existingSegments
            ) else { return nil }

            return makeWallPrismPrimitive(
                axis: .vertical,
                center: center,
                primaryLength: length * scale,
                thickness: thickness * scale,
                height: height,
                canvasSize: canvasSize,
                scale: scale,
                color: UIColor(red: 0.19, green: 0.40, blue: 0.24, alpha: 1.0),
                name: "mask-wall-v-\(run.cross)-\(run.start)-\(run.end)"
            )
        }

        return supplementalHorizontal + supplementalVertical
    }

    static func collectMaskRuns(in mask: FloorplanSegmentationMask, axis: WallAxis, minimumLength: Int) -> [LinearRun] {
        var runs: [LinearRun] = []

        switch axis {
        case .horizontal:
            for y in 0 ..< mask.height {
                var x = 0
                while x < mask.width {
                    while x < mask.width, mask.classID(atX: x, y: y) != 1 {
                        x += 1
                    }
                    let start = x
                    while x < mask.width, mask.classID(atX: x, y: y) == 1 {
                        x += 1
                    }
                    let end = x - 1
                    if end >= start, (end - start + 1) >= minimumLength {
                        runs.append(LinearRun(start: start, end: end, cross: y))
                    }
                }
            }
        case .vertical:
            for x in 0 ..< mask.width {
                var y = 0
                while y < mask.height {
                    while y < mask.height, mask.classID(atX: x, y: y) != 1 {
                        y += 1
                    }
                    let start = y
                    while y < mask.height, mask.classID(atX: x, y: y) == 1 {
                        y += 1
                    }
                    let end = y - 1
                    if end >= start, (end - start + 1) >= minimumLength {
                        runs.append(LinearRun(start: start, end: end, cross: x))
                    }
                }
            }
        }

        return runs
    }

    static func isCoveredByExistingWall(
        axis: WallAxis,
        center: CGPoint,
        primaryRange: ClosedRange<CGFloat>,
        thickness: CGFloat,
        segments: [FloorplanWallSegment]
    ) -> Bool {
        segments.contains { segment in
            guard segment.axis == axis else { return false }

            switch axis {
            case .horizontal:
                let segmentRange = min(segment.start.x, segment.end.x) ... max(segment.start.x, segment.end.x)
                let overlap = max(0, min(segmentRange.upperBound, primaryRange.upperBound) - max(segmentRange.lowerBound, primaryRange.lowerBound))
                let alignment = abs(segment.center.y - center.y)
                return overlap >= (primaryRange.upperBound - primaryRange.lowerBound) * 0.75 &&
                    alignment <= max(segment.thickness, thickness) * 1.5
            case .vertical:
                let segmentRange = min(segment.start.y, segment.end.y) ... max(segment.start.y, segment.end.y)
                let overlap = max(0, min(segmentRange.upperBound, primaryRange.upperBound) - max(segmentRange.lowerBound, primaryRange.lowerBound))
                let alignment = abs(segment.center.x - center.x)
                return overlap >= (primaryRange.upperBound - primaryRange.lowerBound) * 0.75 &&
                    alignment <= max(segment.thickness, thickness) * 1.5
            }
        }
    }

    static func makeOpeningAccentEntity(
        opening: FloorplanOpeningCandidate,
        canvasSize: CGSize,
        scale: CGFloat,
        wallHeight: CGFloat,
        preferSnappedPlacement: Bool
    ) -> ModelEntity? {
        makeOpeningAccentPrimitive(
            opening: opening,
            canvasSize: canvasSize,
            scale: scale,
            wallHeight: wallHeight,
            preferSnappedPlacement: preferSnappedPlacement
        )?.entity
    }

    static func makeOpeningAccentPrimitive(
        opening: FloorplanOpeningCandidate,
        canvasSize: CGSize,
        scale: CGFloat,
        wallHeight: CGFloat,
        preferSnappedPlacement: Bool
    ) -> FloorplanScenePrimitive? {
        let center = preferSnappedPlacement ? (opening.snappedCenter ?? opening.center) : opening.center
        let span = max(opening.span * scale, 0.12)

        let color: UIColor
        switch opening.kind {
        case .door:
            guard !preferSnappedPlacement || opening.attachedWallID == nil else { return makeDoorThresholdPrimitive(opening: opening, canvasSize: canvasSize, scale: scale) }
            color = UIColor.systemOrange.withAlphaComponent(0.92)
        case .window:
            color = UIColor.systemBlue.withAlphaComponent(0.82)
        case .room:
            return nil
        }

        let width = opening.axis == .horizontal ? span : 0.04
        let depth = opening.axis == .vertical ? span : 0.04
        let height = opening.kind == .door ? wallHeight * 0.75 : wallHeight * 0.35
        let elevation = opening.kind == .door ? height / 2 : wallHeight * 0.62
        return FloorplanScenePrimitive(
            name: "\(opening.kind.rawValue)-accent-\(opening.id)",
            size: SIMD3(Float(width), Float(height), Float(depth)),
            position: position(for: center, canvasSize: canvasSize, scale: scale, elevation: elevation),
            color: color
        )
    }

    static func makeDoorThresholdEntity(
        opening: FloorplanOpeningCandidate,
        canvasSize: CGSize,
        scale: CGFloat
    ) -> ModelEntity? {
        makeDoorThresholdPrimitive(opening: opening, canvasSize: canvasSize, scale: scale)?.entity
    }

    static func makeDoorThresholdPrimitive(
        opening: FloorplanOpeningCandidate,
        canvasSize: CGSize,
        scale: CGFloat
    ) -> FloorplanScenePrimitive? {
        let center = opening.snappedCenter ?? opening.center
        let span = max(opening.span * scale, 0.12)
        let width = opening.axis == .horizontal ? span : 0.03
        let depth = opening.axis == .vertical ? span : 0.03
        return FloorplanScenePrimitive(
            name: "door-threshold-\(opening.id)",
            size: SIMD3(Float(width), 0.01, Float(depth)),
            position: position(for: center, canvasSize: canvasSize, scale: scale, elevation: 0.005),
            color: UIColor.systemOrange.withAlphaComponent(0.9)
        )
    }

    static func contentsForOpening(
        _ opening: OpeningCut,
        on segment: FloorplanWallSegment,
        canvasSize: CGSize,
        scale: CGFloat,
        wallHeight: CGFloat
    ) -> [ModelEntity] {
        contentsForOpeningPrimitives(
            opening,
            on: segment,
            canvasSize: canvasSize,
            scale: scale,
            wallHeight: wallHeight
        ).map(\.entity)
    }

    static func contentsForOpeningPrimitives(
        _ opening: OpeningCut,
        on segment: FloorplanWallSegment,
        canvasSize: CGSize,
        scale: CGFloat,
        wallHeight: CGFloat
    ) -> [FloorplanScenePrimitive] {
        switch opening.kind {
        case .door:
            let clearHeight = min(doorClearHeight, wallHeight - 0.18)
            let headerHeight = max(wallHeight - clearHeight, 0.18)
            let openingCenter = point(on: segment, primaryValue: opening.centerPrimary)
            var header = makeWallPrismPrimitive(
                axis: segment.axis,
                center: openingCenter,
                primaryLength: (opening.range.upperBound - opening.range.lowerBound) * scale,
                thickness: segment.thickness * scale,
                height: headerHeight,
                canvasSize: canvasSize,
                scale: scale,
                color: UIColor(red: 0.19, green: 0.40, blue: 0.24, alpha: 1.0),
                name: "door-header-\(segment.id)-\(opening.id)"
            )
            header.position.y = Float(clearHeight + (headerHeight / 2))
            return [header]
        case .window:
            let sillHeight = min(windowSillHeight, wallHeight * 0.45)
            let openingHeight = min(windowOpeningHeight, wallHeight - sillHeight - 0.22)
            let upperHeight = max(wallHeight - sillHeight - openingHeight, 0.18)
            let openingCenter = point(on: segment, primaryValue: opening.centerPrimary)
            var lowerPiece = makeWallPrismPrimitive(
                axis: segment.axis,
                center: openingCenter,
                primaryLength: (opening.range.upperBound - opening.range.lowerBound) * scale,
                thickness: segment.thickness * scale,
                height: sillHeight,
                canvasSize: canvasSize,
                scale: scale,
                color: UIColor(red: 0.19, green: 0.40, blue: 0.24, alpha: 1.0),
                name: "window-lower-\(segment.id)-\(opening.id)"
            )
            lowerPiece.position.y = Float(sillHeight / 2)

            var upperPiece = makeWallPrismPrimitive(
                axis: segment.axis,
                center: openingCenter,
                primaryLength: (opening.range.upperBound - opening.range.lowerBound) * scale,
                thickness: segment.thickness * scale,
                height: upperHeight,
                canvasSize: canvasSize,
                scale: scale,
                color: UIColor(red: 0.19, green: 0.40, blue: 0.24, alpha: 1.0),
                name: "window-upper-\(segment.id)-\(opening.id)"
            )
            upperPiece.position.y = Float(sillHeight + openingHeight + (upperHeight / 2))

            let glassThickness = max(min(segment.thickness * scale * 0.28, 0.025), 0.012)
            let glassPrimary = max((opening.range.upperBound - opening.range.lowerBound) * scale, 0.12)
            var glass = makeWallPrismPrimitive(
                axis: segment.axis,
                center: openingCenter,
                primaryLength: glassPrimary,
                thickness: glassThickness,
                height: openingHeight,
                canvasSize: canvasSize,
                scale: scale,
                color: UIColor.systemBlue.withAlphaComponent(0.36),
                name: "window-glass-\(segment.id)-\(opening.id)"
            )
            glass.position.y = Float(sillHeight + (openingHeight / 2))
            return [lowerPiece, upperPiece, glass]
        case .room:
            return []
        }
    }

    static func openingCuts(
        for segment: FloorplanWallSegment,
        openings: [FloorplanOpeningCandidate],
        scale: CGFloat
    ) -> [OpeningCut] {
        let wallRange = primaryRange(for: segment)

        return openings.compactMap { opening in
            guard let snappedStart = opening.snappedStart, let snappedEnd = opening.snappedEnd else { return nil }
            let lower: CGFloat
            let upper: CGFloat

            switch segment.axis {
            case .horizontal:
                lower = min(snappedStart.x, snappedEnd.x)
                upper = max(snappedStart.x, snappedEnd.x)
            case .vertical:
                lower = min(snappedStart.y, snappedEnd.y)
                upper = max(snappedStart.y, snappedEnd.y)
            }

            let clampedLower = max(wallRange.lowerBound, lower)
            let clampedUpper = min(wallRange.upperBound, upper)
            guard clampedUpper - clampedLower >= (minimumWallPieceLength / max(scale, 0.0001)) else { return nil }

            let centerPrimary = (clampedLower + clampedUpper) / 2
            return OpeningCut(
                id: opening.id,
                kind: opening.kind,
                range: clampedLower ... clampedUpper,
                centerPrimary: centerPrimary
            )
        }
    }

    static func primaryRange(for segment: FloorplanWallSegment) -> ClosedRange<CGFloat> {
        switch segment.axis {
        case .horizontal:
            return min(segment.start.x, segment.end.x) ... max(segment.start.x, segment.end.x)
        case .vertical:
            return min(segment.start.y, segment.end.y) ... max(segment.start.y, segment.end.y)
        }
    }

    static func point(on segment: FloorplanWallSegment, primaryValue: CGFloat) -> CGPoint {
        switch segment.axis {
        case .horizontal:
            return CGPoint(x: primaryValue, y: segment.center.y)
        case .vertical:
            return CGPoint(x: segment.center.x, y: primaryValue)
        }
    }

    static func position(for point: CGPoint, canvasSize: CGSize, scale: CGFloat, elevation: CGFloat) -> SIMD3<Float> {
        let centeredX = (point.x - (canvasSize.width / 2)) * scale
        let centeredZ = (point.y - (canvasSize.height / 2)) * scale
        return SIMD3(Float(centeredX), Float(elevation), Float(centeredZ))
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private struct OpeningCut {
    let id: String
    let kind: FloorplanRegionKind
    let range: ClosedRange<CGFloat>
    let centerPrimary: CGFloat
}

private struct LinearRun {
    let start: Int
    let end: Int
    let cross: Int
}

struct FloorplanScenePrimitive {
    let name: String
    let size: SIMD3<Float>
    var position: SIMD3<Float>
    let color: UIColor

    var entity: ModelEntity {
        let mesh = MeshResource.generateBox(size: size)
        let material = SimpleMaterial(color: color, roughness: 0.84, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        entity.name = name
        return entity
    }
}
