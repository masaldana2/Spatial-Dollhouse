import CoreGraphics

enum FloorplanGeometryExtractor {
    static func extract(from mask: FloorplanSegmentationMask, sourceSize: CGSize) -> FloorplanGeometrySummary {
        let roomRegions = connectedComponents(in: mask, matching: 4, minimumPixelArea: 1_000, sourceSize: sourceSize, prefix: "R")
        let doorRegions = connectedComponents(in: mask, matching: 2, minimumPixelArea: 40, sourceSize: sourceSize, prefix: "D")
        let windowRegions = connectedComponents(in: mask, matching: 3, minimumPixelArea: 40, sourceSize: sourceSize, prefix: "W")

        let wallPixels = mask.classIDs.reduce(into: 0) { count, classID in
            if classID == 1 {
                count += 1
            }
        }
        let totalPixels = max(mask.width * mask.height, 1)
        let rawWallSegments = extractWallSegments(from: mask, sourceSize: sourceSize)
        let refinedNetwork = refineWallNetwork(rawWallSegments, mask: mask, sourceSize: sourceSize)
        let openings = anchoredOpenings(from: doorRegions + windowRegions, onto: refinedNetwork.segments)

        return FloorplanGeometrySummary(
            roomCount: roomRegions.count,
            doorCount: doorRegions.count,
            windowCount: windowRegions.count,
            wallCoverage: Double(wallPixels) / Double(totalPixels),
            segmentationMask: mask,
            regions: roomRegions + doorRegions + windowRegions,
            wallSegments: refinedNetwork.segments,
            junctions: refinedNetwork.junctions,
            openings: openings
        )
    }

    private static func connectedComponents(
        in mask: FloorplanSegmentationMask,
        matching targetClassID: UInt8,
        minimumPixelArea: Int,
        sourceSize: CGSize,
        prefix: String
    ) -> [FloorplanDetectedRegion] {
        var visited = [Bool](repeating: false, count: mask.width * mask.height)
        var regions: [FloorplanDetectedRegion] = []
        var runningIndex = 1

        for y in 0 ..< mask.height {
            for x in 0 ..< mask.width {
                let flatIndex = (y * mask.width) + x
                guard !visited[flatIndex], mask.classID(atX: x, y: y) == targetClassID else {
                    continue
                }

                var queue = [(x: Int, y: Int)]()
                queue.reserveCapacity(128)
                queue.append((x, y))
                visited[flatIndex] = true

                var queueIndex = 0
                var pixelArea = 0
                var minX = x
                var minY = y
                var maxX = x
                var maxY = y

                while queueIndex < queue.count {
                    let current = queue[queueIndex]
                    queueIndex += 1
                    pixelArea += 1

                    minX = min(minX, current.x)
                    minY = min(minY, current.y)
                    maxX = max(maxX, current.x)
                    maxY = max(maxY, current.y)

                    for neighbor in neighbors(of: current, width: mask.width, height: mask.height) {
                        let neighborIndex = (neighbor.y * mask.width) + neighbor.x
                        guard !visited[neighborIndex], mask.classID(atX: neighbor.x, y: neighbor.y) == targetClassID else {
                            continue
                        }

                        visited[neighborIndex] = true
                        queue.append(neighbor)
                    }
                }

                guard pixelArea >= minimumPixelArea else {
                    continue
                }

                let scaleX = sourceSize.width / CGFloat(mask.width)
                let scaleY = sourceSize.height / CGFloat(mask.height)
                let box = CGRect(
                    x: CGFloat(minX) * scaleX,
                    y: CGFloat(minY) * scaleY,
                    width: CGFloat(maxX - minX + 1) * scaleX,
                    height: CGFloat(maxY - minY + 1) * scaleY
                )

                let kind: FloorplanRegionKind = switch targetClassID {
                case 2: .door
                case 3: .window
                default: .room
                }

                regions.append(
                    FloorplanDetectedRegion(
                        id: "\(prefix)\(runningIndex)",
                        kind: kind,
                        boundingBox: box,
                        pixelArea: pixelArea
                    )
                )
                runningIndex += 1
            }
        }

        return regions.sorted { lhs, rhs in
            lhs.pixelArea > rhs.pixelArea
        }
    }

