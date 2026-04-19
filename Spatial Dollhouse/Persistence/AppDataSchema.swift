import Foundation
import SwiftData

enum AppDataSchema {
    enum V1: VersionedSchema {
        static let versionIdentifier = Schema.Version(1, 0, 0)

        static var models: [any PersistentModel.Type] {
            [AppDataModels_v1.ProjectRecord.self]
        }
    }
}
