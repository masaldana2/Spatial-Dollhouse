//
//  FloorplanSemanticParser.swift
//  Spatial Dollhouse
//

import CoreGraphics
import Foundation

final class FloorplanSemanticParser {
    /// Legacy prototype parser for direct image-to-3D experiments.
    /// Production generation must come from the CoreML pipeline, not from
    /// parsing the raster image directly inside the immersive builder.
    func parse(image: CGImage, config: DollhouseBuildConfig) throws -> FloorplanSemanticModel {
        guard let grid = FloorplanMaskParser.parse(image: image, cellSize: config.cellSize) else {
            throw FloorplanDollhouseBuilderError.parseFailure
        }

        // 1. WALLS: Preserved exactly as requested (keeps short walls, kills sliver noise)
        let rawWalls = GridMesher.extract(from: grid.wallMask, width: grid.width, height: grid.height, minimumArea: 10)
        let walls = rawWalls.filter { min($0.width, $0.height) >= 2 }

        // 2. DOORS: Uses the original 40-pixel raycast to prevent overshooting into other rooms
        let rawDoors = GridMesher.extract(from: grid.doorMask, width: grid.width, height: grid.height, minimumArea: 4)
            .filter(GridMesher.isLikelyOpening)
        
        // Define minimum door length (in grid cells).
        // Tweak this based on your config.cellSize.
        // e.g., if a cell is 2 inches, a standard 32-inch door would be 16 cells.
        let minDoorLength = 12
        
        let doors = OpeningAligner.align(rawDoors, walls: walls, mask: grid.wallMask, w: grid.width, h: grid.height, maxRaycast: 40)
            .filter { $0.maxDimension >= minDoorLength } // <-- Kills noise doors that are too short

        // 3. WINDOWS: Uses the extended 150-pixel raycast to bridge very long gaps
        let rawWindows = GridMesher.extract(from: grid.windowMask, width: grid.width, height: grid.height, minimumArea: 4)
            .filter(GridMesher.isLikelyOpening)
        let windows = OpeningAligner.align(rawWindows, walls: walls, mask: grid.wallMask, w: grid.width, h: grid.height, maxRaycast: 150)

        return FloorplanSemanticModel(
            gridWidth: grid.width,
            gridHeight: grid.height,
            walls: walls,
            doors: doors,
            windows: windows
        )
    }
}
// MARK: - Core Data Structures

private struct FloorplanGrid {
    let width: Int, height: Int
    var wallMask: [Bool], doorMask: [Bool], windowMask: [Bool]
}

// MARK: - Opening Aligner (Centers Doors & Windows)

private enum OpeningAligner {
    enum Axis { case horizontal, vertical }
    
    struct Candidate {
        let rect: GridRect
        let axis: Axis
        let wallLine: Float?
        let rawCenter: SIMD2<Float>
        let projCenter: SIMD2<Float>
        
        var along: Float { axis == .horizontal ? projCenter.x : projCenter.y }
        var cross: Float { axis == .horizontal ? projCenter.y : projCenter.x }
    }

