import Foundation
import SwiftData

enum AppDataModels_v1 {
    @Model
    final class ProjectRecord {
        #Unique<ProjectRecord>([\.id])
        #Index<ProjectRecord>([\.name], [\.updatedAt])

        var id: UUID
        var name: String
        var directoryName: String
        var imageFilename: String
        var modelFilename: String?
        var generationStatus: String
        var generationErrorMessage: String?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID,
            name: String,
            directoryName: String,
            imageFilename: String,
            modelFilename: String?,
            generationStatus: String,
            generationErrorMessage: String?,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.name = name
            self.directoryName = directoryName
            self.imageFilename = imageFilename
            self.modelFilename = modelFilename
            self.generationStatus = generationStatus
            self.generationErrorMessage = generationErrorMessage
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}
