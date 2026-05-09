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
}