    static func align(_ rects: [GridRect], walls: [GridRect], mask: [Bool], w: Int, h: Int, maxRaycast: Int) -> [GridRect] {
        guard rects.count > 0 else { return [] }
        if rects.count == 1 { return rects }

        // 1. Convert to candidates with projected wall info
        let candidates = rects.map { rect -> Candidate in
            let center = SIMD2<Float>(Float(rect.x) + Float(rect.width) * 0.5, Float(rect.y) + Float(rect.height) * 0.5)
            
            if let nearest = nearestWall(to: center, walls: walls) {
                let wallLine = nearest.axis == .horizontal ? Float(nearest.wall.y) + Float(nearest.wall.height)*0.5 : Float(nearest.wall.x) + Float(nearest.wall.width)*0.5
                let pCenter = nearest.axis == .horizontal ? SIMD2<Float>(center.x, wallLine) : SIMD2<Float>(wallLine, center.y)
                return Candidate(rect: rect, axis: nearest.axis, wallLine: wallLine, rawCenter: center, projCenter: pCenter)
            }
            let fallbackAxis: Axis = rect.width >= rect.height ? .horizontal : .vertical
            return Candidate(rect: rect, axis: fallbackAxis, wallLine: nil, rawCenter: center, projCenter: center)
        }

        // 2. Cluster candidates together based on proximity and alignment
        var clusters: [[Candidate]] = []
        for c in candidates {
            var matchedIdx: Int?
            for (i, cluster) in clusters.enumerated() {
                guard cluster.first?.axis == c.axis else { continue }
                
                if let cLine = c.wallLine, let clLine = cluster.avgWallLine, abs(cLine - clLine) > 24.0 { continue }
                
                let hasWall = c.wallLine != nil && cluster.avgWallLine != nil
                let alongDelta = abs(c.along - cluster.avgAlong)
                let crossDelta = abs(c.cross - cluster.avgCross)
                
                guard alongDelta <= (hasWall ? 20.0 : 10.0), crossDelta <= (hasWall ? 22.0 : 8.0) else { continue }
                
                let range = cluster.alongRange(axis: c.axis)
                let rMin = c.axis == .horizontal ? c.rect.x : c.rect.y
                let rMax = c.axis == .horizontal ? c.rect.x + c.rect.width : c.rect.y + c.rect.height
                
                let overlap = Float(max(0, min(rMax, range.max) - max(rMin, range.min))) / Float(max(1, min(rMax - rMin, range.max - range.min)))
                
                if overlap >= 0.35 || alongDelta <= 4.0 { matchedIdx = i; break }
            }
            if let idx = matchedIdx { clusters[idx].append(c) } else { clusters.append([c]) }
        }

        // 3. Merge clusters and raycast the gap to center perfectly
        return clusters.compactMap { cluster -> GridRect? in
            guard let first = cluster.first else { return nil }
            let axis = first.axis
            let center = cluster.avgProjCenter
            let range = cluster.alongRange(axis: axis)
            
            let startX = axis == .horizontal ? (range.min + range.max) / 2 : Int(round(center.x))
            let startY = axis == .vertical ? (range.min + range.max) / 2 : Int(round(center.y))
            
            let gap = refineGap(startX: startX, startY: startY, axis: axis, mask: mask, w: w, h: h, fallback: range, maxRaycast: maxRaycast)
            let thickness = max(2, Int(round(cluster.reduce(0) { $0 + Float($1.rect.minDimension) } / Float(cluster.count))))
            
            let merged: GridRect
            if axis == .horizontal {
                merged = GridRect(x: gap.min, y: Int(round(center.y - Float(thickness)*0.5)), width: max(1, gap.max - gap.min), height: thickness)
            } else {
                merged = GridRect(x: Int(round(center.x - Float(thickness)*0.5)), y: gap.min, width: thickness, height: max(1, gap.max - gap.min))
            }
            
            let clamped = clamp(merged, w: w, h: h)
            return (clamped.area >= 4 && clamped.maxDimension >= 4) ? clamped : nil
        }.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
    }

    private static func refineGap(startX sx: Int, startY sy: Int, axis: Axis, mask: [Bool], w: Int, h: Int, fallback: (min: Int, max: Int), maxRaycast: Int) -> (min: Int, max: Int) {
        func isWall(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] }
        var cx = sx, cy = sy

        if isWall(cx, cy) {
            var clear = false
            for off in 1...15 {
                if axis == .horizontal {
                    if !isWall(cx + off, cy) { cx += off; clear = true; break }
                    if !isWall(cx - off, cy) { cx -= off; clear = true; break }
                } else {
                    if !isWall(cx, cy + off) { cy += off; clear = true; break }
                    if !isWall(cx, cy - off) { cy -= off; clear = true; break }
                }
            }
            if !clear { return fallback }
        }

