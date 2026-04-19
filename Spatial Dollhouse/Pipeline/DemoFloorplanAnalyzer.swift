import CoreGraphics

struct DemoFloorplanAnalyzer: FloorplanAnalyzing {
    let configurationDescription = "Using demo analyzer. Add your bundled Core ML model to switch to live inference."
    let usesBundledModel = false

    func analyze(_ image: CGImage) async throws -> FloorplanAnalysisResult {
        let room1 = FloorplanDetectedRegion(id: "R1", kind: .room, boundingBox: CGRect(x: 60, y: 80, width: 180, height: 140), pixelArea: 21_000)
        let room2 = FloorplanDetectedRegion(id: "R2", kind: .room, boundingBox: CGRect(x: 270, y: 80, width: 160, height: 140), pixelArea: 18_000)
        let door = FloorplanDetectedRegion(id: "D1", kind: .door, boundingBox: CGRect(x: 238, y: 120, width: 18, height: 42), pixelArea: 300)
        let window = FloorplanDetectedRegion(id: "W1", kind: .window, boundingBox: CGRect(x: 120, y: 68, width: 56, height: 12), pixelArea: 220)

        let geometrySummary = FloorplanGeometrySummary(
            roomCount: 4,
            doorCount: 3,
            windowCount: 2,
            wallCoverage: 0.24,
            segmentationMask: nil,
            regions: [room1, room2, door, window],
            wallSegments: [
                FloorplanWallSegment(id: "H1", axis: .horizontal, start: CGPoint(x: 60, y: 80), end: CGPoint(x: 430, y: 80), thickness: 10),
                FloorplanWallSegment(id: "H2", axis: .horizontal, start: CGPoint(x: 60, y: 220), end: CGPoint(x: 430, y: 220), thickness: 10),
                FloorplanWallSegment(id: "V1", axis: .vertical, start: CGPoint(x: 60, y: 80), end: CGPoint(x: 60, y: 220), thickness: 10),
                FloorplanWallSegment(id: "V2", axis: .vertical, start: CGPoint(x: 430, y: 80), end: CGPoint(x: 430, y: 220), thickness: 10),
                FloorplanWallSegment(id: "V3", axis: .vertical, start: CGPoint(x: 248, y: 80), end: CGPoint(x: 248, y: 220), thickness: 8)
            ],
            junctions: [
                FloorplanWallJunction(id: "J1", point: CGPoint(x: 60, y: 80), horizontalWallID: "H1", verticalWallID: "V1"),
                FloorplanWallJunction(id: "J2", point: CGPoint(x: 430, y: 80), horizontalWallID: "H1", verticalWallID: "V2"),
                FloorplanWallJunction(id: "J3", point: CGPoint(x: 248, y: 80), horizontalWallID: "H1", verticalWallID: "V3"),
                FloorplanWallJunction(id: "J4", point: CGPoint(x: 248, y: 220), horizontalWallID: "H2", verticalWallID: "V3")
            ],
            openings: [
                FloorplanOpeningCandidate(
                    id: "D1",
                    kind: .door,
                    axis: .vertical,
                    center: CGPoint(x: 246, y: 141),
                    span: 42,
                    boundingBox: door.boundingBox,
                    attachedWallID: "V3",
                    snappedCenter: CGPoint(x: 248, y: 141),
                    snappedStart: CGPoint(x: 248, y: 120),
                    snappedEnd: CGPoint(x: 248, y: 162),
                    offsetFromWall: 2
                ),
                FloorplanOpeningCandidate(
                    id: "W1",
                    kind: .window,
                    axis: .horizontal,
                    center: CGPoint(x: 148, y: 74),
                    span: 56,
                    boundingBox: window.boundingBox,
                    attachedWallID: "H1",
                    snappedCenter: CGPoint(x: 148, y: 80),
                    snappedStart: CGPoint(x: 120, y: 80),
                    snappedEnd: CGPoint(x: 176, y: 80),
                    offsetFromWall: 6
                )
            ]
        )

        let previewImage = try SegmentationPreviewRenderer.makeDemoPreview(
            width: image.width,
            height: image.height,
            legendItems: SegmentationLegendItem.defaults
        )
        let maskImage = previewImage
        let structureImage = try FloorplanStructureRenderer.render(
            over: image,
            summary: geometrySummary,
            legendItems: SegmentationLegendItem.defaults
        )

        return FloorplanAnalysisResult(
            previewImage: previewImage,
            maskImage: maskImage,
            structureImage: structureImage,
            legendItems: SegmentationLegendItem.defaults,
            geometrySummary: geometrySummary,
            classDistribution: [
                FloorplanClassDistribution(classID: 0, name: "Background", pixelCount: 90_000, percentage: 0.35),
                FloorplanClassDistribution(classID: 1, name: "Walls", pixelCount: 61_000, percentage: 0.24),
                FloorplanClassDistribution(classID: 2, name: "Doors", pixelCount: 4_000, percentage: 0.02),
                FloorplanClassDistribution(classID: 3, name: "Windows", pixelCount: 3_000, percentage: 0.01),
                FloorplanClassDistribution(classID: 4, name: "Rooms", pixelCount: 96_000, percentage: 0.37),
                FloorplanClassDistribution(classID: 5, name: "Fixed Objects", pixelCount: 3_000, percentage: 0.01),
                FloorplanClassDistribution(classID: 6, name: "Text / Symbols", pixelCount: 2_000, percentage: 0.01)
            ],
            summary: "Demo preview ready. The wall network now includes refined segments, junctions, and anchored openings."
        )
    }
}
