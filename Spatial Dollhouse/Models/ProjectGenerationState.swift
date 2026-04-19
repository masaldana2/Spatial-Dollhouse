import Foundation

enum ProjectGenerationState: Equatable {
    case idle
    case generating
    case ready
    case failed(String)

    var statusValue: String {
        switch self {
        case .idle:
            return "idle"
        case .generating:
            return "generating"
        case .ready:
            return "ready"
        case .failed:
            return "failed"
        }
    }

    var description: String {
        switch self {
        case .idle:
            return "Pending 3D generation."
        case .generating:
            return "Generating 3D model..."
        case .ready:
            return "3D model ready."
        case let .failed(message):
            return message.isEmpty ? "3D model generation failed." : message
        }
    }
}