    private static func extractWallSegments(from mask: FloorplanSegmentationMask, sourceSize: CGSize) -> [FloorplanWallSegment] {
        let horizontalRuns = collectContourRuns(in: mask, axis: .horizontal, minimumLength: 24)
        let verticalRuns = collectContourRuns(in: mask, axis: .vertical, minimumLength: 24)

        let horizontalBands = merge(runs: horizontalRuns, axis: .horizontal)
        let verticalBands = merge(runs: verticalRuns, axis: .vertical)

        let scaleX = sourceSize.width / CGFloat(mask.width)
        let scaleY = sourceSize.height / CGFloat(mask.height)

        let horizontalSegments = horizontalBands.enumerated().compactMap { index, band in
            makeSegment(id: "H\(index + 1)", band: band, scaleX: scaleX, scaleY: scaleY)
        }
        let verticalSegments = verticalBands.enumerated().compactMap { index, band in
            makeSegment(id: "V\(index + 1)", band: band, scaleX: scaleX, scaleY: scaleY)
        }

        return (horizontalSegments + verticalSegments).sorted { lhs, rhs in
            lhs.length > rhs.length
        }
    }

    private static func refineWallNetwork(
        _ segments: [FloorplanWallSegment],
        mask: FloorplanSegmentationMask,
        sourceSize: CGSize
    ) -> RefinedWallNetwork {
        var horizontal = mergeCollinearSegments(segments.filter { $0.axis == .horizontal })
        var vertical = mergeCollinearSegments(segments.filter { $0.axis == .vertical })
        snapIntersections(horizontal: &horizontal, vertical: &vertical)

        let horizontalSegments = makeSegments(from: horizontal, prefix: "H")
        let verticalSegments = makeSegments(from: vertical, prefix: "V")
        let supportedSegments = filterSupportedSegments(
            horizontalSegments + verticalSegments,
            in: mask,
            sourceSize: sourceSize
        )
        let bridgedSegments = bridgeInferredGaps(in: supportedSegments, mask: mask, sourceSize: sourceSize)
        let connectedSegments = pruneIsolatedSegments(bridgedSegments)
        let junctions = inferJunctions(from: connectedSegments)

        return RefinedWallNetwork(
            segments: connectedSegments.sorted { lhs, rhs in
                lhs.length > rhs.length
            },
            junctions: junctions
        )
    }

    private static func mergeCollinearSegments(_ segments: [FloorplanWallSegment]) -> [MutableWallSegment] {
        let sortedSegments = segments
            .map(MutableWallSegment.init)
            .sorted { lhs, rhs in
                if lhs.secondaryCoordinate == rhs.secondaryCoordinate {
                    return lhs.minimumPrimary < rhs.minimumPrimary
                }
                return lhs.secondaryCoordinate < rhs.secondaryCoordinate
            }

        var merged: [MutableWallSegment] = []
        for segment in sortedSegments {
            guard let last = merged.last, canMerge(last, with: segment) else {
                merged.append(segment)
                continue
            }

            var updated = last
            updated.merge(with: segment)
            merged[merged.count - 1] = updated
        }

        return merged
    }

    private static func canMerge(_ lhs: MutableWallSegment, with rhs: MutableWallSegment) -> Bool {
        guard lhs.axis == rhs.axis else { return false }

        let baseThickness = min(lhs.thickness, rhs.thickness)
        let alignmentTolerance = max(CGFloat(3), baseThickness * 0.55)
        let gapTolerance = max(CGFloat(8), baseThickness * 1.25)
        let alignment = abs(lhs.secondaryCoordinate - rhs.secondaryCoordinate)
        let gap = distanceBetween(primaryRangeOf: lhs, and: rhs)
        let overlap = overlapLength(between: lhs, and: rhs)
        let shorterLength = max(CGFloat(1), min(lhs.primaryLength, rhs.primaryLength))
        let overlapRatio = overlap / shorterLength

        guard alignment <= alignmentTolerance else { return false }
        if gap == 0 {
            return overlapRatio >= 0.22
        }
        return gap <= gapTolerance
    }

