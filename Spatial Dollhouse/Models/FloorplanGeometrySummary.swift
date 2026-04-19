import CoreGraphics

enum FloorplanRegionKind: String, CaseIterable, Identifiable {
    case room
    case door
    case window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .room:
            "Rooms"
        case .door:
            "Doors"
        case .window:
            "Windows"
        }
    }

    var singularTitle: String {
        switch self {
        case .room:
            "Room"
        case .door:
            "Door"
        case .window:
            "Window"
        }
    }

    var legendClassID: Int {
        switch self {
        case .room:
            4
        case .door:
            2
        case .window:
            3
        }
    }
}

enum WallAxis: String, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal:
            "Horizontal"
        case .vertical:
            "Vertical"
        }
    }
}

struct FloorplanDetectedRegion: Identifiable {
    let id: String
    let kind: FloorplanRegionKind
    let boundingBox: CGRect
    let pixelArea: Int

    var title: String {
        "\(kind.singularTitle) \(id)"
    }

    var pixelSizeSummary: String {
        "\(Int(boundingBox.width)) x \(Int(boundingBox.height)) px"
    }
}

struct FloorplanWallSegment: Identifiable {
    let id: String
    let axis: WallAxis
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat

    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    var center: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    var lengthSummary: String {
        "\(Int(length.rounded())) px"
    }

    var thicknessSummary: String {
        "\(Int(thickness.rounded())) px"
    }
}

struct FloorplanWallJunction: Identifiable {
    let id: String
    let point: CGPoint
    let horizontalWallID: String
    let verticalWallID: String

    var title: String {
        "\(horizontalWallID) x \(verticalWallID)"
    }
}

struct FloorplanOpeningCandidate: Identifiable {
    let id: String
    let kind: FloorplanRegionKind
    let axis: WallAxis
    let center: CGPoint
    let span: CGFloat
    let boundingBox: CGRect
    let attachedWallID: String?
    let snappedCenter: CGPoint?
    let snappedStart: CGPoint?
    let snappedEnd: CGPoint?
    let offsetFromWall: CGFloat?

    var title: String {
        "\(kind.singularTitle) \(id)"
    }

    var spanSummary: String {
        "\(Int(span.rounded())) px"
    }

    var anchorSummary: String {
        if let attachedWallID {
            if let offsetFromWall {
                return "\(attachedWallID) | d=\(Int(offsetFromWall.rounded())) px"
            }
            return attachedWallID
        }
        return "Unattached"
    }
}

struct FloorplanGeometrySummary {
    let roomCount: Int
    let doorCount: Int
    let windowCount: Int
    let wallCoverage: Double
    let segmentationMask: FloorplanSegmentationMask?
    let regions: [FloorplanDetectedRegion]
    let wallSegments: [FloorplanWallSegment]
    let junctions: [FloorplanWallJunction]
    let openings: [FloorplanOpeningCandidate]

    static let empty = FloorplanGeometrySummary(
        roomCount: 0,
        doorCount: 0,
        windowCount: 0,
        wallCoverage: 0,
        segmentationMask: nil,
        regions: [],
        wallSegments: [],
        junctions: [],
        openings: []
    )
}
