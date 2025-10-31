import Foundation
import SwiftData

typealias CurrentComicSchema = ComicSchemaV4

typealias Comic = CurrentComicSchema.Comic
typealias ComicPage = CurrentComicSchema.ComicPage
typealias ComicImage = CurrentComicSchema.ComicPageImage

enum ComicMigrationPlan: SchemaMigrationPlan {
    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: ComicSchemaV1.self,
                toVersion: ComicSchemaV2.self
            ),
            .lightweight(
                fromVersion: ComicSchemaV2.self,
                toVersion: ComicSchemaV3.self
            ),
            .lightweight(
                fromVersion: ComicSchemaV3.self,
                toVersion: ComicSchemaV4.self
            )
        ]
    }

    // List schema versions in order from oldest to newest.
    static var schemas: [any VersionedSchema.Type] = [
        ComicSchemaV1.self,
        ComicSchemaV2.self,
        ComicSchemaV3.self,
        ComicSchemaV4.self
    ]
}