    private static func distanceBetween(primaryRangeOf lhs: MutableWallSegment, and rhs: MutableWallSegment) -> CGFloat {
        if lhs.maximumPrimary < rhs.minimumPrimary {
            return rhs.minimumPrimary - lhs.maximumPrimary
        }
        if rhs.maximumPrimary < lhs.minimumPrimary {
            return lhs.minimumPrimary - rhs.maximumPrimary
        }
        return 0
    }

    private static func overlapLength(between lhs: MutableWallSegment, and rhs: MutableWallSegment) -> CGFloat {
        max(0, min(lhs.maximumPrimary, rhs.maximumPrimary) - max(lhs.minimumPrimary, rhs.minimumPrimary))
    }

    private static func makeSegments(from mutableSegments: [MutableWallSegment], prefix: String) -> [FloorplanWallSegment] {
        let sorted = mutableSegments.sorted { lhs, rhs in
            if lhs.secondaryCoordinate == rhs.secondaryCoordinate {
                return lhs.minimumPrimary < rhs.minimumPrimary
            }
            return lhs.secondaryCoordinate < rhs.secondaryCoordinate
        }

        return sorted.enumerated().compactMap { index, segment in
            segment.makeFinalSegment(id: "\(prefix)\(index + 1)")
        }
    }

    private static func snapIntersections(
        horizontal: inout [MutableWallSegment],
        vertical: inout [MutableWallSegment]
    ) {
        let snapTolerance: CGFloat = 14

        for horizontalIndex in horizontal.indices {
            for verticalIndex in vertical.indices {
                let horizontalSegment = horizontal[horizontalIndex]
                let verticalSegment = vertical[verticalIndex]
                let junctionPoint = CGPoint(x: verticalSegment.secondaryCoordinate, y: horizontalSegment.secondaryCoordinate)

                let withinHorizontalReach = junctionPoint.x >= horizontalSegment.minimumPrimary - snapTolerance
                    && junctionPoint.x <= horizontalSegment.maximumPrimary + snapTolerance
                let withinVerticalReach = junctionPoint.y >= verticalSegment.minimumPrimary - snapTolerance
                    && junctionPoint.y <= verticalSegment.maximumPrimary + snapTolerance

                guard withinHorizontalReach, withinVerticalReach else {
                    continue
                }

                var updatedHorizontal = horizontalSegment
                updatedHorizontal.extendToward(primaryValue: junctionPoint.x, tolerance: snapTolerance)
                horizontal[horizontalIndex] = updatedHorizontal

                var updatedVertical = verticalSegment
                updatedVertical.extendToward(primaryValue: junctionPoint.y, tolerance: snapTolerance)
                vertical[verticalIndex] = updatedVertical
            }
        }
    }

    private static func inferJunctions(from segments: [FloorplanWallSegment]) -> [FloorplanWallJunction] {
        let horizontals = segments.filter { $0.axis == .horizontal }
        let verticals = segments.filter { $0.axis == .vertical }
        let tolerance: CGFloat = 8
        var junctions: [FloorplanWallJunction] = []

        for horizontal in horizontals {
            let minX = min(horizontal.start.x, horizontal.end.x)
            let maxX = max(horizontal.start.x, horizontal.end.x)
            let y = horizontal.start.y

            for vertical in verticals {
                let minY = min(vertical.start.y, vertical.end.y)
                let maxY = max(vertical.start.y, vertical.end.y)
                let x = vertical.start.x

                guard x >= minX - tolerance, x <= maxX + tolerance,
                      y >= minY - tolerance, y <= maxY + tolerance else {
                    continue
                }

                junctions.append(
                    FloorplanWallJunction(
                        id: "J\(junctions.count + 1)",
                        point: CGPoint(x: x, y: y),
                        horizontalWallID: horizontal.id,
                        verticalWallID: vertical.id
                    )
                )
            }
        }

        return junctions
    }

    private static func filterSupportedSegments(
        _ segments: [FloorplanWallSegment],
        in mask: FloorplanSegmentationMask,
        sourceSize: CGSize
    ) -> [FloorplanWallSegment] {
        segments.filter { segment in
            let support = supportScore(for: segment, in: mask, sourceSize: sourceSize)
            if segment.length >= 180 {
                return support >= 0.48
            }
            if segment.length >= 90 {
                return support >= 0.58
            }
            return support >= 0.66
        }
    }

