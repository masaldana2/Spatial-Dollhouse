import SwiftData

enum AppDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppDataSchema.V1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
