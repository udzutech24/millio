import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7.4 expand-шаг №1 — populate `state.coreGroups`/`state.coreAccounts` РЯДОМ с легаси-полями.
///
/// Назначение: зафиксировать, что новые core-поля наполняются в том же lifecycle, что `state.groups`,
/// БЕЗ смены легаси-поведения (потребителей ещё нет — dead-read до пофайловой миграции). Инвариант 9
/// §2.1: fixture держит core-счета и непроконвертированный легаси-счёт ОДНОВРЕМЕННО.
///
/// Контейнер — полный миграционный (как в `FinanceViewModelCharacterizationTests`): базовый
/// `FinanceViewModelTests.schema` не содержит `Account`/`AccountGroup`.
@Suite(.serialized)
@MainActor
struct FinanceViewModelCoreEntitiesTests {

    // Держим контейнеры/VM живыми: `loadAccounts` планирует fire-and-forget Task, трогающий store
    // после возврата из теста (тот же приём, что в characterization-сьюте).
    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        let defaults = UserDefaults.standard
        defaults.set("RUB", forKey: "primaryCurrencyCode")
        defaults.set(false, forKey: "finance_savings_goal_enabled")
        defaults.set(0, forKey: "finance_savings_goal_amount")
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    private func makeViewModel(_ ctx: ModelContext) -> FinanceViewModel {
        let vm = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        Self.retained.append(vm)
        return vm
    }

    /// MIXED-STORE (инвариант 9 §2.1): core-счёт в группе + core-счёт БЕЗ группы + непроконвертированный
    /// легаси-счёт одновременно. После loadGroups: coreAccounts содержит оба core-счёта, coreGroups без
    /// Ungrouped, легаси-путь (`state.groups`/`calculateGroupTotal`) не изменился.
    @Test("expand#1 mixed-store: coreAccounts содержит core-счета, coreGroups без Ungrouped, легаси не тронуто")
    func mixedStorePopulatesCoreEntitiesBesideLegacy() async throws {
        let ctx = try makeContext()

        // Core-часть: группа "Инвест" + core-счёт в ней + core-счёт БЕЗ группы (Ungrouped-канон).
        let coreGroup = AccountGroup(name: "Инвест")
        ctx.insert(coreGroup)
        let coreService = AccountsCoreService(modelContext: ctx)
        let grouped = try coreService.createAccount(
            name: "CoreГруппа", kind: .debitCard, currency: "RUB", openingBalance: 5_000, group: coreGroup
        )
        let ungrouped = try coreService.createAccount(
            name: "CoreБезГруппы", kind: .debitCard, currency: "RUB", openingBalance: 3_000, group: nil
        )

        // Легаси-часть: непроконвертированный легаси-счёт + FinanceGroup + junction.
        let legacyGroup = FinanceGroup(name: "Легаси", colorHex: "#123456", order: 0)
        legacyGroup.displayCurrency = "RUB"
        ctx.insert(legacyGroup)
        let legacyCard = Card(name: "ЛегасиКарта", cardNumber: "9999", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        legacyCard.includeInTotal = true
        ctx.insert(legacyCard)
        let junction = FinanceAccount(accountType: .card, accountID: legacyCard.cardUniqueID)
        junction.group = legacyGroup
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        vm.handle(.loadAccounts)

        // (1) coreAccounts содержит оба core-счёта.
        let coreIDs = Set(vm.state.coreAccounts.map(\.id))
        #expect(coreIDs.contains(grouped.id))
        #expect(coreIDs.contains(ungrouped.id))

        // (2) coreGroups содержит реальную группу и НЕ содержит Ungrouped-сущности.
        #expect(vm.state.coreGroups.map(\.name).contains("Инвест"))
        #expect(!vm.state.coreGroups.map(\.name).contains(FinanceSystemGroups.ungroupedName))

        // (3) Счёт без группы виден через канон `group == nil`.
        let ungroupedCore = vm.state.coreAccounts.filter { $0.group == nil }
        #expect(ungroupedCore.map(\.id) == [ungrouped.id])

        // (4) Легаси-поля не изменились относительно characterization-ожиданий: группа видна,
        //     тотал по легаси-группе = 10000 (легаси-карта; core-счёта с именем "Легаси" нет).
        #expect(vm.state.groups.map(\.name).contains("Легаси"))
        let legacyTotal = await vm.calculateGroupTotal(group: legacyGroup, in: "RUB")
        #expect(abs(legacyTotal - 10_000) < 0.01)
    }

    /// Пустой core-стор: поля инициализированы пустыми массивами, легаси-populate не падает.
    @Test("expand#1: пустой core-стор → coreAccounts/coreGroups пусты, без краша")
    func emptyCoreStoreYieldsEmptyArrays() throws {
        let ctx = try makeContext()
        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(vm.state.coreAccounts.isEmpty)
        #expect(vm.state.coreGroups.isEmpty)
    }

    /// Архивный core-счёт не попадает в coreAccounts (participates-семантика, как у `newCoreAccounts`).
    @Test("expand#1: архивный core-счёт исключён из coreAccounts")
    func archivedCoreAccountExcluded() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let active = try coreService.createAccount(name: "Актив", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: nil)
        let archived = try coreService.createAccount(name: "Архив", kind: .debitCard, currency: "RUB", openingBalance: 2_000, group: nil)
        archived.archivedAt = Date().addingTimeInterval(-86_400) // архивирован вчера → не participates
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        let ids = Set(vm.state.coreAccounts.map(\.id))
        #expect(ids.contains(active.id))
        #expect(!ids.contains(archived.id))
    }
}