        if axis == .horizontal {
            var l = cx, r = cx
            while l > cx - maxRaycast && !isWall(l, cy) { l -= 1 }
            while r < cx + maxRaycast && !isWall(r, cy) { r += 1 }
            if isWall(l, cy) && isWall(r, cy) { return (l + 1, r) }
        } else {
            var t = cy, b = cy
            while t > cy - maxRaycast && !isWall(cx, t) { t -= 1 }
            while b < cy + maxRaycast && !isWall(cx, b) { b += 1 }
            if isWall(cx, t) && isWall(cx, b) { return (t + 1, b) }
        }
        return fallback
    }

    private static func nearestWall(to center: SIMD2<Float>, walls: [GridRect]) -> (wall: GridRect, axis: Axis)? {
        var best: GridRect?
        var bestDistSq = Float.greatestFiniteMagnitude
        for w in walls {
            let dx = max(0, max(Float(w.x) - center.x, center.x - Float(w.x + w.width)))
            let dy = max(0, max(Float(w.y) - center.y, center.y - Float(w.y + w.height)))
            let distSq = dx*dx + dy*dy
            if distSq < bestDistSq { bestDistSq = distSq; best = w }
        }
        guard let wall = best else { return nil }
        return (wall, wall.width >= wall.height ? .horizontal : .vertical)
    }

    private static func clamp(_ r: GridRect, w: Int, h: Int) -> GridRect {
        let x = min(max(0, r.x), max(0, w - 1)), y = min(max(0, r.y), max(0, h - 1))
        return GridRect(x: x, y: y, width: min(max(1, r.width), max(1, w - x)), height: min(max(1, r.height), max(1, h - y)))
    }
}

// Compact extensions for cluster math
private extension Array where Element == OpeningAligner.Candidate {
    var avgAlong: Float { reduce(0) { $0 + $1.along } / Float(count) }
    var avgCross: Float { reduce(0) { $0 + $1.cross } / Float(count) }
    var avgProjCenter: SIMD2<Float> { reduce(.zero) { $0 + $1.projCenter } / Float(count) }
    var avgWallLine: Float? {
        let lines = compactMap(\.wallLine)
        return lines.isEmpty ? nil : lines.reduce(0, +) / Float(lines.count)
    }
    func alongRange(axis: OpeningAligner.Axis) -> (min: Int, max: Int) {
        let mins = map { axis == .horizontal ? $0.rect.x : $0.rect.y }
        let maxs = map { axis == .horizontal ? $0.rect.x + $0.rect.width : $0.rect.y + $0.rect.height }
        return (mins.min() ?? 0, maxs.max() ?? 1)
    }
}

// MARK: - Fast Grid Mesher

private enum GridMesher {
    static func extract(from mask: [Bool], width: Int, height: Int, minimumArea: Int) -> [GridRect] {
        var used = [Bool](repeating: false, count: mask.count)
        var result: [GridRect] = []

        func findBestRect(x: Int, y: Int) -> GridRect? {
            let idx = y * width + x
            guard mask[idx], !used[idx] else { return nil }

            var wW = 1, wH = 1, hH = 1, hW = 1
            while x + wW < width && mask[y * width + (x + wW)] && !used[y * width + (x + wW)] { wW += 1 }
            while y + wH < height {
                var fits = true
                for dx in 0..<wW { if !mask[(y + wH) * width + (x + dx)] || used[(y + wH) * width + (x + dx)] { fits = false; break } }
                if fits { wH += 1 } else { break }
            }

            while y + hH < height && mask[(y + hH) * width + x] && !used[(y + hH) * width + x] { hH += 1 }
            while x + hW < width {
                var fits = true
                for dy in 0..<hH { if !mask[(y + dy) * width + (x + hW)] || used[(y + dy) * width + (x + hW)] { fits = false; break } }
                if fits { hW += 1 } else { break }
            }

            return (wW * wH >= hW * hH) ? GridRect(x: x, y: y, width: wW, height: wH) : GridRect(x: x, y: y, width: hW, height: hH)
        }

        var candidates: [GridRect] = []
        for y in 0..<height {
            for x in 0..<width {
                if let r = findBestRect(x: x, y: y), r.area >= minimumArea { candidates.append(r) }
            }
        }

        candidates.sort { $0.area < $1.area }

        while !candidates.isEmpty {
            let candidate = candidates.removeLast()
            var clean = true
            for dy in 0..<candidate.height {
                for dx in 0..<candidate.width {
                    if used[(candidate.y + dy) * width + (candidate.x + dx)] { clean = false; break }
                }
                if !clean { break }
            }

            if clean {
                result.append(candidate)
                for dy in 0..<candidate.height {
                    for dx in 0..<candidate.width { used[(candidate.y + dy) * width + (candidate.x + dx)] = true }
                }
            } else if let newRect = findBestRect(x: candidate.x, y: candidate.y), newRect.area >= minimumArea {
                // Binary search insert
                var low = 0, high = candidates.count
                while low < high {
                    let mid = low + (high - low) / 2
                    if candidates[mid].area < newRect.area { low = mid + 1 } else { high = mid }
                }
                candidates.insert(newRect, at: low)
            }
        }
        return result
    }