    private static func bridgeInferredGaps(
        in segments: [FloorplanWallSegment],
        mask: FloorplanSegmentationMask,
        sourceSize: CGSize
    ) -> [FloorplanWallSegment] {
        let horizontal = bridgeInferredGaps(
            in: segments.filter { $0.axis == .horizontal },
            axis: .horizontal,
            mask: mask,
            sourceSize: sourceSize
        )
        let vertical = bridgeInferredGaps(
            in: segments.filter { $0.axis == .vertical },
            axis: .vertical,
            mask: mask,
            sourceSize: sourceSize
        )

        return (horizontal + vertical).sorted { lhs, rhs in
            lhs.length > rhs.length
        }
    }

    private static func bridgeInferredGaps(
        in segments: [FloorplanWallSegment],
        axis: WallAxis,
        mask: FloorplanSegmentationMask,
        sourceSize: CGSize
    ) -> [FloorplanWallSegment] {
        let sorted = segments
            .map(MutableWallSegment.init)
            .sorted { lhs, rhs in
                if lhs.secondaryCoordinate == rhs.secondaryCoordinate {
                    return lhs.minimumPrimary < rhs.minimumPrimary
                }
                return lhs.secondaryCoordinate < rhs.secondaryCoordinate
            }

        var bridged: [MutableWallSegment] = []
        let maxGap: CGFloat = 22

        for candidate in sorted {
            guard let last = bridged.last else {
                bridged.append(candidate)
                continue
            }

            let alignmentTolerance = max(CGFloat(4), min(last.thickness, candidate.thickness) * 0.7)
            let alignment = abs(last.secondaryCoordinate - candidate.secondaryCoordinate)
            let gap = distanceBetween(primaryRangeOf: last, and: candidate)

            guard alignment <= alignmentTolerance,
                  gap > 0,
                  gap <= maxGap,
                  hasInferredWallBridge(between: last, and: candidate, axis: axis, mask: mask, sourceSize: sourceSize) else {
                bridged.append(candidate)
                continue
            }

            var merged = last
            merged.merge(with: candidate)
            bridged[bridged.count - 1] = merged
        }

        return makeSegments(from: bridged, prefix: axis == .horizontal ? "H" : "V")
    }

    private static func hasInferredWallBridge(
        between lhs: MutableWallSegment,
        and rhs: MutableWallSegment,
        axis: WallAxis,
        mask: FloorplanSegmentationMask,
        sourceSize: CGSize
    ) -> Bool {
        let scaleX = CGFloat(mask.width) / max(sourceSize.width, 1)
        let scaleY = CGFloat(mask.height) / max(sourceSize.height, 1)
        let gapStart = lhs.maximumPrimary
        let gapEnd = rhs.minimumPrimary
        guard gapEnd > gapStart else { return false }

        let samples = max(Int((gapEnd - gapStart) / 4), 3)
        var supportedNeighborLines = 0

        switch axis {
        case .horizontal:
            let centerY = ((lhs.secondaryCoordinate + rhs.secondaryCoordinate) / 2) * scaleY
            let maskY = Int(centerY.rounded())
            let offsets = [-1, 1]

            for offset in offsets {
                let neighborY = maskY + offset
                guard neighborY >= 0, neighborY < mask.height else { continue }
                var supportedSamples = 0

                for step in 0 ... samples {
                    let t = CGFloat(step) / CGFloat(samples)
                    let sourceX = gapStart + ((gapEnd - gapStart) * t)
                    let maskX = Int((sourceX * scaleX).rounded())
                    guard maskX >= 0, maskX < mask.width else { continue }
                    if mask.classID(atX: maskX, y: neighborY) == 1 {
                        supportedSamples += 1
                    }
                }

                if supportedSamples * 4 >= (samples + 1) * 3 {
                    supportedNeighborLines += 1
                }
            }

        case .vertical:
            let centerX = ((lhs.secondaryCoordinate + rhs.secondaryCoordinate) / 2) * scaleX
            let maskX = Int(centerX.rounded())
            let offsets = [-1, 1]

            for offset in offsets {
                let neighborX = maskX + offset
                guard neighborX >= 0, neighborX < mask.width else { continue }
                var supportedSamples = 0

                for step in 0 ... samples {
                    let t = CGFloat(step) / CGFloat(samples)
                    let sourceY = gapStart + ((gapEnd - gapStart) * t)
                    let maskY = Int((sourceY * scaleY).rounded())
                    guard maskY >= 0, maskY < mask.height else { continue }
                    if mask.classID(atX: neighborX, y: maskY) == 1 {
                        supportedSamples += 1
                    }
                }

                if supportedSamples * 4 >= (samples + 1) * 3 {
                    supportedNeighborLines += 1
                }
            }
        }

        return supportedNeighborLines >= 1
    }

