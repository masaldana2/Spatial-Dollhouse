import CoreML

struct FloorplanSegmentationMask {
    let width: Int
    let height: Int
    let classIDs: [UInt8]
    private static let wallClassID: UInt8 = 1

    func classID(atX x: Int, y: Int) -> UInt8 {
        classIDs[(y * width) + x]
    }

    func classHistogram() -> [UInt8: Int] {
        classIDs.reduce(into: [:]) { counts, classID in
            counts[classID, default: 0] += 1
        }
    }

    func coverage(for classID: UInt8) -> Double {
        let total = max(classIDs.count, 1)
        let matches = classIDs.reduce(into: 0) { count, candidate in
            if candidate == classID {
                count += 1
            }
        }
        return Double(matches) / Double(total)
    }

    func unletterboxed(using layout: FloorplanCoreMLInput.Layout) -> FloorplanSegmentationMask {
        guard width == layout.imageSize, height == layout.imageSize else {
            return self
        }

        let croppedWidth = max(1, min(layout.scaledWidth, width - layout.padLeft))
        let croppedHeight = max(1, min(layout.scaledHeight, height - layout.padTop))
        var cropped = [UInt8](repeating: 0, count: croppedWidth * croppedHeight)

        for y in 0 ..< croppedHeight {
            let sourceY = min(height - 1, layout.padTop + y)
            for x in 0 ..< croppedWidth {
                let sourceX = min(width - 1, layout.padLeft + x)
                cropped[(y * croppedWidth) + x] = classID(atX: sourceX, y: sourceY)
            }
        }

        guard croppedWidth != layout.originalWidth || croppedHeight != layout.originalHeight else {
            return FloorplanSegmentationMask(
                width: croppedWidth,
                height: croppedHeight,
                classIDs: cropped
            )
        }

        var resized = [UInt8](repeating: 0, count: layout.originalWidth * layout.originalHeight)
        let scaleX = CGFloat(croppedWidth) / CGFloat(layout.originalWidth)
        let scaleY = CGFloat(croppedHeight) / CGFloat(layout.originalHeight)

        for y in 0 ..< layout.originalHeight {
            let sourceY = min(croppedHeight - 1, Int(CGFloat(y) * scaleY))
            for x in 0 ..< layout.originalWidth {
                let sourceX = min(croppedWidth - 1, Int(CGFloat(x) * scaleX))
                resized[(y * layout.originalWidth) + x] = cropped[(sourceY * croppedWidth) + sourceX]
            }
        }

        return FloorplanSegmentationMask(
            width: layout.originalWidth,
            height: layout.originalHeight,
            classIDs: resized
        )
    }

    func fillingInferredWallGaps(maxGap: Int = 24, minimumNeighborSupport: Int = 1) -> FloorplanSegmentationMask {
        guard width > 2, height > 2, maxGap > 0 else { return self }

        var filled = classIDs
        bridgeWallComponents(in: &filled, maximumGap: maxGap, minimumOverlap: 3)
        fillAlignedWallBandGaps(in: &filled, axis: .horizontal, maxGap: maxGap * 2, minimumRunLength: 10)
        fillAlignedWallBandGaps(in: &filled, axis: .vertical, maxGap: maxGap * 2, minimumRunLength: 10)
        bridgeWallGaps(in: &filled, axis: .horizontal, maxGap: maxGap, minimumNeighborSupport: minimumNeighborSupport)
        bridgeWallGaps(in: &filled, axis: .vertical, maxGap: maxGap, minimumNeighborSupport: minimumNeighborSupport)
        bridgeWallGaps(in: &filled, axis: .horizontal, maxGap: maxGap, minimumNeighborSupport: minimumNeighborSupport)
        bridgeWallGaps(in: &filled, axis: .vertical, maxGap: maxGap, minimumNeighborSupport: minimumNeighborSupport)

        return FloorplanSegmentationMask(width: width, height: height, classIDs: filled)
    }
}

private extension FloorplanSegmentationMask {
    enum ScanAxis {
        case horizontal
        case vertical
    }

