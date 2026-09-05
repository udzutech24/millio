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
            Comment(rawValue:
                "AppSchemaCurrent.models и AppMigrationPlan расходятся: \(diff). " +
                "Добавь тип в AppSchemaCurrent.models И в AppMigrationPlan."
            ))
    }

    /// AppSchemaV2.models ⊇ AppSchemaV1.models — V2 не теряет типы из V1.
    @Test
    func v2IsSupersetOfV1() {
        let v1Names = Set(AppSchemaV1.models.map { entityName(for: $0) })
        let v2Names = Set(AppSchemaV2.models.map { entityName(for: $0) })
        let missing = v1Names.subtracting(v2Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V1 содержит типы, отсутствующие в V2: \(missing). " +
                "V2 должна быть надмножеством V1."
            ))
    }

    /// AppSchemaV3.models ⊇ AppSchemaV2.models — V3 не теряет типы из V2.
    @Test
    func v3IsSupersetOfV2() {
        let v2Names = Set(AppSchemaV2.models.map { entityName(for: $0) })
        let v3Names = Set(AppSchemaV3.models.map { entityName(for: $0) })
        let missing = v2Names.subtracting(v3Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V2 содержит типы, отсутствующие в V3: \(missing). " +
                "V3 должна быть надмножеством V2."
            ))
    }

    /// AppSchemaV4.models ⊇ AppSchemaV3.models — V4 не теряет типы из V3.
    @Test
    func v4IsSupersetOfV3() {
        let v3Names = Set(AppSchemaV3.models.map { entityName(for: $0) })
        let v4Names = Set(AppSchemaV4.models.map { entityName(for: $0) })
        let missing = v3Names.subtracting(v4Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V3 содержит типы, отсутствующие в V4: \(missing). " +
                "V4 должна быть надмножеством V3."
            ))
    }

    /// AppSchemaV5.models ⊇ AppSchemaV4.models — V5 не теряет типы из V4.
    /// Этот тест — прямая страховка от Находки 2 (HistoricalAssetPrice был задним числом
    /// дописан в V4.models вместо новой версии, что ломало staged migration на dev-сторах).
    @Test
    func v5IsSupersetOfV4() {
        let v4Names = Set(AppSchemaV4.models.map { entityName(for: $0) })
        let v5Names = Set(AppSchemaV5.models.map { entityName(for: $0) })
        let missing = v4Names.subtracting(v5Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V4 содержит типы, отсутствующие в V5: \(missing). " +
                "V5 должна быть надмножеством V4."
            ))
    }

    /// V6 swaps the frozen V5 AccountsCore declarations for their current counterparts while
    /// preserving the same entity set. The V5→V6 stage owns the additive product columns.
    @Test
    func v6IsSupersetOfV5() {
        let v5Names = Set(AppSchemaV5.models.map { entityName(for: $0) })
        let v6Names = Set(AppSchemaV6.models.map { entityName(for: $0) })
        let missing = v5Names.subtracting(v6Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V5 содержит типы, отсутствующие в V6: \(missing). " +
                "V6 должна сохранять все released entity names V5."
            ))
    }

    /// V7 preserves every V6 entity and adds the immutable close table. Account revision columns
    /// are optional and therefore belong to this lightweight boundary, not to frozen V6.
    @Test
    func v7IsSupersetOfV6() {
        let v6Names = Set(AppSchemaV6.models.map { entityName(for: $0) })
        let v7Names = Set(AppSchemaV7.models.map { entityName(for: $0) })
        let missing = v6Names.subtracting(v7Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V6 содержит типы, отсутствующие в V7: \(missing). " +
                "V7 должна сохранять все released entity names V6."
            ))
        #expect(v7Names.contains("HistoricalPortfolioValuation"))
    }

    @Test
    func v8IsAdditiveOverV7() {
        let v7Names = Set(AppSchemaV7.models.map { entityName(for: $0) })
        let v8Names = Set(AppSchemaV8.models.map { entityName(for: $0) })
        #expect(v7Names.subtracting(v8Names).isEmpty)
        #expect(v8Names.subtracting(v7Names) == ["RealEstateProfile", "AccountAttachment"])
    }

    /// V10 — первая версия, чей `models` собран заново, а не как `AppSchemaV9.models + [...]`.
    /// Аддитивность больше не гарантирована конструкцией, поэтому её проверяет тест: потерянная
    /// строка в списке = молча удалённая таблица у пользователей на V9-сторах.
    @Test
    func v10PreservesEveryV9Entity() {
        let v9Names = Set(AppSchemaV9.models.map { entityName(for: $0) })
        let v10Names = Set(AppSchemaV10.models.map { entityName(for: $0) })
        let missing = v9Names.subtracting(v10Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V9 содержит типы, отсутствующие в V10: \(missing). " +
                "V10 должна сохранять все released entity names V9."
            ))
        #expect(v10Names.subtracting(v9Names).isEmpty,
            Comment(rawValue:
                "V10 добавляет таблицы \(v10Names.subtracting(v9Names)), хотя заявлена как " +
                "изменение только атрибутов DepositMeta. Новая таблица требует своей версии схемы."
            ))
    }

    /// V11 аддитивна: добавляет ровно `AccountAppearance` и не теряет ни одной таблицы V10.
    /// Потерянная строка = молча удалённая таблица у пользователей на V10-сторах.
    @Test
    func v11PreservesEveryV10Entity() {
        let v10Names = Set(AppSchemaV10.models.map { entityName(for: $0) })
        let v11Names = Set(AppSchemaV11.models.map { entityName(for: $0) })
        let missing = v10Names.subtracting(v11Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V10 содержит типы, отсутствующие в V11: \(missing). " +
                "V11 должна сохранять все released entity names V10."
            ))
        #expect(v11Names.subtracting(v10Names) == ["AccountAppearance"],
            Comment(rawValue:
                "V11 заявлена как добавление одной таблицы AccountAppearance, а добавляет " +
                "\(v11Names.subtracting(v10Names)). Каждая новая таблица требует своей версии схемы."
            ))
    }

    /// V12 аддитивна: добавляет ровно `LoanContract` и не теряет ни одной таблицы V11.
    /// Потерянная строка = молча удалённая таблица у пользователей на V11-сторах.
    @Test
    func v12PreservesEveryV11Entity() {
        let v11Names = Set(AppSchemaV11.models.map { entityName(for: $0) })
        let v12Names = Set(AppSchemaV12.models.map { entityName(for: $0) })
        let missing = v11Names.subtracting(v12Names)
        #expect(missing.isEmpty,
            Comment(rawValue:
                "V11 содержит типы, отсутствующие в V12: \(missing). " +
                "V12 должна сохранять все released entity names V11."
            ))
        #expect(v12Names.subtracting(v11Names) == ["LoanContract"],
            Comment(rawValue:
                "V12 заявлена как добавление одной таблицы LoanContract, а добавляет " +
                "\(v12Names.subtracting(v11Names)). Каждая новая таблица требует своей версии схемы."
            ))
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
