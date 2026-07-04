import SwiftData

// MARK: - V1 (исходная схема без UserSubscription и без Cashback)
// Не изменять: реальные сторы на устройствах пользователей были записаны с этой схемой.

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        Item.self,
        CashflowTransaction.self,
        CashflowSystemCategoryOverride.self,
        CashflowCustomCategory.self,
        BudgetPlan.self,
        BudgetCategoryLimit.self,
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

// MARK: - V2 (добавлена UserSubscription; Cashback отсутствовал — историческая ошибка)
// Не изменять: реальные сторы на устройствах пользователей были записаны с этой схемой.

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [
        Item.self,
        CashflowTransaction.self,
        CashflowSystemCategoryOverride.self,
        CashflowCustomCategory.self,
        BudgetPlan.self,
        BudgetCategoryLimit.self,
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

// MARK: - V3 (Cashback добавлен в схему явно)
// Исправляет историческую ошибку: Cashback был в ModelTypeRegistry, но не в V1/V2.
// Пользователи со старыми V2-сторами мигрируют сюда lightweight-миграцией (добавляется таблица).

enum AppSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
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

// MARK: - V4 (добавлено ядро счетов event-sourcing: Account/AccountEvent/AccountGroup/AccountDailySnapshot)
// Новые таблицы, старые (Card/Credit/Investment/FinanceAccount) НЕ трогаются — оба ядра
// сосуществуют на время миграции UI (см. specs/2026-07-04-accounts-core.md, Scope).

enum AppSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] = AppSchemaV3.models + [
        Account.self,
        AccountEvent.self,
        AccountGroup.self,
        AccountDailySnapshot.self,
    ]
}

// MARK: - Текущая схема (единственный источник правды)

// При добавлении нового @Model:
//   1. Создать AppSchemaV{N+1} с новым типом в models
//   2. Добавить lightweight stage V{N}→V{N+1} в AppMigrationPlan.stages
//   3. Обновить этот typealias на AppSchemaV{N+1}
//   4. Запустить SchemaConsistencyTests — должны быть зелёными
typealias AppSchemaCurrent = AppSchemaV4

// MARK: - План миграции

// Существующие сторы без версионирования трактуются как V1 и безопасно мигрируют.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [
        AppSchemaV1.self,
        AppSchemaV2.self,
        AppSchemaV3.self,
        AppSchemaV4.self,
    ]

    static var stages: [MigrationStage] = [
        .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self),
        .lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self),
        .lightweight(fromVersion: AppSchemaV3.self, toVersion: AppSchemaV4.self),
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
                 Account.self,
                 AccountEvent.self,
                 AccountGroup.self,
                 AccountDailySnapshot.self,
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
                 Account.self,
                 AccountEvent.self,
                 AccountGroup.self,
                 AccountDailySnapshot.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }
}
