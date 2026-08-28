import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф0 V11: контракт `AccountAppearanceStore`.
///
/// Ключевой риск — два мира ID в одном поле (`Account.id` vs `Card.cardUniqueID`), тот же класс
/// багов, что дал инцидент 27.08 с сохранением на core-счёте.
@Suite(.serialized)
@MainActor
struct AccountAppearanceStoreTests {

    /// Контейнер держим в локальной переменной теста: если его не удержать, он умирает сразу
    /// после создания и запрос к `mainContext` роняет тест-хост (signal trap, а не падение assert).

    @Test("Пустой стор: словарь пуст, избранных нет, чтение по любому ID не падает")
    func emptyStore() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = AccountAppearanceStore(context: context)
        #expect(try store.loadAll().isEmpty)
        #expect(try store.favoriteAccountIDs().isEmpty)
        #expect(try store.isFavorite(accountID: UUID()) == false)
    }

    @Test("upsert идемпотентен: два вызова на один accountID дают одну строку")
    func upsertIsIdempotent() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = AccountAppearanceStore(context: context)
        let accountID = UUID()

        try store.upsert(accountID: accountID) { $0.tintHex = "#112233" }
        try store.upsert(accountID: accountID) { $0.tintHex = "#445566"; $0.isFavorite = true }
        try context.save()

        let rows = try context.fetch(FetchDescriptor<AccountAppearance>())
        #expect(rows.count == 1)
        #expect(rows.first?.tintHex == "#445566")
        #expect(rows.first?.isFavorite == true)
    }

    @Test("accountID адресует оба мира: core Account.id и легаси Card.cardUniqueID")
    func keyWorksForBothAccountWorlds() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Core-счёт", kind: .cash)
        let card = Card(name: "Легаси-карта", cardNumber: "1111")
        context.insert(account)
        context.insert(card)
        try context.save()

        let cardUUID = try #require(UUID(uuidString: card.cardUniqueID))
        let store = AccountAppearanceStore(context: context)
        try store.upsert(accountID: account.id) { $0.isFavorite = true }
        try store.upsert(accountID: cardUUID) { $0.tintHex = "#ABCDEF" }
        try context.save()

        let map = try store.loadAll()
        #expect(map.count == 2)
        #expect(map[account.id]?.isFavorite == true)
        #expect(map[cardUUID]?.tintHex == "#ABCDEF")
        // Ключи разных миров не должны схлопываться друг с другом.
        #expect(account.id != cardUUID)
    }

    @Test("toggleFavorite: включает, выключает и не оставляет пустую строку после выключения")
    func toggleFavoriteRoundTrip() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = AccountAppearanceStore(context: context)
        let accountID = UUID()

        #expect(try store.toggleFavorite(accountID: accountID) == true)
        try context.save()
        #expect(try store.favoriteAccountIDs() == [accountID])

        #expect(try store.toggleFavorite(accountID: accountID) == false)
        try context.save()
        #expect(try store.favoriteAccountIDs().isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountAppearance>()).isEmpty)
    }

    @Test("toggleFavorite сохраняет строку, если у счёта есть оформление")
    func toggleFavoriteKeepsDecoratedRow() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let store = AccountAppearanceStore(context: context)
        let accountID = UUID()
        try store.upsert(accountID: accountID) { $0.tintHex = "#00FF00" }

        _ = try store.toggleFavorite(accountID: accountID)
        _ = try store.toggleFavorite(accountID: accountID)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<AccountAppearance>())
        #expect(rows.count == 1)
        #expect(rows.first?.tintHex == "#00FF00")
        #expect(rows.first?.isFavorite == false)
    }

    /// `@Attribute(.unique)` в проекте запрещён, поэтому restore/merge может внести второй ряд
    /// на тот же счёт. Победитель обязан быть детерминированным, иначе правка «не применяется».
    @Test("Дубли по accountID схлопываются: побеждает свежий updatedAt, upsert чистит остальные")
    func duplicatesCollapseDeterministically() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let accountID = UUID()
        let old = AccountAppearance(
            accountID: accountID, tintHex: "#000000", updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let fresh = AccountAppearance(
            accountID: accountID, tintHex: "#FFFFFF", updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        context.insert(old)
        context.insert(fresh)
        try context.save()

        let store = AccountAppearanceStore(context: context)
        #expect(try store.loadAll()[accountID]?.tintHex == "#FFFFFF")

        try store.upsert(accountID: accountID) { $0.isFavorite = true }
        try context.save()
        let rows = try context.fetch(FetchDescriptor<AccountAppearance>())
        #expect(rows.count == 1)
        #expect(rows.first?.tintHex == "#FFFFFF")
    }
}