    func bridgeWallGaps(
        in pixels: inout [UInt8],
        axis: ScanAxis,
        maxGap: Int,
        minimumNeighborSupport: Int
    ) {
        let primaryLength = axis == .horizontal ? width : height
        let secondaryLength = axis == .horizontal ? height : width
        guard primaryLength >= 3, secondaryLength >= 3 else { return }

        for secondary in 0 ..< secondaryLength {
            var primary = 1
            while primary < primaryLength - 1 {
                guard pixel(in: pixels, axis: axis, primary: primary, secondary: secondary) != Self.wallClassID,
                      pixel(in: pixels, axis: axis, primary: primary - 1, secondary: secondary) == Self.wallClassID else {
                    primary += 1
                    continue
                }

                var gapEnd = primary
                while gapEnd < primaryLength, pixel(in: pixels, axis: axis, primary: gapEnd, secondary: secondary) != Self.wallClassID {
                    gapEnd += 1
                    if gapEnd - primary > maxGap {
                        break
                    }
                }

                let gapLength = gapEnd - primary
                guard gapEnd < primaryLength,
                      gapLength > 0,
                      gapLength <= maxGap,
                      neighborSupport(in: pixels, axis: axis, secondary: secondary, gapStart: primary, gapEnd: gapEnd) >= minimumNeighborSupport else {
                    primary = max(primary + 1, gapEnd)
                    continue
                }

                for fillPrimary in primary ..< gapEnd {
                    setPixel(in: &pixels, axis: axis, primary: fillPrimary, secondary: secondary, value: Self.wallClassID)
                }

                primary = gapEnd
            }
        }
    }

    func bridgeWallComponents(in pixels: inout [UInt8], maximumGap: Int, minimumOverlap: Int) {
        let components = wallComponents(in: pixels)
        guard components.count >= 2 else { return }

        for lhsIndex in components.indices {
            for rhsIndex in components.indices where rhsIndex > lhsIndex {
                let lhs = components[lhsIndex]
                let rhs = components[rhsIndex]

                if let bridge = verticalBridgeRect(between: lhs, and: rhs, maximumGap: maximumGap, minimumOverlap: minimumOverlap) {
                    if isLikelyWallBridge(rect: bridge, axis: .vertical, in: pixels) {
                        fill(rect: bridge, in: &pixels)
                    }
                    continue
                }

                if let bridge = horizontalBridgeRect(between: lhs, and: rhs, maximumGap: maximumGap, minimumOverlap: minimumOverlap) {
                    if isLikelyWallBridge(rect: bridge, axis: .horizontal, in: pixels) {
                        fill(rect: bridge, in: &pixels)
                    }
                }
            }
        }
    }

    func fillAlignedWallBandGaps(
        in pixels: inout [UInt8],
        axis: ScanAxis,
        maxGap: Int,
        minimumRunLength: Int
    ) {
        let primaryLength = axis == .horizontal ? width : height
        let secondaryLength = axis == .horizontal ? height : width
        guard primaryLength >= minimumRunLength * 2 + 1 else { return }

        for secondary in 0 ..< secondaryLength {
            var primary = 0
            while primary < primaryLength {
                while primary < primaryLength,
                      pixel(in: pixels, axis: axis, primary: primary, secondary: secondary) != Self.wallClassID {
                    primary += 1
                }
                let firstRunStart = primary
                while primary < primaryLength,
                      pixel(in: pixels, axis: axis, primary: primary, secondary: secondary) == Self.wallClassID {
                    primary += 1
                }
                let firstRunEnd = primary
                let firstRunLength = firstRunEnd - firstRunStart

                guard firstRunLength >= minimumRunLength else { continue }

                let gapStart = primary
                while primary < primaryLength,
                      pixel(in: pixels, axis: axis, primary: primary, secondary: secondary) != Self.wallClassID {
                    let value = pixel(in: pixels, axis: axis, primary: primary, secondary: secondary)
                    if value == 2 || value == 3 {
                        break
                    }
                    primary += 1
                    if primary - gapStart > maxGap {
                        break
                    }
                }

                let gapEnd = primary
                let gapLength = gapEnd - gapStart
                guard gapLength > 0, gapLength <= maxGap, primary < primaryLength else { continue }

                let secondRunStart = primary
                while primary < primaryLength,
                      pixel(in: pixels, axis: axis, primary: primary, secondary: secondary) == Self.wallClassID {
                    primary += 1
                }
                let secondRunLength = primary - secondRunStart
                guard secondRunLength >= minimumRunLength,
                      hasBandSupport(in: pixels, axis: axis, secondary: secondary, gapStart: gapStart, gapEnd: gapEnd) else {
                    continue
                }

                for fillPrimary in gapStart ..< gapEnd {
                    setPixel(in: &pixels, axis: axis, primary: fillPrimary, secondary: secondary, value: Self.wallClassID)
                }
            }
        }
    }

