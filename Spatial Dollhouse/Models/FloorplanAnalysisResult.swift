import CoreGraphics

struct FloorplanAnalysisResult {
    let previewImage: CGImage
    let maskImage: CGImage
    let structureImage: CGImage?
    let legendItems: [SegmentationLegendItem]
    let geometrySummary: FloorplanGeometrySummary
    let classDistribution: [FloorplanClassDistribution]
    let summary: String
}

struct FloorplanClassDistribution: Identifiable {
    let classID: Int
    let name: String
    let pixelCount: Int
    let percentage: Double

    var id: Int { classID }
}