    private static func supportScore(
        for segment: FloorplanWallSegment,
        in mask: FloorplanSegmentationMask,
        sourceSize: CGSize
    ) -> CGFloat {
        let scaleX = CGFloat(mask.width) / max(sourceSize.width, 1)
        let scaleY = CGFloat(mask.height) / max(sourceSize.height, 1)
        let samples = max(Int(segment.length / 12), 8)
        let transverseRadius: Int
        let axialRadius = 1

        switch segment.axis {
        case .horizontal:
            transverseRadius = max(1, min(4, Int((segment.thickness * scaleY / 2).rounded())))
        case .vertical:
            transverseRadius = max(1, min(4, Int((segment.thickness * scaleX / 2).rounded())))
        }

        var supportedSteps = 0

        for step in 0 ... samples {
            let t = CGFloat(step) / CGFloat(samples)
            let point = CGPoint(
                x: segment.start.x + ((segment.end.x - segment.start.x) * t),
                y: segment.start.y + ((segment.end.y - segment.start.y) * t)
            )
            let baseX = Int((point.x * scaleX).rounded())
            let baseY = Int((point.y * scaleY).rounded())
            var isSupported = false

            switch segment.axis {
            case .horizontal:
                outerHorizontal: for dx in -axialRadius ... axialRadius {
                    for dy in -transverseRadius ... transverseRadius {
                        if hasStructuralPixel(atX: baseX + dx, y: baseY + dy, in: mask) {
                            isSupported = true
                            break outerHorizontal
                        }
                    }
                }
            case .vertical:
                outerVertical: for dy in -axialRadius ... axialRadius {
                    for dx in -transverseRadius ... transverseRadius {
                        if hasStructuralPixel(atX: baseX + dx, y: baseY + dy, in: mask) {
                            isSupported = true
                            break outerVertical
                        }
                    }
                }
            }

            if isSupported {
                supportedSteps += 1
            }
        }

        return CGFloat(supportedSteps) / CGFloat(samples + 1)
    }

    private static func hasStructuralPixel(atX x: Int, y: Int, in mask: FloorplanSegmentationMask) -> Bool {
        guard x >= 0, x < mask.width, y >= 0, y < mask.height else { return false }
        let classID = mask.classID(atX: x, y: y)
        return classID == 1 || classID == 2 || classID == 3
    }

    private static func pruneIsolatedSegments(_ segments: [FloorplanWallSegment]) -> [FloorplanWallSegment] {
        let junctions = inferJunctions(from: segments)
        let connectedIDs = Set(junctions.flatMap { [$0.horizontalWallID, $0.verticalWallID] })

        return segments.filter { segment in
            connectedIDs.contains(segment.id) || segment.length >= 72
        }
    }

    private static func anchoredOpenings(
        from regions: [FloorplanDetectedRegion],
        onto wallSegments: [FloorplanWallSegment]
    ) -> [FloorplanOpeningCandidate] {
        regions.compactMap { region in
            guard region.kind != .room else { return nil }

            let axis: WallAxis = region.boundingBox.width >= region.boundingBox.height ? .horizontal : .vertical
            let span = max(region.boundingBox.width, region.boundingBox.height)
            let center = CGPoint(x: region.boundingBox.midX, y: region.boundingBox.midY)
            let attachment = nearestWall(for: center, axis: axis, span: span, walls: wallSegments)

            return FloorplanOpeningCandidate(
                id: region.id,
                kind: region.kind,
                axis: axis,
                center: center,
                span: span,
                boundingBox: region.boundingBox,
                attachedWallID: attachment?.wall.id,
                snappedCenter: attachment?.center,
                snappedStart: attachment?.start,
                snappedEnd: attachment?.end,
                offsetFromWall: attachment?.distance
            )
        }
        .sorted { lhs, rhs in
            lhs.span > rhs.span
        }
    }