    func neighborSupport(
        in pixels: [UInt8],
        axis: ScanAxis,
        secondary: Int,
        gapStart: Int,
        gapEnd: Int
    ) -> Int {
        let secondaryLength = axis == .horizontal ? height : width
        let neighbors = [secondary - 2, secondary - 1, secondary + 1, secondary + 2]

        return neighbors.reduce(into: 0) { count, neighbor in
            guard neighbor >= 0, neighbor < secondaryLength else { return }

            let supportedPixels = (gapStart - 1 ... gapEnd).reduce(into: 0) { lineCount, primary in
                if pixel(in: pixels, axis: axis, primary: primary, secondary: neighbor) == Self.wallClassID {
                    lineCount += 1
                }
            }

            let spanLength = gapEnd - gapStart + 2
            if supportedPixels * 4 >= spanLength * 3 {
                count += 1
            }
        }
    }

    func hasBandSupport(
        in pixels: [UInt8],
        axis: ScanAxis,
        secondary: Int,
        gapStart: Int,
        gapEnd: Int
    ) -> Bool {
        let secondaryLength = axis == .horizontal ? height : width
        let neighbors = [secondary - 2, secondary - 1, secondary + 1, secondary + 2]
        var supportingLines = 0

        for neighbor in neighbors {
            guard neighbor >= 0, neighbor < secondaryLength else { continue }
            var wallPixels = 0
            for primary in gapStart ..< gapEnd {
                if pixel(in: pixels, axis: axis, primary: primary, secondary: neighbor) == Self.wallClassID {
                    wallPixels += 1
                }
            }

            if wallPixels * 3 >= (gapEnd - gapStart) * 2 {
                supportingLines += 1
            }
        }

        return supportingLines >= 1
    }