    static func isLikelyOpening(_ rect: GridRect) -> Bool {
        guard rect.area >= 2 else { return false }
        if rect.minDimension <= 3 { return true }
        return Float(rect.maxDimension) / Float(rect.minDimension) >= 1.7
    }
}

// MARK: - Image Processing & Mask Parser

private enum FloorplanMaskParser {
    static func parse(image: CGImage, cellSize: Int) -> FloorplanGrid? {
        guard let rgba = RGBAImage(cgImage: image) else { return nil }

        let gridWidth = max(1, Int(ceil(Double(rgba.width) / Double(cellSize))))
        let gridHeight = max(1, Int(ceil(Double(rgba.height) / Double(cellSize))))
        let cellCount = gridWidth * gridHeight

        var walls = [Bool](repeating: false, count: cellCount)
        var doors = [Bool](repeating: false, count: cellCount)
        var windows = [Bool](repeating: false, count: cellCount)

        for gy in 0..<gridHeight {
            let yMin = gy * cellSize, yMax = min((gy + 1) * cellSize, rgba.height)
            for gx in 0..<gridWidth {
                let xMin = gx * cellSize, xMax = min((gx + 1) * cellSize, rgba.width)
                var wallCount = 0, doorCount = 0, windowCount = 0, sampled = 0

                for py in yMin..<yMax {
                    for px in xMin..<xMax {
                        sampled += 1
                        let offset = py * rgba.bytesPerRow + (px * 4)
                        let r = Float(rgba.pixels[offset]) / 255.0
                        let g = Float(rgba.pixels[offset + 1]) / 255.0
                        let b = Float(rgba.pixels[offset + 2]) / 255.0
                        let a = Float(rgba.pixels[offset + 3]) / 255.0

                        guard a > 0.1 else { continue }
                        let brightness = max(r, max(g, b)), darkness = min(r, min(g, b))
                        let saturation = brightness == 0 ? 0 : (brightness - darkness) / brightness

                        if r > 0.45 && r > (g * 1.5) && r > (b * 1.5) { wallCount += 1 }
                        else if g > 0.24 && g > (r * 1.2) && g > (b * 1.15) { doorCount += 1 }
                        else if b > 0.28 && b > (r * 1.1) && b > (g * 1.05) { windowCount += 1 }
                        else if saturation > 0.35 {
                            let hue = calculateHue(r: r, g: g, b: b)
                            if hue < 0.04 || hue > 0.96 { wallCount += 1 }
                            else if hue > 0.20 && hue < 0.45 { doorCount += 1 }
                            else if hue > 0.50 && hue < 0.73 { windowCount += 1 }
                        }
                    }
                }

                let index = gy * gridWidth + gx, total = max(1, sampled)
                if Float(doorCount) / Float(total) > 0.14 && doorCount >= 2 { doors[index] = true }
                else if Float(windowCount) / Float(total) > 0.14 && windowCount >= 2 { windows[index] = true }
                else if Float(wallCount) / Float(total) > 0.30 && wallCount >= 3 { walls[index] = true }
            }
        }

        let wallSnapshot = walls
        for y in 0..<gridHeight {
            for x in 0..<gridWidth {
                let index = y * gridWidth + x
                // Restored noise cleanup for doors ONLY.
                // Windows bypass this so their middle segments aren't erased.
                if doors[index] && countNeighbors(in: wallSnapshot, x: x, y: y, w: gridWidth, h: gridHeight) == 0 { doors[index] = false }
            }
        }

        var carvedWalls = walls
        for y in 0..<gridHeight {
            for x in 0..<gridWidth {
                let index = y * gridWidth + x
                guard doors[index] || windows[index] else { continue }
                carvedWalls[index] = false
                carveOpenings(x: x, y: y, snap: walls, target: &carvedWalls, w: gridWidth, h: gridHeight)
            }
        }

        carvedWalls = applyMorphology(mask: carvedWalls, w: gridWidth, h: gridHeight)

        return FloorplanGrid(width: gridWidth, height: gridHeight, wallMask: carvedWalls, doorMask: doors, windowMask: windows)
    }