    private static func nearestWall(
        for center: CGPoint,
        axis: WallAxis,
        span: CGFloat,
        walls: [FloorplanWallSegment]
    ) -> WallAttachment? {
        let compatibleWalls = walls.filter { $0.axis == axis }
        guard !compatibleWalls.isEmpty else { return nil }

        let ranked = compatibleWalls.compactMap { wall -> WallAttachment? in
            switch axis {
            case .horizontal:
                let minX = min(wall.start.x, wall.end.x)
                let maxX = max(wall.start.x, wall.end.x)
                let snappedX = center.x.clamped(to: minX ... maxX)
                let distance = abs(center.y - wall.start.y)
                let halfSpan = min(span / 2, (maxX - minX) / 2)
                let start = CGPoint(x: max(minX, snappedX - halfSpan), y: wall.start.y)
                let end = CGPoint(x: min(maxX, snappedX + halfSpan), y: wall.start.y)
                guard end.x - start.x >= 6 else { return nil }
                return WallAttachment(
                    wall: wall,
                    center: CGPoint(x: (start.x + end.x) / 2, y: wall.start.y),
                    start: start,
                    end: end,
                    distance: distance
                )

            case .vertical:
                let minY = min(wall.start.y, wall.end.y)
                let maxY = max(wall.start.y, wall.end.y)
                let snappedY = center.y.clamped(to: minY ... maxY)
                let distance = abs(center.x - wall.start.x)
                let halfSpan = min(span / 2, (maxY - minY) / 2)
                let start = CGPoint(x: wall.start.x, y: max(minY, snappedY - halfSpan))
                let end = CGPoint(x: wall.start.x, y: min(maxY, snappedY + halfSpan))
                guard end.y - start.y >= 6 else { return nil }
                return WallAttachment(
                    wall: wall,
                    center: CGPoint(x: wall.start.x, y: (start.y + end.y) / 2),
                    start: start,
                    end: end,
                    distance: distance
                )
            }
        }

        return ranked.min { lhs, rhs in
            if lhs.distance == rhs.distance {
                return lhs.wall.length > rhs.wall.length
            }
            return lhs.distance < rhs.distance
        }
    }

