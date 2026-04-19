import Foundation
import ImageIO
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class FloorplanViewModel {
    var importedImage: UIImage?
    var previewImage: UIImage?
    var maskImage: UIImage?
    var structureImage: UIImage?
    var legendItems: [SegmentationLegendItem] = SegmentationLegendItem.defaults
    var classDistribution: [FloorplanClassDistribution] = []
    var geometrySummary = FloorplanGeometrySummary.empty
    var statusMessage: String
    var analysisSummary: String?
    var errorMessage: String?
    var isAnalyzing = false
    var usesBundledModel: Bool
    var analyzerDescription: String

    private let analyzer: any FloorplanAnalyzing

    init(analyzer: (any FloorplanAnalyzing)? = nil) {
        let resolvedAnalyzer = analyzer ?? FloorplanAnalyzerFactory.makeDefault()
        self.analyzer = resolvedAnalyzer
        self.usesBundledModel = resolvedAnalyzer.usesBundledModel
        self.analyzerDescription = resolvedAnalyzer.configurationDescription
        self.statusMessage = resolvedAnalyzer.configurationDescription
    }

    var analyzerIconName: String {
        usesBundledModel ? "checkmark.seal.fill" : "shippingbox.fill"
    }

    func handleImportResult(_ result: Result<URL, any Error>) {
        Task {
            do {
                let url = try result.get()
                try await importImage(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func importImage(from url: URL) async throws {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FloorplanAnalyzerError.invalidImage
        }
        let image = UIImage(cgImage: cgImage)

        importedImage = image
        previewImage = nil
        maskImage = nil
        structureImage = nil
        geometrySummary = .empty
        classDistribution = []
        analysisSummary = nil
        errorMessage = nil
        statusMessage = "Imported \(url.lastPathComponent). Ready to analyze."
    }

    func analyzeCurrentImage() async {
        guard !isAnalyzing else { return }
        guard let importedImage, let cgImage = importedImage.normalizedCGImage else {
            errorMessage = FloorplanAnalyzerError.invalidImage.errorDescription
            return
        }

        isAnalyzing = true
        errorMessage = nil
        statusMessage = "Running floorplan analysis..."

        do {
            let result = try await analyzer.analyze(cgImage)
            previewImage = UIImage(cgImage: result.previewImage)
            maskImage = UIImage(cgImage: result.maskImage)
            structureImage = result.structureImage.map(UIImage.init(cgImage:))
            legendItems = result.legendItems
            classDistribution = result.classDistribution
            geometrySummary = result.geometrySummary
            analysisSummary = result.summary
            statusMessage = result.summary
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Analysis failed."
        }

        isAnalyzing = false
    }
}
