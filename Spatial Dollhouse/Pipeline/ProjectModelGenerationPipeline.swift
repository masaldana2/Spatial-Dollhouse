import Foundation
import ImageIO
@MainActor
struct ProjectModelGenerationPipeline {
    private let primaryAnalyzer: any FloorplanAnalyzing
    private let fallbackAnalyzer: any FloorplanAnalyzing

    init(
        analyzer: (any FloorplanAnalyzing)? = nil,
        fallbackAnalyzer: (any FloorplanAnalyzing)? = nil
    ) {
        self.primaryAnalyzer = analyzer ?? FloorplanAnalyzerFactory.makeDefault()
        self.fallbackAnalyzer = fallbackAnalyzer ?? DemoFloorplanAnalyzer()
    }

    func generateModelAsset(for project: ProjectSummary) async throws -> GeneratedProjectModelAsset {
        let image = try loadProjectImage(from: project.imageFileURL)
        let analysis = try await analyzeImageWithFallback(image)
        let canvasSize = CGSize(width: image.width, height: image.height)
        let primitives = FloorplanSceneBuilder.makeExportPrimitives(
            summary: analysis.geometrySummary,
            canvasSize: canvasSize
        )
        let immersiveScene = StoredFloorplanScene(
            canvasSize: canvasSize,
            geometrySummary: analysis.geometrySummary
        )

        return GeneratedProjectModelAsset(
            filename: "\(sanitizedFilename(from: project.name)).obj",
            primitives: primitives,
            immersiveScene: immersiveScene
        )
    }

    private func loadProjectImage(from url: URL) throws -> CGImage {
        let imageData = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FloorplanAnalyzerError.invalidImage
        }
        return image
    }

    private func sanitizedFilename(from name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let pieces = name.components(separatedBy: invalidCharacters)
        let collapsed = pieces.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = collapsed.replacingOccurrences(of: " ", with: "-")
        return compact.isEmpty ? "Project" : compact
    }

    private func analyzeImageWithFallback(_ image: CGImage) async throws -> FloorplanAnalysisResult {
        do {
            return try await primaryAnalyzer.analyze(image)
        } catch {
            print("[ProjectModelGenerationPipeline] Primary analyzer failed: \(error.localizedDescription). Falling back to demo analyzer.")
            return try await fallbackAnalyzer.analyze(image)
        }
    }
}

@MainActor
struct GeneratedProjectModelAsset {
    let filename: String
    let primitives: [FloorplanScenePrimitive]
    let immersiveScene: StoredFloorplanScene

    func write(to url: URL) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path()) {
            try fileManager.removeItem(at: url)
        }
        try FloorplanOBJExporter.writeOBJ(primitives: primitives, to: url)
    }

    func encodedImmersiveScene() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(immersiveScene)
    }
}