    func wallComponents(in pixels: [UInt8]) -> [WallComponent] {
        var visited = [Bool](repeating: false, count: pixels.count)
        var components: [WallComponent] = []

        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = (y * width) + x
                guard !visited[index], pixels[index] == Self.wallClassID else { continue }

                var queue: [(x: Int, y: Int)] = [(x, y)]
                visited[index] = true
                var queueIndex = 0
                var minX = x
                var maxX = x
                var minY = y
                var maxY = y
                var pixelCount = 0

                while queueIndex < queue.count {
                    let current = queue[queueIndex]
                    queueIndex += 1
                    pixelCount += 1
                    minX = min(minX, current.x)
                    maxX = max(maxX, current.x)
                    minY = min(minY, current.y)
                    maxY = max(maxY, current.y)

                    for neighbor in fourNeighbors(ofX: current.x, y: current.y) {
                        let neighborIndex = (neighbor.y * width) + neighbor.x
                        guard !visited[neighborIndex], pixels[neighborIndex] == Self.wallClassID else { continue }
                        visited[neighborIndex] = true
                        queue.append(neighbor)
                    }
                }

                if pixelCount >= 6 {
                    components.append(
                        WallComponent(
                            bounds: CGRect(
                                x: minX,
                                y: minY,
                                width: maxX - minX + 1,
                                height: maxY - minY + 1
                            ),
                            pixelCount: pixelCount
                        )
                    )
                }
            }
        }

        return components
    }

    func verticalBridgeRect(
        between lhs: WallComponent,
        and rhs: WallComponent,
        maximumGap: Int,
        minimumOverlap: Int
    ) -> CGRect? {
        guard lhs.isMostlyVertical, rhs.isMostlyVertical else { return nil }
        let overlapStart = max(Int(lhs.bounds.minX), Int(rhs.bounds.minX))
        let overlapEnd = min(Int(lhs.bounds.maxX), Int(rhs.bounds.maxX))
        let overlapWidth = overlapEnd - overlapStart + 1
        let maxWallThickness = max(Int(lhs.bounds.width), Int(rhs.bounds.width))
        let centerDelta = abs(lhs.bounds.midX - rhs.bounds.midX)
        guard overlapWidth >= minimumOverlap,
              overlapWidth <= 20,
              maxWallThickness <= 20,
              centerDelta <= 12 else { return nil }

        let upper: WallComponent
        let lower: WallComponent
        if lhs.bounds.minY <= rhs.bounds.minY {
            upper = lhs
            lower = rhs
        } else {
            upper = rhs
            lower = lhs
        }

        let gap = Int(lower.bounds.minY) - Int(upper.bounds.maxY) - 1
        guard gap > 0, gap <= maximumGap else { return nil }

        let bridgeX = overlapStart
        let bridgeWidth = overlapWidth
        let bridgeY = Int(upper.bounds.maxY) + 1
        return CGRect(x: bridgeX, y: bridgeY, width: bridgeWidth, height: gap)
    }

    func horizontalBridgeRect(
        between lhs: WallComponent,
        and rhs: WallComponent,
        maximumGap: Int,
        minimumOverlap: Int
    ) -> CGRect? {
        guard lhs.isMostlyHorizontal, rhs.isMostlyHorizontal else { return nil }
        let overlapStart = max(Int(lhs.bounds.minY), Int(rhs.bounds.minY))
        let overlapEnd = min(Int(lhs.bounds.maxY), Int(rhs.bounds.maxY))
        let overlapHeight = overlapEnd - overlapStart + 1
        let maxWallThickness = max(Int(lhs.bounds.height), Int(rhs.bounds.height))
        let centerDelta = abs(lhs.bounds.midY - rhs.bounds.midY)
        guard overlapHeight >= minimumOverlap,
              overlapHeight <= 20,
              maxWallThickness <= 20,
              centerDelta <= 12 else { return nil }

        let left: WallComponent
        let right: WallComponent
        if lhs.bounds.minX <= rhs.bounds.minX {
            left = lhs
            right = rhs
        } else {
            left = rhs
            right = lhs
        }

        let gap = Int(right.bounds.minX) - Int(left.bounds.maxX) - 1
        guard gap > 0, gap <= maximumGap else { return nil }

        let bridgeX = Int(left.bounds.maxX) + 1
        let bridgeY = overlapStart
        return CGRect(x: bridgeX, y: bridgeY, width: gap, height: overlapHeight)
    }

    func fill(rect: CGRect, in pixels: inout [UInt8]) {
        let minX = max(0, Int(rect.minX))
        let maxX = min(width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(height - 1, Int(rect.maxY))
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY ... maxY {
            for x in minX ... maxX {
                let index = (y * width) + x
                let value = pixels[index]
                if value != 2, value != 3 {
                    pixels[index] = Self.wallClassID
                }
            }
        }
    }

    func isLikelyWallBridge(rect: CGRect, axis: ScanAxis, in pixels: [UInt8]) -> Bool {
        let minX = max(0, Int(rect.minX))
        let maxX = min(width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY))
        let maxY = min(height - 1, Int(rect.maxY))
        guard minX <= maxX, minY <= maxY else { return false }

        var openingPixels = 0
        var totalPixels = 0

        for y in max(0, minY - 1) ... min(height - 1, maxY + 1) {
            for x in max(0, minX - 1) ... min(width - 1, maxX + 1) {
                totalPixels += 1
                let classID = pixels[(y * width) + x]
                if classID == 2 || classID == 3 {
                    openingPixels += 1
                }
            }
        }

        guard openingPixels * 5 <= max(totalPixels, 1) else { return false }

        switch axis {
        case .vertical:
            let leftSupport = sideSupportRatio(in: pixels, fixed: minX - 1, range: minY ... maxY, axis: .vertical)
            let rightSupport = sideSupportRatio(in: pixels, fixed: maxX + 1, range: minY ... maxY, axis: .vertical)
            return leftSupport >= 0.45 && rightSupport >= 0.45

        case .horizontal:
            let topSupport = sideSupportRatio(in: pixels, fixed: minY - 1, range: minX ... maxX, axis: .horizontal)
            let bottomSupport = sideSupportRatio(in: pixels, fixed: maxY + 1, range: minX ... maxX, axis: .horizontal)
            return topSupport >= 0.45 && bottomSupport >= 0.45
        }
    }

    func sideSupportRatio(in pixels: [UInt8], fixed: Int, range: ClosedRange<Int>, axis: ScanAxis) -> CGFloat {
        var supported = 0
        var samples = 0

        switch axis {
        case .vertical:
            guard fixed >= 0, fixed < width else { return 1 }
            for y in range {
                guard y >= 0, y < height else { continue }
                samples += 1
                let classID = pixels[(y * width) + fixed]
                if classID == 0 || classID == 4 {
                    supported += 1
                }
            }

        case .horizontal:
            guard fixed >= 0, fixed < height else { return 1 }
            for x in range {
                guard x >= 0, x < width else { continue }
                samples += 1
                let classID = pixels[(fixed * width) + x]
                if classID == 0 || classID == 4 {
                    supported += 1
                }
            }
        }

        guard samples > 0 else { return 0 }
        return CGFloat(supported) / CGFloat(samples)
    }

    func fourNeighbors(ofX x: Int, y: Int) -> [(x: Int, y: Int)] {
        var neighbors: [(x: Int, y: Int)] = []
        if x > 0 { neighbors.append((x - 1, y)) }
        if x + 1 < width { neighbors.append((x + 1, y)) }
        if y > 0 { neighbors.append((x, y - 1)) }
        if y + 1 < height { neighbors.append((x, y + 1)) }
        return neighbors
    }

    func pixel(in pixels: [UInt8], axis: ScanAxis, primary: Int, secondary: Int) -> UInt8 {
        switch axis {
        case .horizontal:
            pixels[(secondary * width) + primary]
        case .vertical:
            pixels[(primary * width) + secondary]
        }
    }

    func setPixel(in pixels: inout [UInt8], axis: ScanAxis, primary: Int, secondary: Int, value: UInt8) {
        switch axis {
        case .horizontal:
            pixels[(secondary * width) + primary] = value
        case .vertical:
            pixels[(primary * width) + secondary] = value
        }
    }
}

