import Foundation

struct ProjectSummary: Identifiable, Hashable {
    let id: UUID
    var name: String
    var thumbnailData: Data?
    var directoryURL: URL
    var imageFileURL: URL
    var modelFileURL: URL?
    var geometryFileURL: URL?
    var generationState: ProjectGenerationState
    
    var isImmersiveReady: Bool {
        generationState == .ready && geometryFileURL != nil
    }

    init(
        id: UUID = UUID(),
        name: String,
        thumbnailData: Data? = nil,
        directoryURL: URL,
        imageFileURL: URL,
        modelFileURL: URL? = nil,
        geometryFileURL: URL? = nil,
        generationState: ProjectGenerationState = .idle
    ) {
        self.id = id
        self.name = name
        self.thumbnailData = thumbnailData
        self.directoryURL = directoryURL
        self.imageFileURL = imageFileURL
        self.modelFileURL = modelFileURL
        self.geometryFileURL = geometryFileURL
        self.generationState = generationState
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
