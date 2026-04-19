import CoreGraphics

extension FloorplanSemanticModel {
    init(summary: FloorplanGeometrySummary, canvasSize: CGSize, cellSize: Int) {
        let safeCellSize = max(cellSize, 1)
        let gridWidth = max(Int(ceil(canvasSize.width / CGFloat(safeCellSize))), 1)
        let gridHeight = max(Int(ceil(canvasSize.height / CGFloat(safeCellSize))), 1)

        self.init(
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            walls: Self.makeWallRects(from: summary.wallSegments, cellSize: safeCellSize, gridWidth: gridWidth, gridHeight: gridHeight),
            doors: Self.makeOpeningRects(kind: .door, from: summary.openings, cellSize: safeCellSize, gridWidth: gridWidth, gridHeight: gridHeight),
            windows: Self.makeOpeningRects(kind: .window, from: summary.openings, cellSize: safeCellSize, gridWidth: gridWidth, gridHeight: gridHeight)
        )
    }

    private static func makeWallRects(
        from segments: [FloorplanWallSegment],
        cellSize: Int,
        gridWidth: Int,
        gridHeight: Int
    ) -> [GridRect] {
        Array(
            Set(
                segments.map { segment in
                    let bounds: CGRect
                    switch segment.axis {
                    case .horizontal:
                        bounds = CGRect(
                            x: min(segment.start.x, segment.end.x),
                            y: segment.center.y - (segment.thickness / 2),
                            width: segment.length,
                            height: segment.thickness
                        )
                    case .vertical:
                        bounds = CGRect(
                            x: segment.center.x - (segment.thickness / 2),
                            y: min(segment.start.y, segment.end.y),
                            width: segment.thickness,
                            height: segment.length
                        )
                    }
                    return gridRect(from: bounds, cellSize: cellSize, gridWidth: gridWidth, gridHeight: gridHeight)
                }
            )
        )
        .sorted { lhs, rhs in
            if lhs.y == rhs.y {
                return lhs.x < rhs.x
            }
            return lhs.y < rhs.y
        }
    }

    private static func makeOpeningRects(
        kind: FloorplanRegionKind,
        from openings: [FloorplanOpeningCandidate],
        cellSize: Int,
        gridWidth: Int,
        gridHeight: Int
    ) -> [GridRect] {
        Array(
            Set(
                openings
                    .filter { $0.kind == kind }
                    .map { opening in
                        gridRect(
                            from: opening.boundingBox,
                            cellSize: cellSize,
                            gridWidth: gridWidth,
                            gridHeight: gridHeight
                        )
                    }
            )
        )
        .sorted { lhs, rhs in
            if lhs.y == rhs.y {
                return lhs.x < rhs.x
            }
            return lhs.y < rhs.y
        }
    }

    private static func gridRect(
        from bounds: CGRect,
        cellSize: Int,
        gridWidth: Int,
        gridHeight: Int
    ) -> GridRect {
        let scale = CGFloat(cellSize)
        let minX = max(Int(floor(bounds.minX / scale)), 0)
        let minY = max(Int(floor(bounds.minY / scale)), 0)
        let maxX = min(Int(ceil(bounds.maxX / scale)), gridWidth)
        let maxY = min(Int(ceil(bounds.maxY / scale)), gridHeight)

        return GridRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1),
            height: max(maxY - minY, 1)
        )
    }
}
