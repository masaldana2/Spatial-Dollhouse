import Foundation

enum FloorplanAnalyzerError: LocalizedError {
    case modelNotFound
    case invalidImage
    case unsupportedModelOutput
    case analysisFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "No Core ML model was found in the app bundle. Add your compiled .mlpackage to the target to run live inference."
        case .invalidImage:
            return "The selected file could not be decoded as a valid image."
        case .unsupportedModelOutput:
            return "The model ran, but its output format is not supported by this preview renderer yet."
        case .analysisFailed:
            return "The floorplan analysis request did not return a usable result."
        }
    }
}