private struct WallComponent {
    let bounds: CGRect
    let pixelCount: Int

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

enum FloorplanSegmentationDecoder {
    static func decode(_ multiArray: MLMultiArray) -> FloorplanSegmentationMask {
        let shape = multiArray.shape.map { Int(truncating: $0) }
        let dimensions = dimensions(for: shape)
        let width = dimensions.width
        let height = dimensions.height
        let channels = dimensions.channels

        var classIDs = [UInt8](repeating: 0, count: width * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let bestClass: Int
                if channels <= 1 {
                    bestClass = max(0, readClassIndex(in: multiArray, y: y, x: x, rank: dimensions.rank))
                } else {
                    var candidateClass = 0
                    var candidateScore = -Double.infinity
                    for channel in 0 ..< channels {
                        let score = readValue(in: multiArray, channel: channel, y: y, x: x, rank: dimensions.rank)
                        if score > candidateScore {
                            candidateScore = score
                            candidateClass = channel
                        }
                    }
                    bestClass = candidateClass
                }

                classIDs[(y * width) + x] = UInt8(clamping: bestClass)
            }
        }

        return FloorplanSegmentationMask(width: width, height: height, classIDs: classIDs)
    }

    private static func dimensions(for shape: [Int]) -> (channels: Int, height: Int, width: Int, rank: Int) {
        switch shape.count {
        case 4:
            return (shape[1], shape[2], shape[3], 4)
        case 3:
            return (shape[0], shape[1], shape[2], 3)
        case 2:
            return (1, shape[0], shape[1], 2)
        default:
            return (1, shape.last ?? 1, shape.last ?? 1, shape.count)
        }
    }

    private static func readValue(in multiArray: MLMultiArray, channel: Int, y: Int, x: Int, rank: Int) -> Double {
        let index: [NSNumber]
        switch rank {
        case 4:
            index = [0, channel as NSNumber, y as NSNumber, x as NSNumber]
        case 3:
            index = [channel as NSNumber, y as NSNumber, x as NSNumber]
        case 2:
            index = [y as NSNumber, x as NSNumber]
        default:
            index = [0]
        }

        return multiArray[index].doubleValue
    }

    private static func readClassIndex(in multiArray: MLMultiArray, y: Int, x: Int, rank: Int) -> Int {
        let index: [NSNumber]
        switch rank {
        case 4:
            index = [0, 0, y as NSNumber, x as NSNumber]
        case 3:
            index = [0, y as NSNumber, x as NSNumber]
        case 2:
            index = [y as NSNumber, x as NSNumber]
        default:
            index = [0]
        }

        let value = multiArray[index]
        switch multiArray.dataType {
        case .int32:
            return value.intValue
        case .float16, .float32, .double:
            return Int(value.doubleValue.rounded())
        @unknown default:
            return Int(value.doubleValue.rounded())
        }
    }
}
