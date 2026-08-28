import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("SchemaMigration")
struct SchemaMigrationTests {

    // MARK: - Helpers

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("migration_test_\(UUID().uuidString).store")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }

    // MARK: - Tests

    /// Данные из V1-стора (без UserSubscription) должны сохраниться после открытия через AppMigrationPlan (V2)
    @Test @MainActor
    func existingDataSurvivesV1toV2Migration() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        // 1. Создаём V1-стор и вносим данные
        let v1Schema = Schema(AppSchemaV1.models)
        let v1Config = ModelConfiguration(
            "v1_\(UUID().uuidString)",
            schema: v1Schema,
            url: url,
            cloudKitDatabase: .none
        )
        let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Config])
        let v1Ctx = v1Container.mainContext
        let item = Item(timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        v1Ctx.insert(item)
        try v1Ctx.save()

        // 2. Открываем тот же стор через AppMigrationPlan (V2) — lightweight migration
        let v2Config = ModelConfiguration(
            "v1_\(UUID().uuidString)",
            url: url,
            cloudKitDatabase: .none
        )
        let v2Container = try AppMigrationPlan.makeContainer(configuration: v2Config)

        // 3. Данные должны сохраниться
        let items = try v2Container.mainContext.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        #expect(items.first?.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// После миграции V1→V2 таблица UserSubscription должна быть доступна без ошибок
    @Test @MainActor
    func userSubscriptionTableAccessibleAfterMigration() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        // Создаём V1-стор (без UserSubscription)
        let v1Schema = Schema(AppSchemaV1.models)
        let v1Config = ModelConfiguration(
            "v1sub_\(UUID().uuidString)",
            schema: v1Schema,
            url: url,
            cloudKitDatabase: .none
        )
        _ = try ModelContainer(for: v1Schema, configurations: [v1Config])

        // Открываем через migration plan — должен создать таблицу UserSubscription
        let v2Config = ModelConfiguration(
            "v1sub_\(UUID().uuidString)",
            url: url,
            cloudKitDatabase: .none
        )
        let v2Container = try AppMigrationPlan.makeContainer(configuration: v2Config)

        // Fetch UserSubscription не должен бросать — таблица создана миграцией
        let subs = try v2Container.mainContext.fetch(FetchDescriptor<UserSubscription>())
        #expect(subs.isEmpty)
    }

    /// V2-стор (уже актуальная схема) открывается через AppMigrationPlan без потери данных
    @Test @MainActor
    func currentSchemaOpenedWithMigrationPlanPreservesData() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        // Создаём стор сразу через migration plan
        let config1 = ModelConfiguration(
            "v2a_\(UUID().uuidString)",
            url: url,
            cloudKitDatabase: .none
        )
        let container1 = try AppMigrationPlan.makeContainer(configuration: config1)
        let ctx1 = container1.mainContext
        let item = Item(timestamp: Date(timeIntervalSince1970: 999_999))
        ctx1.insert(item)
        try ctx1.save()

        // Открываем повторно — данные должны быть на месте
        let config2 = ModelConfiguration(
            "v2b_\(UUID().uuidString)",
            url: url,
            cloudKitDatabase: .none
        )
        let container2 = try AppMigrationPlan.makeContainer(configuration: config2)
        let items = try container2.mainContext.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
    }


    @Test("V7 account history survives additive migration to the current schema") @MainActor
    func v7AccountHistorySurvivesV8Migration() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }
        let v7Schema = Schema(AppSchemaV7.models, version: AppSchemaV7.versionIdentifier)
        let v7Config = ModelConfiguration("v7_fixture", schema: v7Schema, url: url, cloudKitDatabase: .none)
        let v7Container = try ModelContainer(for: v7Schema, configurations: [v7Config])
        // Стор пишется ЗАМОРОЖЕННЫМИ декларациями V7. С заморозкой AccountsCore-графа
        // `AppSchemaV7.models` перестала содержать продакшн-`Account`, и вставка продакшн-типа
        // в такой контейнер роняет тест-хост (signal trap) вместо честного падения проверки.
        let account = AppSchemaV7.Account(
            name: "Apartment",
            kindRaw: AccountKind.manualAsset.rawValue
        )
        account.productTypeRaw = AccountProductType.realEstate.rawValue
        account.manualAssetMeta = ManualAssetMeta(revalReminderMonths: 12, depreciationRatePerYear: nil, linkedLoanID: nil)
        let eventDate = Date(timeIntervalSince1970: 1_700_000_000)
        let event = AppSchemaV7.AccountEvent(
            account: account,
            date: eventDate,
            dayKey: AccountEvent.dayKey(for: eventDate),
            typeRaw: AccountEventType.openingBalance.rawValue
        )
        event.amount = 54_000_000
        v7Container.mainContext.insert(account)
        v7Container.mainContext.insert(event)
        try v7Container.mainContext.save()

        let migrated = try AppMigrationPlan.makeContainer(configuration: ModelConfiguration("v8_fixture", url: url, cloudKitDatabase: .none))
        let restored = try #require(migrated.mainContext.fetch(FetchDescriptor<Account>()).first)
        #expect(restored.name == "Apartment")
        #expect(restored.events?.first?.amount == 54_000_000)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<AccountAttachment>()).isEmpty)
    }

    /// Главный риск Ф0 (V11): реальный V10-стор обязан открыться текущей схемой без
    /// `NSCocoaErrorDomain 134504` — иначе срабатывает no-plan fallback и данные теряются.
    @Test("V10 store opens under the current schema and keeps its rows") @MainActor
    func v10StoreMigratesToV11WithoutDataLoss() throws {
        let url = tempStoreURL()
        defer { cleanup(url) }

        let v10Schema = Schema(AppSchemaV10.models, version: AppSchemaV10.versionIdentifier)
        let v10Config = ModelConfiguration("v10_fixture", schema: v10Schema, url: url, cloudKitDatabase: .none)
        let v10Container = try ModelContainer(for: v10Schema, configurations: [v10Config])
        let account = Account(name: "Счёт V10", kind: .cash, currency: "RUB")
        v10Container.mainContext.insert(account)
        try v10Container.mainContext.save()
        let accountID = account.id

        let migrated = try AppMigrationPlan.makeContainer(
            configuration: ModelConfiguration("v11_fixture", url: url, cloudKitDatabase: .none)
        )
        let restored = try #require(migrated.mainContext.fetch(FetchDescriptor<Account>()).first)
        #expect(restored.id == accountID)
        #expect(restored.name == "Счёт V10")
        // Новая таблица есть и пуста — миграция аддитивная, ничего не досочинила.
        #expect(try migrated.mainContext.fetch(FetchDescriptor<AccountAppearance>()).isEmpty)
    }
}