    private static func collectContourRuns(in mask: FloorplanSegmentationMask, axis: WallAxis, minimumLength: Int) -> [LinearRun] {
        var runs: [LinearRun] = []

        switch axis {
        case .horizontal:
            for y in 0 ..< mask.height {
                var x = 0
                while x < mask.width {
                    while x < mask.width, !isWallContourPixel(atX: x, y: y, in: mask, axis: .horizontal) {
                        x += 1
                    }
                    let start = x
                    while x < mask.width, isWallContourPixel(atX: x, y: y, in: mask, axis: .horizontal) {
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
                    while y < mask.height, !isWallContourPixel(atX: x, y: y, in: mask, axis: .vertical) {
                        y += 1
                    }
                    let start = y
                    while y < mask.height, isWallContourPixel(atX: x, y: y, in: mask, axis: .vertical) {
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

    private static func isWallContourPixel(atX x: Int, y: Int, in mask: FloorplanSegmentationMask, axis: WallAxis) -> Bool {
        guard x >= 0, x < mask.width, y >= 0, y < mask.height else { return false }
        guard mask.classID(atX: x, y: y) == 1 else { return false }

        switch axis {
        case .horizontal:
            return !isWall(atX: x, y: y - 1, in: mask) || !isWall(atX: x, y: y + 1, in: mask)
        case .vertical:
            return !isWall(atX: x - 1, y: y, in: mask) || !isWall(atX: x + 1, y: y, in: mask)
        }
    }

    private static func isWall(atX x: Int, y: Int, in mask: FloorplanSegmentationMask) -> Bool {
        guard x >= 0, x < mask.width, y >= 0, y < mask.height else { return false }
        return mask.classID(atX: x, y: y) == 1
    }

    private static func merge(runs: [LinearRun], axis: WallAxis) -> [WallBand] {
        let sortedRuns = runs.sorted { lhs, rhs in
            if lhs.cross == rhs.cross {
                return lhs.start < rhs.start
            }
            return lhs.cross < rhs.cross
        }

        var bands: [WallBand] = []
        for run in sortedRuns {
            if let index = bands.firstIndex(where: { $0.accepts(run) }) {
                bands[index].append(run)
            } else {
                bands.append(WallBand(axis: axis, firstRun: run))
            }
        }

        return bands.filter { $0.length >= 40 && $0.thickness >= 1 }
    }

    private static func makeSegment(id: String, band: WallBand, scaleX: CGFloat, scaleY: CGFloat) -> FloorplanWallSegment? {
        let startPrimary = CGFloat(band.medianStart) + 0.5
        let endPrimary = CGFloat(band.medianEnd) + 0.5
        let centerSecondary = CGFloat(band.minCross + band.maxCross + 1) / 2.0

        switch band.axis {
        case .horizontal:
            let start = CGPoint(x: startPrimary * scaleX, y: centerSecondary * scaleY)
            let end = CGPoint(x: endPrimary * scaleX, y: centerSecondary * scaleY)
            let thickness = CGFloat(band.thickness) * scaleY
            guard hypot(end.x - start.x, end.y - start.y) >= 24 else { return nil }
            return FloorplanWallSegment(id: id, axis: .horizontal, start: start, end: end, thickness: thickness)

        case .vertical:
            let start = CGPoint(x: centerSecondary * scaleX, y: startPrimary * scaleY)
            let end = CGPoint(x: centerSecondary * scaleX, y: endPrimary * scaleY)
            let thickness = CGFloat(band.thickness) * scaleX
            guard hypot(end.x - start.x, end.y - start.y) >= 24 else { return nil }
            return FloorplanWallSegment(id: id, axis: .vertical, start: start, end: end, thickness: thickness)
        }
    }

    private static func neighbors(of point: (x: Int, y: Int), width: Int, height: Int) -> [(x: Int, y: Int)] {
        var items: [(x: Int, y: Int)] = []
        items.reserveCapacity(4)

        if point.x > 0 {
            items.append((point.x - 1, point.y))
        }
        if point.x + 1 < width {
            items.append((point.x + 1, point.y))
        }
        if point.y > 0 {
            items.append((point.x, point.y - 1))
        }
        if point.y + 1 < height {
            items.append((point.x, point.y + 1))
        }

        return items
    }
}

private struct RefinedWallNetwork {
    let segments: [FloorplanWallSegment]
    let junctions: [FloorplanWallJunction]
}

private struct LinearRun {
    let start: Int
    let end: Int
    let cross: Int

    var length: Int {
        end - start + 1
    }
}

private struct WallBand {
    let axis: WallAxis
    var starts: [Int]
    var ends: [Int]
    var minCross: Int
    var maxCross: Int

    init(axis: WallAxis, firstRun: LinearRun) {
        self.axis = axis
        self.starts = [firstRun.start]
        self.ends = [firstRun.end]
        self.minCross = firstRun.cross
        self.maxCross = firstRun.cross
    }

    var medianStart: Int {
        starts.sorted()[starts.count / 2]
    }

    var medianEnd: Int {
        ends.sorted()[ends.count / 2]
    }

    var thickness: Int {
        maxCross - minCross + 1
    }

    var length: Int {
        medianEnd - medianStart + 1
    }

    mutating func append(_ run: LinearRun) {
        starts.append(run.start)
        ends.append(run.end)
        minCross = min(minCross, run.cross)
        maxCross = max(maxCross, run.cross)
    }

    func accepts(_ run: LinearRun) -> Bool {
        guard run.cross <= maxCross + 1 else { return false }

        let overlapStart = max(medianStart, run.start)
        let overlapEnd = min(medianEnd, run.end)
        let overlap = max(0, overlapEnd - overlapStart + 1)
        let shorterLength = max(1, min(length, run.length))
        let overlapRatio = Double(overlap) / Double(shorterLength)

        return overlapRatio >= 0.55
    }
}

private struct MutableWallSegment {
    let axis: WallAxis
    var start: CGPoint
    var end: CGPoint
    var thickness: CGFloat

    init(_ segment: FloorplanWallSegment) {
        axis = segment.axis
        thickness = segment.thickness

        switch segment.axis {
        case .horizontal:
            let minX = min(segment.start.x, segment.end.x)
            let maxX = max(segment.start.x, segment.end.x)
            let y = (segment.start.y + segment.end.y) / 2
            start = CGPoint(x: minX, y: y)
            end = CGPoint(x: maxX, y: y)
        case .vertical:
            let minY = min(segment.start.y, segment.end.y)
            let maxY = max(segment.start.y, segment.end.y)
            let x = (segment.start.x + segment.end.x) / 2
            start = CGPoint(x: x, y: minY)
            end = CGPoint(x: x, y: maxY)
        }
    }

    var secondaryCoordinate: CGFloat {
        switch axis {
        case .horizontal:
            start.y
        case .vertical:
            start.x
        }
    }

    var minimumPrimary: CGFloat {
        switch axis {
        case .horizontal:
            min(start.x, end.x)
        case .vertical:
            min(start.y, end.y)
        }
    }

    var maximumPrimary: CGFloat {
        switch axis {
        case .horizontal:
            max(start.x, end.x)
        case .vertical:
            max(start.y, end.y)
        }
    }

    var primaryLength: CGFloat {
        maximumPrimary - minimumPrimary
    }

    mutating func merge(with other: MutableWallSegment) {
        thickness = max(thickness, other.thickness)

        switch axis {
        case .horizontal:
            let minX = min(minimumPrimary, other.minimumPrimary)
            let maxX = max(maximumPrimary, other.maximumPrimary)
            let dominantY = primaryLength >= other.primaryLength ? secondaryCoordinate : other.secondaryCoordinate
            start = CGPoint(x: minX, y: dominantY)
            end = CGPoint(x: maxX, y: dominantY)
        case .vertical:
            let minY = min(minimumPrimary, other.minimumPrimary)
            let maxY = max(maximumPrimary, other.maximumPrimary)
            let dominantX = primaryLength >= other.primaryLength ? secondaryCoordinate : other.secondaryCoordinate
            start = CGPoint(x: dominantX, y: minY)
            end = CGPoint(x: dominantX, y: maxY)
        }
    }

    mutating func extendToward(primaryValue: CGFloat, tolerance: CGFloat) {
        switch axis {
        case .horizontal:
            let minX = min(start.x, end.x)
            let maxX = max(start.x, end.x)
            if primaryValue < minX, minX - primaryValue <= tolerance {
                start = CGPoint(x: primaryValue, y: start.y)
                end = CGPoint(x: maxX, y: end.y)
            } else if primaryValue > maxX, primaryValue - maxX <= tolerance {
                start = CGPoint(x: minX, y: start.y)
                end = CGPoint(x: primaryValue, y: end.y)
            }
        case .vertical:
            let minY = min(start.y, end.y)
            let maxY = max(start.y, end.y)
            if primaryValue < minY, minY - primaryValue <= tolerance {
                start = CGPoint(x: start.x, y: primaryValue)
                end = CGPoint(x: end.x, y: maxY)
            } else if primaryValue > maxY, primaryValue - maxY <= tolerance {
                start = CGPoint(x: start.x, y: minY)
                end = CGPoint(x: end.x, y: primaryValue)
            }
        }
    }

    func makeFinalSegment(id: String) -> FloorplanWallSegment? {
        guard primaryLength >= 24 else { return nil }
        return FloorplanWallSegment(id: id, axis: axis, start: start, end: end, thickness: thickness)
    }
}

private struct WallAttachment {
    let wall: FloorplanWallSegment
    let center: CGPoint
    let start: CGPoint
    let end: CGPoint
    let distance: CGFloat
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
