import Foundation
import SwiftData

typealias Comic = ComicSchemaV2.Comic
typealias ComicPage = ComicSchemaV2.ComicPage
typealias ComicImages = ComicSchemaV2.ComicPageImages

enum ComicMigrationPlan: SchemaMigrationPlan {

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: ComicSchemaV1.self,
        toVersion: ComicSchemaV2.self
    )

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // List schema versions in order from oldest to newest.
    static var schemas: [any VersionedSchema.Type] = [
        ComicSchemaV1.self,
        ComicSchemaV2.self
    ]
}
