import Foundation
import SwiftData
import Testing
@testable import millio

/// Верифицирует, что AppSchemaCurrent.models и AppMigrationPlan содержат идентичный набор типов.
/// Тест становится красным при добавлении нового @Model без обновления AppSchemaCurrent (или наоборот).
///
/// Как читать падение:
///   "SchemaConsistency/currentSchemaMatchesMigrationPlan: ..."
///   → в difference будут имена типов, присутствующих только в одном из источников.
///   → Добавь тип в AppSchemaCurrent.models И убедись что AppMigrationPlan.makeContainer включает его.
@Suite("SchemaConsistency")
struct SchemaConsistencyTests {

    /// AppSchemaCurrent.models и AppMigrationPlan открывают одинаковый набор таблиц.
    @Test @MainActor
    func currentSchemaMatchesMigrationPlan() throws {
        let schemaNames = Set(AppSchemaCurrent.models.map { entityName(for: $0) })

        let config = ModelConfiguration(
            "consistency_check_\(UUID().uuidString)",
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try AppMigrationPlan.makeContainer(configuration: config)
        let planNames = Set(container.schema.entities.map { $0.name })

        let diff = schemaNames.symmetricDifference(planNames)
        #expect(diff.isEmpty,
            "AppSchemaCurrent.models и AppMigrationPlan расходятся: \(diff). " +
            "Добавь тип в AppSchemaCurrent.models И в AppMigrationPlan.")
    }

    /// AppSchemaV2.models ⊇ AppSchemaV1.models — V2 не теряет типы из V1.
    @Test
    func v2IsSupersetOfV1() {
        let v1Names = Set(AppSchemaV1.models.map { entityName(for: $0) })
        let v2Names = Set(AppSchemaV2.models.map { entityName(for: $0) })
        let missing = v1Names.subtracting(v2Names)
        #expect(missing.isEmpty,
            "V1 содержит типы, отсутствующие в V2: \(missing). " +
            "V2 должна быть надмножеством V1.")
    }

    /// AppSchema.create() возвращает схему из тех же типов что и AppSchemaCurrent.
    @Test
    func appSchemaCreateMatchesSchemaCurrent() {
        let currentNames = Set(AppSchemaCurrent.models.map { entityName(for: $0) })
        let createdNames = Set(AppSchema.create().entities.map { $0.name })
        let diff = currentNames.symmetricDifference(createdNames)
        #expect(diff.isEmpty,
            "AppSchema.create() и AppSchemaCurrent.models расходятся: \(diff).")
    }

    // MARK: - Helper

    private func entityName(for type: any PersistentModel.Type) -> String {
        // SwiftData использует простое имя типа как имя entity.
        String(describing: type).components(separatedBy: ".").last ?? String(describing: type)
    }
}
