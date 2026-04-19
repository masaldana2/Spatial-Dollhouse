import Foundation

struct StoredProjectMetadata: Codable {
    let id: UUID
    let name: String
    let imageFilename: String
    let modelFilename: String?
    let generationStatus: String
    let generationErrorMessage: String?

    init(
        id: UUID,
        name: String,
        imageFilename: String,
        modelFilename: String?,
        generationStatus: String,
        generationErrorMessage: String?
    ) {
        self.id = id
        self.name = name
        self.imageFilename = imageFilename
        self.modelFilename = modelFilename
        self.generationStatus = generationStatus
        self.generationErrorMessage = generationErrorMessage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        imageFilename = try container.decode(String.self, forKey: .imageFilename)
        modelFilename = try container.decodeIfPresent(String.self, forKey: .modelFilename)
        generationStatus = try container.decodeIfPresent(String.self, forKey: .generationStatus) ?? "idle"
        generationErrorMessage = try container.decodeIfPresent(String.self, forKey: .generationErrorMessage)
    }
}
