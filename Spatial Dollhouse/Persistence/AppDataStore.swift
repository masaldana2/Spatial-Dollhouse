import Foundation
import SwiftData

@MainActor
final class AppDataStore {
    let modelContainer: ModelContainer

    init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: AppDataSchema.V1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        self.modelContainer = try ModelContainer(
            for: schema,
            migrationPlan: AppDataMigrationPlan.self,
            configurations: configuration
        )
    }
}
