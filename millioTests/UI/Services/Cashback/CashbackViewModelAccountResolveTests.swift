//
//  CashbackViewModelAccountResolveTests.swift
//  millioTests
//
//  6b Путь B, Ф5c.4: пикер кэшбэка переведён с легаси `Card` на единый источник
//  «карты легаси ∪ core cash-like счета». Проверяем:
//   1. `cleanInvalidCardIDs` держит валидными ОБА пространства ID (легаси + core) и вычищает мусор.
//   2. Пикер резолвит смешанный набор (легаси-карта и core-счёт).
//   3. Не-денежные core-счета (вклад) не предлагаются как цель кэшбэка.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashbackViewModelAccountResolveTests {
    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        UserDefaults.standard.set("RUB", forKey: "primaryCurrencyCode")
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "CashbackViewModelAccountResolveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @discardableResult
    private func insertCoreAccount(
        name: String,
        kind: AccountKind,
        into context: ModelContext
    ) -> Account {
        let account = Account(name: name, kind: kind, currency: "RUB", createdAt: Date(timeIntervalSince1970: 1_000))
        context.insert(account)
        return account
    }

    @Test("cleanInvalidCardIDs держит и легаси-, и core-ID, вычищает несуществующий")
    func cleanKeepsBothWorldsDropsBogus() throws {
        let ctx = try makeContext()

        let card = Card(name: "Легаси-карта", cardNumber: "0000", currency: "RUB", balance: 500)
        ctx.insert(card)
        let coreAccount = insertCoreAccount(name: "Core-дебет", kind: .debitCard, into: ctx)
        let legacyID = card.cardUniqueID
        let coreID = coreAccount.id.uuidString

        let cashback = Cashback(
            name: "Такси",
            category: .other,
            percentage: 5,
            cardIDs: [legacyID, coreID, "bogus-nonexistent-id"],
            monthKey: Cashback.monthKey(for: Date())
        )
        ctx.insert(cashback)
        try ctx.save()

        // init прогоняет cleanInvalidCardIDs
        _ = CashbackViewModel(modelContext: ctx, defaults: makeIsolatedDefaults())

        #expect(cashback.cardIDs.contains(legacyID))
        #expect(cashback.cardIDs.contains(coreID))
        #expect(!cashback.cardIDs.contains("bogus-nonexistent-id"))
        #expect(cashback.cardIDs.count == 2)
    }

    @Test("Пикер резолвит смешанный набор: легаси-карта и core-счёт")
    func pickerResolvesMixedAccounts() throws {
        let ctx = try makeContext()

        let card = Card(name: "Легаси-карта", cardNumber: "1111", currency: "RUB", balance: 100)
        ctx.insert(card)
        let coreAccount = insertCoreAccount(name: "Core-дебет", kind: .debitCard, into: ctx)
        let legacyID = card.cardUniqueID
        let coreID = coreAccount.id.uuidString

        let cashback = Cashback(
            name: "Кафе",
            category: .other,
            percentage: 3,
            cardIDs: [legacyID, coreID],
            monthKey: Cashback.monthKey(for: Date())
        )
        ctx.insert(cashback)
        try ctx.save()

        let vm = CashbackViewModel(modelContext: ctx, defaults: makeIsolatedDefaults())

        #expect(vm.getAccount(byID: legacyID) != nil)
        #expect(vm.getAccount(byID: coreID) != nil)
        #expect(vm.getAccount(byID: "bogus") == nil)

        let resolved = vm.getCardsForCashback(cashback)
        #expect(resolved.count == 2)
        #expect(resolved.contains { $0.cardID == legacyID })
        #expect(resolved.contains { $0.cardID == coreID })
        #expect(vm.state.availableAccounts.contains { $0.title == "Core-дебет" })
    }

    @Test("Вклад (не денежный core-счёт) не предлагается как цель кэшбэка")
    func depositAccountNotOffered() throws {
        let ctx = try makeContext()

        let deposit = insertCoreAccount(name: "Вклад Альфа", kind: .deposit, into: ctx)
        let cashAccount = insertCoreAccount(name: "Наличные", kind: .cash, into: ctx)
        try ctx.save()

        let vm = CashbackViewModel(modelContext: ctx, defaults: makeIsolatedDefaults())

        #expect(vm.getAccount(byID: deposit.id.uuidString) == nil)
        #expect(vm.getAccount(byID: cashAccount.id.uuidString) != nil)
        #expect(!vm.state.availableAccounts.contains { $0.title == "Вклад Альфа" })
        #expect(vm.state.availableAccounts.contains { $0.title == "Наличные" })
    }
}
