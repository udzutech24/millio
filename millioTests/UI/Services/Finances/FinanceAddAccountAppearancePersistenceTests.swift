import Foundation
import SwiftData
import Testing
@testable import millio

/// Баг 2: тумблеры «избранное»/иконка/цвет были в формах, но `FinanceProductCreationInput` их
/// не несло — оформление молча терялось при создании ЛЮБОГО типа счёта.
///
/// Тест проверяет `AccountAppearancePersister` — единственное новое место, куда стекаются все
/// 6 точек вызова из `FinanceAddAccountView+CoreCreate.swift` (карта/счёт, вклад, кредит, долг,
/// рыночный актив, ручной актив включая недвижимость). Сам `create*OnNewCore` вызвать напрямую
/// нельзя: это подтверждено экспериментом в этой же сессии — `@State`, заданный вне живого рендера
/// SwiftUI (как в unit-тесте), не читается обратно (`location` остаётся `nil`, геттер всегда
/// возвращает значение по умолчанию из декларации) — это верно для ЛЮБОГО `@State`, не только для
/// опциональных/кортежных типов, и для этого тулчейна нет обходного пути без реального рендера
/// (backing storage `_foo` помечен `private` самим компилятором). Поэтому счёт создаётся РЕАЛЬНЫМ
/// `AccountProductFactory`/`FinanceProductCreationCommandResolver` (как и делает `CoreCreate.swift`),
/// а оформление — РЕАЛЬНЫМ `AccountAppearancePersister`, который CoreCreate.swift вызывает как есть.
@Suite(.serialized)
@MainActor
struct FinanceAddAccountAppearancePersistenceTests {

    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    // MARK: - Ядро: no-op при пустом наборе, upsert при непустом

    @Test("Все три пустые/false — строка в сторе не создаётся (не плодим мусор)")
    func emptyDraftIsNoOp() throws {
        let ctx = try makeContext()
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: accountID, isFavorite: false, iconName: nil, tintHex: nil)

        #expect(try AccountAppearanceStore(context: ctx).appearance(for: accountID) == nil)
    }

    @Test("Только isFavorite=true — строка создаётся, а не остаётся молчаливо пустой (сам Баг 2)")
    func favoriteOnlyPersists() throws {
        let ctx = try makeContext()
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: accountID, isFavorite: true, iconName: nil, tintHex: nil)

        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: accountID))
        #expect(appearance.isFavorite == true)
        #expect(appearance.iconName == nil)
        #expect(appearance.tintHex == nil)
    }

    @Test("Только иконка (без избранного) — строка создаётся")
    func iconOnlyPersists() throws {
        let ctx = try makeContext()
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: accountID, isFavorite: false, iconName: "star.fill", tintHex: nil)

        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: accountID))
        #expect(appearance.isFavorite == false)
        #expect(appearance.iconName == "star.fill")
    }

    @Test("Избранное+иконка+цвет — все три поля доходят до стора одним upsert'ом")
    func fullDraftPersistsAllFields() throws {
        let ctx = try makeContext()
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: accountID, isFavorite: true, iconName: "banknote", tintHex: "#FF00FF")

        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: accountID))
        #expect(appearance.isFavorite == true)
        #expect(appearance.iconName == "banknote")
        #expect(appearance.tintHex == "#FF00FF")
    }

    // MARK: - Путь создания: те же вызовы `resolve`+`create`, что делает каждая из 6 точек в CoreCreate.swift,
    // плюс реальный `AccountAppearancePersister` — доказывает, что оформление доживает до реального
    // счёта, созданного реальной фабрикой, а не только до изолированного UUID.

    private func createdAccountID(named name: String, in context: ModelContext) throws -> UUID {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.name == name })
        return try #require(try context.fetch(descriptor).first).id
    }

    @Test("Путь создания — карта: избранное+иконка доходят до стора после factory.create")
    func moneyAccountCreationPathPersistsAppearance() throws {
        let ctx = try makeContext()
        let factory = AccountProductFactory(modelContext: ctx)
        let command = try FinanceProductCreationCommandResolver.resolve(.init(
            option: .card, name: "Дебетовая карта", currency: "RUB", amount: 1_000, cardType: .debit
        ))
        _ = try factory.create(command)
        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: command.accountID, isFavorite: true, iconName: "star.fill", tintHex: nil)

        let id = try createdAccountID(named: "Дебетовая карта", in: ctx)
        #expect(id == command.accountID)
        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: id))
        #expect(appearance.isFavorite == true)
        #expect(appearance.iconName == "star.fill")
    }

    @Test("Путь создания — кредит: избранное доходит до стора после factory.create с loanMeta")
    func loanAccountCreationPathPersistsFavorite() throws {
        let ctx = try makeContext()
        let factory = AccountProductFactory(modelContext: ctx)
        let meta = AccountsCoreAdditionBridge.loanMeta(principal: 1_000_000, monthlyPayment: nil, paymentDay: nil, termEnd: Date())
        let command = try FinanceProductCreationCommandResolver.resolve(.init(
            option: .credit, name: "Ипотека", currency: "RUB", amount: 1_000_000, loanMeta: meta
        ))
        _ = try factory.create(command)
        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: command.accountID, isFavorite: true, iconName: nil, tintHex: nil)

        let id = try createdAccountID(named: "Ипотека", in: ctx)
        #expect(try AccountAppearanceStore(context: ctx).isFavorite(accountID: id) == true)
    }

    @Test("Путь создания — долг: избранное доходит до стора после factory.create с debtDirection (риск: легко забыть эту ветку)")
    func debtAccountCreationPathPersistsFavorite() throws {
        let ctx = try makeContext()
        let factory = AccountProductFactory(modelContext: ctx)
        let command = try FinanceProductCreationCommandResolver.resolve(.init(
            option: .debt, name: "Долг Игоря", currency: "RUB", amount: 30_000, debtDirection: .owedToMe
        ))
        _ = try factory.create(command)
        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: command.accountID, isFavorite: true, iconName: nil, tintHex: nil)

        let id = try createdAccountID(named: "Долг Игоря", in: ctx)
        #expect(try AccountAppearanceStore(context: ctx).isFavorite(accountID: id) == true)
    }

    @Test("Путь создания — ручной актив (недвижимость): избранное доходит до стора (риск: легко забыть house-ветку)")
    func manualAssetHouseCreationPathPersistsFavorite() throws {
        let ctx = try makeContext()
        let factory = AccountProductFactory(modelContext: ctx)
        let command = try FinanceProductCreationCommandResolver.resolve(.init(
            option: .house, name: "Квартира", currency: "RUB", amount: 5_000_000
        ))
        _ = try factory.create(command, graphEnricher: { graph, transactionContext in
            transactionContext.insert(RealEstateProfile(accountID: graph.account.id, propertyType: .apartment))
        })
        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: command.accountID, isFavorite: true, iconName: nil, tintHex: nil)

        let id = try createdAccountID(named: "Квартира", in: ctx)
        #expect(try AccountAppearanceStore(context: ctx).isFavorite(accountID: id) == true)
    }
}
