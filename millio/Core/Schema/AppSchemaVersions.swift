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
// Не изменять: HistoricalAssetPrice был дописан сюда задним числом (Фаза 4, S9/AC10) уже
// после того как на dev-устройствах существовали сторы под идентификатором 4.0.0 без этой
// таблицы — SwiftData видел расхождение факт/декларация и падал с "Cannot use staged
// migration with an unknown model version" → no-plan fallback стирал данные (Находка 2,
// plans/2026-07-04__accounts-core-rebuild-plan.md). V4 зафиксирован как было изначально,
// HistoricalAssetPrice переехал в честную V5 ниже. Впредь: новые @Model — только в новую
// версию, никогда не редактировать models уже выпущенной (или уже физически существующей
// на дисках) версии.

enum AppSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] = AppSchemaV3.models
        + AppSchemaV5.frozenAccountsCoreModels
}

// MARK: - V5 (HistoricalAssetPrice — append-only кэш рыночных цен, Фаза 4 S9/AC10)
// Честная версия для типа, ошибочно дописанного в V4 задним числом (см. комментарий V4 выше).
// V4 никогда не публиковался (ветка feature/accounts-core не смержена в develop) — риск
// расхождения ограничен dev/sim-сторами разработчика.

enum AppSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] = AppSchemaV4.models + [
        HistoricalAssetPrice.self,
    ]
}

// MARK: - V6 (persisted product identity, Accounts history Phase 1P)

// V4/V5 используют frozen declarations из `AppSchemaV5AccountsCoreModels.swift`. Ссылаться из
// исторической версии на mutable top-level `Account` нельзя: добавление даже optional-свойства
// меняет checksum старой версии, и реальный V5 store падает с NSCocoaErrorDomain 134504
// "Cannot use staged migration with an unknown model version".
//
// V6 впервые владеет optional-колонками `productTypeRaw`/`productMigrationReason`.
// После acceptance его AccountsCore graph заморожен в `AppSchemaV6AccountsCoreModels.swift`:
// иначе V7 revision columns изменят checksum исторической V6 задним числом.
enum AppSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] = AppSchemaV3.models
        + AppSchemaV6.frozenAccountsCoreModels
}

// MARK: - V7 (immutable local historical close repository, Accounts history Phase 3V)

// V7 switches the frozen V6 AccountsCore declarations to the current production graph. This owns
// only additive optional valuation-revision Account columns plus the new close table. The staged
// transition never deletes or rewrites Account/Event/Snapshot source rows.
enum AppSchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] = AppSchemaV3.models + [
        Account.self,
        AccountEvent.self,
        AccountGroup.self,
        AccountDailySnapshot.self,
        HistoricalAssetPrice.self,
        HistoricalPortfolioValuation.self,
    ]
}

// MARK: - V8 (real-estate profile and privacy-safe photo attachments)

/// Additive tables only: V7 model declarations remain byte-for-byte unchanged so existing stores
/// retain a valid checksum and migrate without rewriting financial history.
enum AppSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] = AppSchemaV7.models + [
        RealEstateProfile.self,
        AccountAttachment.self,
    ]
}

// MARK: - Текущая схема (единственный источник правды)

// При добавлении нового @Model:
//   1. Создать AppSchemaV{N+1} с новым типом в models
//   2. Добавить lightweight stage V{N}→V{N+1} в AppMigrationPlan.stages
//   3. Обновить этот typealias на AppSchemaV{N+1}
//   4. Запустить SchemaConsistencyTests — должны быть зелёными
// ВАЖНО: models уже выпущенной версии (или версии, под идентификатором которой уже
// существуют сторы на дисках — dev/sim в том числе) — не редактировать задним числом.
// Это ломает staged migration (см. комментарий V4 выше, Находка 2).
typealias AppSchemaCurrent = AppSchemaV8

// MARK: - План миграции

// Существующие сторы без версионирования трактуются как V1 и безопасно мигрируют.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [
        AppSchemaV1.self,
        AppSchemaV2.self,
        AppSchemaV3.self,
        AppSchemaV4.self,
        AppSchemaV5.self,
        AppSchemaV6.self,
        AppSchemaV7.self,
        AppSchemaV8.self,
    ]

    static var stages: [MigrationStage] = [
        .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self),
        .lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self),
        .lightweight(fromVersion: AppSchemaV3.self, toVersion: AppSchemaV4.self),
        .lightweight(fromVersion: AppSchemaV4.self, toVersion: AppSchemaV5.self),
        .lightweight(fromVersion: AppSchemaV5.self, toVersion: AppSchemaV6.self),
        .lightweight(fromVersion: AppSchemaV6.self, toVersion: AppSchemaV7.self),
        .lightweight(fromVersion: AppSchemaV7.self, toVersion: AppSchemaV8.self),
    ]
}

// MARK: - Фабрика контейнеров

// Все вызовы ModelContainer с планом миграции должны идти через эти методы. Фабрика
// сама подставляет current versioned schema: schema-less `ModelConfiguration` иначе
// создаёт current layout с on-disk version identifier `1.0.0`, ломая следующую staged migration.
extension AppMigrationPlan {
    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        let schema = AppSchema.create()
        var resolvedConfiguration = configuration
        resolvedConfiguration.schema = schema
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [resolvedConfiguration]
        )
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainer(
            configuration: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
    }
}
