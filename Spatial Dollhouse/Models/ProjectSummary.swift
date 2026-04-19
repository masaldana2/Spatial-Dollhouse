import Foundation

struct ProjectSummary: Identifiable, Hashable {
    let id: UUID
    var name: String
    var thumbnailData: Data?
    var directoryURL: URL
    var imageFileURL: URL
    var modelFileURL: URL?
    var generationState: ProjectGenerationState
    
    var isImmersiveReady: Bool {
        generationState == .ready && modelFileURL != nil
    }

    init(
        id: UUID = UUID(),
        name: String,
        thumbnailData: Data? = nil,
        directoryURL: URL,
        imageFileURL: URL,
        modelFileURL: URL? = nil,
        generationState: ProjectGenerationState = .idle
    ) {
        self.id = id
        self.name = name
        self.thumbnailData = thumbnailData
        self.directoryURL = directoryURL
        self.imageFileURL = imageFileURL
        self.modelFileURL = modelFileURL
        self.generationState = generationState
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
