import Foundation
import SwiftData

enum ComicMigrationPlan: SchemaMigrationPlan {
    static let migrateV1toV1 = MigrationStage.custom(
        fromVersion: ComicSchemaV1.self,
        toVersion: ComicSchemaV1.self,
        willMigrate: { _ in
            // remove duplicates then save
        }, didMigrate: nil
    )

    static var stages: [MigrationStage] {
        [migrateV1toV1]
    }

    // List schema versions in order from oldest to newest.
    static var schemas: [any VersionedSchema.Type] = [
        ComicSchemaV1.self
    ]
}