    private static func carveOpenings(x: Int, y: Int, snap: [Bool], target: inout [Bool], w: Int, h: Int) {
        func val(_ cx: Int, _ cy: Int) -> Int { (cx >= 0 && cy >= 0 && cx < w && cy < h) ? (snap[cy * w + cx] ? 1 : 0) : 0 }
        let horiz = val(x-1, y) + val(x+1, y), vert = val(x, y-1) + val(x, y+1)
        
        if horiz >= vert {
            carveRay(x, y, 0, -1, &target, w, h); carveRay(x, y, 0, 1, &target, w, h)
        }
        if vert >= horiz {
            carveRay(x, y, -1, 0, &target, w, h); carveRay(x, y, 1, 0, &target, w, h)
        }
    }

    private static func carveRay(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int, _ mask: inout [Bool], _ w: Int, _ h: Int) {
        var cx = x + dx, cy = y + dy
        for _ in 0..<6 {
            guard cx >= 0 && cy >= 0 && cx < w && cy < h else { break }
            if !mask[cy * w + cx] { break }
            mask[cy * w + cx] = false
            cx += dx; cy += dy
        }
    }

    private static func applyMorphology(mask: [Bool], w: Int, h: Int) -> [Bool] {
        var current = mask
        for _ in 0..<12 {
            var next = current, removedAny = false
            for y in 0..<h {
                for x in 0..<w {
                    let i = y * w + x
                    guard current[i] else { continue }
                    
                    func v(_ cx: Int, _ cy: Int) -> Int { (cx >= 0 && cy >= 0 && cx < w && cy < h) ? (current[cy * w + cx] ? 1 : 0) : 0 }
                    let neighbors = v(x-1, y) + v(x+1, y) + v(x, y-1) + v(x, y+1)
                    
                    var isSolid2x2 = false
                    for (ox, oy) in [(x-1, y-1), (x, y-1), (x-1, y), (x, y)] {
                        if v(ox, oy) == 1 && v(ox+1, oy) == 1 && v(ox, oy+1) == 1 && v(ox+1, oy+1) == 1 { isSolid2x2 = true; break }
                    }
                    
                    if neighbors <= 1 && !isSolid2x2 { next[i] = false; removedAny = true }
                }
            }
            current = next
            if !removedAny { break }
        }

        var result = current, visited = [Bool](repeating: false, count: current.count)
        for y in 0..<h {
            for x in 0..<w {
                let start = y * w + x
                guard current[start], !visited[start] else { continue }
                var queue = [start], qIdx = 0, comp = [Int]()
                visited[start] = true
                while qIdx < queue.count {
                    let c = queue[qIdx]; qIdx += 1; comp.append(c)
                    let cx = c % w, cy = c / w
                    for (nx, ny) in [(cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)] {
                        if nx >= 0, ny >= 0, nx < w, ny < h, current[ny * w + nx], !visited[ny * w + nx] {
                            visited[ny * w + nx] = true; queue.append(ny * w + nx)
                        }
                    }
                }
                if comp.count < 10 { comp.forEach { result[$0] = false } }
            }
        }
        return result
    }

    private static func countNeighbors(in mask: [Bool], x: Int, y: Int, w: Int, h: Int) -> Int {
        var count = 0
        for ny in max(0, y-1)...min(h-1, y+1) {
            for nx in max(0, x-1)...min(w-1, x+1) {
                if (nx != x || ny != y) && mask[ny * w + nx] { count += 1 }
            }
        }
        return count
    }

    private static func calculateHue(r: Float, g: Float, b: Float) -> Float {
        let maxVal = max(r, max(g, b)), minVal = min(r, min(g, b)), delta = maxVal - minVal
        guard delta > 0.0001 else { return 0 }
        let hue = maxVal == r ? ((g - b) / delta).truncatingRemainder(dividingBy: 6.0) :
                 (maxVal == g ? ((b - r) / delta) + 2.0 : ((r - g) / delta) + 4.0)
        let normalized = hue / 6.0
        return normalized >= 0 ? normalized : normalized + 1.0
    }
}

private struct RGBAImage {
    let width: Int, height: Int, bytesPerRow: Int, pixels: [UInt8]
    init?(cgImage: CGImage) {
        width = cgImage.width; height = cgImage.height; bytesPerRow = width * 4
        var storage = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &storage, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = storage
    }
}
