import CoreGraphics

protocol FloorplanAnalyzing {
    var configurationDescription: String { get }
    var usesBundledModel: Bool { get }

    func analyze(_ image: CGImage) async throws -> FloorplanAnalysisResult
}
