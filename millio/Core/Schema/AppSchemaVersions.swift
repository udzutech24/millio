import SwiftData

// MARK: - V1 (исходная схема без UserSubscription)

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        Item.self,
        CashflowTransaction.self,
        CashflowSystemCategoryOverride.self,
        CashflowCustomCategory.self,
        BudgetPlan.self,
        BudgetCategoryLimit.self,
        Cashback.self,
        CashbackCustomCategory.self,
        Card.self,
        FinanceAccount.self,
        FinanceGroup.self,
        Credit.self,
        Investment.self,
        AssetCatalogItem.self,
        AssetProviderMapping.self,
        HistoricalRate.self,
    ]
}

// MARK: - V2 (добавлена UserSubscription)

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [
        Item.self,
        CashflowTransaction.self,
        CashflowSystemCategoryOverride.self,
        CashflowCustomCategory.self,
        BudgetPlan.self,
        BudgetCategoryLimit.self,
        Cashback.self,
        UserSubscription.self,
        CashbackCustomCategory.self,
        Card.self,
        FinanceAccount.self,
        FinanceGroup.self,
        Credit.self,
        Investment.self,
        AssetCatalogItem.self,
        AssetProviderMapping.self,
        HistoricalRate.self,
    ]
}

// MARK: - Текущая схема (единственный источник правды)

// При добавлении нового @Model:
//   1. Создать AppSchemaV{N+1} с новым типом в models
//   2. Добавить lightweight stage V{N}→V{N+1} в AppMigrationPlan.stages
//   3. Обновить этот typealias на AppSchemaV{N+1}
//   4. Запустить SchemaConsistencyTests — должны быть зелёными
typealias AppSchemaCurrent = AppSchemaV2

// MARK: - План миграции

// Существующие сторы без версионирования трактуются как V1 и безопасно мигрируют.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [
        AppSchemaV1.self,
        AppSchemaV2.self,
    ]

    static var stages: [MigrationStage] = [
        .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self),
    ]
}

// MARK: - Фабрика контейнеров

// SwiftData требует variadic-форму для передачи migrationPlan.
// Все вызовы ModelContainer с планом миграции должны идти через эти методы.
extension AppMigrationPlan {
    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Item.self,
                 CashflowTransaction.self,
                 CashflowSystemCategoryOverride.self,
                 CashflowCustomCategory.self,
                 BudgetPlan.self,
                 BudgetCategoryLimit.self,
                 Cashback.self,
                 UserSubscription.self,
                 CashbackCustomCategory.self,
                 Card.self,
                 FinanceAccount.self,
                 FinanceGroup.self,
                 Credit.self,
                 Investment.self,
                 AssetCatalogItem.self,
                 AssetProviderMapping.self,
                 HistoricalRate.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: configuration
        )
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Item.self,
                 CashflowTransaction.self,
                 CashflowSystemCategoryOverride.self,
                 CashflowCustomCategory.self,
                 BudgetPlan.self,
                 BudgetCategoryLimit.self,
                 Cashback.self,
                 UserSubscription.self,
                 CashbackCustomCategory.self,
                 Card.self,
                 FinanceAccount.self,
                 FinanceGroup.self,
                 Credit.self,
                 Investment.self,
                 AssetCatalogItem.self,
                 AssetProviderMapping.self,
                 HistoricalRate.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }
}
