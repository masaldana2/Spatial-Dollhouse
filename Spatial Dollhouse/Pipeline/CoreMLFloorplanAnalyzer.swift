import CoreGraphics
import CoreML
import UIKit

struct CoreMLFloorplanAnalyzer: FloorplanAnalyzing {
    let configurationDescription: String
    let usesBundledModel = true

    private let modelName: String
    private let model: FloorplanSegmentation

    init() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        model = try FloorplanSegmentation(configuration: configuration)
        modelName = model.model.modelDescription.metadata[.creatorDefinedKey] as? String ?? "FloorplanSegmentation"
        configurationDescription = "Bundled Core ML model running on-device with \(configuration.computeUnits.description). Uses Python-matched letterbox preprocessing."
    }

    func analyze(_ image: CGImage) async throws -> FloorplanAnalysisResult {
        let selectedCandidate = try await predictCandidate(image: image, label: "letterbox")
        let mask = selectedCandidate.mask.fillingInferredWallGaps()
        let geometrySummary = FloorplanGeometryExtractor.extract(from: mask, sourceSize: CGSize(width: image.width, height: image.height))
        let maskImage = try SegmentationPreviewRenderer.makePreview(from: mask, legendItems: SegmentationLegendItem.defaults)
        let classDistribution = makeClassDistribution(from: mask)
        let wallCoveragePercent = Int((mask.coverage(for: 1) * 100).rounded())
        let roomCoveragePercent = Int((mask.coverage(for: 4) * 100).rounded())
        let dominantClasses = mask.classHistogram()
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(3)
            .map { classID, pixelCount in
                "c\(classID)=\(pixelCount)"
            }
            .joined(separator: ", ")
        let previewImage = try SegmentationPreviewRenderer.makeOverlayPreview(
            from: mask,
            over: image,
            legendItems: SegmentationLegendItem.defaults,
            alpha: 0.42
        )
        let structureImage = try FloorplanStructureRenderer.render(
            over: image,
            summary: geometrySummary,
            legendItems: SegmentationLegendItem.defaults,
            mask: mask
        )

        return FloorplanAnalysisResult(
            previewImage: previewImage,
            maskImage: maskImage,
            structureImage: structureImage,
            legendItems: SegmentationLegendItem.defaults,
            geometrySummary: geometrySummary,
            classDistribution: classDistribution,
            summary: "Analyzed with \(modelName) using \(selectedCandidate.label) input. Built \(geometrySummary.wallSegments.count) wall segments, \(geometrySummary.junctions.count) junctions, and \(geometrySummary.openings.count) anchored openings. Mask: walls \(wallCoveragePercent)%, rooms \(roomCoveragePercent)% [\(dominantClasses)]."
        )
    }

    private func predictCandidate(image: CGImage, label: String) async throws -> PredictionCandidate {
        let prepared = try prepareInput(from: image)
        let input = FloorplanSegmentationInput(image: prepared.pixelBuffer)
        let output = try await model.prediction(input: input)
        let rawMask = FloorplanSegmentationDecoder.decode(output.class_map)
        let mask = rawMask.unletterboxed(using: prepared.layout)
        let classDistribution = makeClassDistribution(from: mask)
        logDistribution(classDistribution, label: label)
        return PredictionCandidate(label: label, mask: mask, classDistribution: classDistribution)
    }

    private func prepareInput(from image: CGImage) throws -> PreparedInput {
        let sourceImage = UIImage(cgImage: image)
        let imageSize = model.model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint?.pixelsWide ?? 1024
        let result = FloorplanCoreMLInput.letterboxedUIImageAndLayout(from: sourceImage, imageSize: imageSize)
        guard let letterboxedCGImage = result.image.cgImage else {
            throw FloorplanAnalyzerError.invalidImage
        }

        let pixelBuffer = try MLFeatureValue(
            cgImage: letterboxedCGImage,
            pixelsWide: imageSize,
            pixelsHigh: imageSize,
            pixelFormatType: kCVPixelFormatType_32ARGB,
            options: nil
        ).imageBufferValue!

        return PreparedInput(pixelBuffer: pixelBuffer, layout: result.layout)
    }

    private func makeClassDistribution(from mask: FloorplanSegmentationMask) -> [FloorplanClassDistribution] {
        let counts = mask.classHistogram()
        let totalPixels = Double(max(mask.classIDs.count, 1))

        return SegmentationLegendItem.defaults.map { item in
            let pixelCount = counts[UInt8(item.id), default: 0]
            return FloorplanClassDistribution(
                classID: item.id,
                name: item.name,
                pixelCount: pixelCount,
                percentage: Double(pixelCount) / totalPixels
            )
        }
    }

    private func logDistribution(_ distribution: [FloorplanClassDistribution], label: String) {
        let message = distribution
            .map { item in
                "\(item.name)=\(Int((item.percentage * 100).rounded()))% (\(item.pixelCount))"
            }
            .joined(separator: ", ")
        print("[CoreMLFloorplanAnalyzer] \(label): \(message)")
    }
}

private struct PredictionCandidate {
    let label: String
    let mask: FloorplanSegmentationMask
    let classDistribution: [FloorplanClassDistribution]
}

private struct PreparedInput {
    let pixelBuffer: CVPixelBuffer
    let layout: FloorplanCoreMLInput.Layout
}

private extension MLComputeUnits {
    var description: String {
        switch self {
        case .all:
            "CPU, GPU, and Neural Engine"
        case .cpuAndGPU:
            "CPU and GPU"
        case .cpuAndNeuralEngine:
            "CPU and Neural Engine"
        case .cpuOnly:
            "CPU"
        @unknown default:
            "available compute units"
        }
    }
}
