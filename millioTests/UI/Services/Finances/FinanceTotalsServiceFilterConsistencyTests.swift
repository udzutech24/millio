//
//  FinanceTotalsServiceFilterConsistencyTests.swift
//  millioTests
//
//  6b Фаза 2 (single-world): агрегат «Общий баланс» считается ТОЛЬКО по ядру
//  (`AccountsTotalsService.totalAt`). Регрессионный тест равенства путей тотала —
//  Дашборд/«Счета» (`FinanceTotalsService.calculateTotalsSnapshot`) == заголовок «Динамика»
//  (`FinanceDynamicsViewModel.state.currentBalance`) — на одном наборе core-счетов.
//  Закрывает R1 аудита 2026-07-02 (три пути тотала → один).
//
//  До Фазы 2 этот файл сравнивал легаси-агрегаты (legacy-фильтры includeInTotal/archivedAt
//  прямо в `calculateTotalsSnapshot`). Легаси-цикл в агрегате снят: мигрированная легаси
//  скрыта (`archivedAt`) и вносит 0, что и проверяет сценарий смешанных данных ниже.
//  Легаси-фильтр включения/знака теперь живёт только в per-group display
//  (`FinanceTotalsService.getAccountAmount`, инлайн бывшего `AccountTotalPolicy`).
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct FinanceTotalsServiceFilterConsistencyTests {

    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        UserDefaults.standard.set("RUB", forKey: "primaryCurrencyCode")
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    /// Заголовок «Динамика» на дату «сегодня» (без скоуп-фильтров) сходится с агрегатом Дашборда.
    private func dynamicsCurrentBalance(
        financeViewModel: FinanceViewModel,
        modelContext: ModelContext
    ) async -> Double {
        let dynamics = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: financeViewModel.currencyService
        )
        dynamics.handle(.loadData)
        dynamics.state.period = .week
        dynamics.state.dynamicsMode = .aggregated
        // Пинним целевую дату «сегодня», чтобы сравнивать с агрегатом Дашборда (`totalAt(now)`),
        // а не с концом произвольно посчитанного периода.
        dynamics.state.selectedDate = Date()
        await dynamics.updateCurrentBalanceAndDelta()
        return dynamics.state.currentBalance
    }

    // AC1: три пути тотала сходятся на наборе core-счетов.
    @Test("AC1: тотал Дашборда/«Счетов» == тотал «Динамики» на наборе core-счетов")
    func aggregateTotalMatchesAcrossDashboardAndDynamics() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        let currency = financeViewModel.state.displayCurrency

        _ = try service.createAccount(name: "Дебетовая", kind: .debitCard, currency: currency, openingBalance: 10_000)
        _ = try service.createAccount(name: "Наличные", kind: .cash, currency: currency, openingBalance: 2_500)
        _ = try service.createAccount(name: "Счёт в банке", kind: .bankAccount, currency: currency, openingBalance: 5_000)

        financeViewModel.handle(.loadAccounts)
        financeViewModel.handle(.loadGroups)

        let dashboard = await financeViewModel.totalsService.calculateTotalsSnapshot().totalAmount
        let dynamics = await dynamicsCurrentBalance(financeViewModel: financeViewModel, modelContext: ctx)

        let expected = 17_500.0
        #expect(abs(dashboard - expected) < 0.01, "Дашборд/«Счета»: агрегат по ядру должен быть 17 500")
        #expect(abs(dynamics - expected) < 0.01, "«Динамика»: заголовок должен сойтись с ядром")
        #expect(abs(dashboard - dynamics) < 0.01, "Три пути тотала → один: Дашборд == Динамика")
    }

    // AC2: смешанные данные (мигрированная = скрытая легаси + нативные core) → тотал = сумма core,
    // скрытая легаси вносит 0.
    @Test("AC2: скрытая (архивная) легаси не вносит вклад — тотал = сумме core-счетов")
    func hiddenLegacyContributesNothing() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        let currency = financeViewModel.state.displayCurrency

        // Нативные core-счета.
        _ = try service.createAccount(name: "Дебетовая", kind: .debitCard, currency: currency, openingBalance: 8_000)
        _ = try service.createAccount(name: "Наличные", kind: .cash, currency: currency, openingBalance: 1_000)
        let coreSum = 9_000.0

        // Скрытая (мигрированная) легаси-карта: archivedAt в прошлом + junction в группе.
        // Заметное значение (99 999) — если бы вклад «протёк», тест упал бы громко.
        let group = FinanceGroup(name: "Группа", colorHex: "#00AAFF")
        group.displayCurrency = currency
        ctx.insert(group)
        let hiddenCard = Card(name: "Мигрированная", cardNumber: "0000", cardType: .debit, currency: currency, balance: 99_999)
        hiddenCard.archivedAt = Date().addingTimeInterval(-86_400)
        ctx.insert(hiddenCard)
        let junction = FinanceAccount(accountType: .card, accountID: hiddenCard.cardUniqueID)
        junction.group = group
        ctx.insert(junction)
        try ctx.save()

        financeViewModel.handle(.loadAccounts)
        financeViewModel.handle(.loadGroups)

        let dashboard = await financeViewModel.totalsService.calculateTotalsSnapshot().totalAmount
        let dynamics = await dynamicsCurrentBalance(financeViewModel: financeViewModel, modelContext: ctx)

        #expect(abs(dashboard - coreSum) < 0.01, "Дашборд: скрытая легаси не должна входить в агрегат")
        #expect(abs(dynamics - coreSum) < 0.01, "Динамика: скрытая легаси не должна входить в заголовок")
        #expect(abs(dashboard - dynamics) < 0.01, "Дашборд == Динамика на смешанных данных")
    }

    // AC3 (Ф5c.7.0): смена группы счёта через `AccountsCoreService.updateAccount` не ломает инвариант
    // Total(Groups)==Total(Accounts). Снапшот-кэш ключён по счёту (не по группе), групповой тотал
    // считается на чтении из живого `account.group` — перенос между группами меняет только к какой
    // группе относится счёт, но не grand total и не сходимость Дашборд/Динамика (см. докстринг
    // `updateAccount`: инвалидация кэша при смене группы была бы no-op).
    @Test("AC3: смена группы через updateAccount — тотал и сходимость Дашборд==Динамика держатся")
    func groupChangeViaUpdateAccountKeepsTotalsConsistent() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        let currency = financeViewModel.state.displayCurrency

        let groupA = AccountGroup(name: "Группа A")
        let groupB = AccountGroup(name: "Группа B")
        ctx.insert(groupA)
        ctx.insert(groupB)
        let card = try service.createAccount(name: "Дебетовая", kind: .debitCard, currency: currency, openingBalance: 10_000, group: groupA)
        _ = try service.createAccount(name: "Наличные", kind: .cash, currency: currency, openingBalance: 2_500, group: groupB)

        financeViewModel.handle(.loadAccounts)
        financeViewModel.handle(.loadGroups)
        let expected = 12_500.0
        let dashboardBefore = await financeViewModel.totalsService.calculateTotalsSnapshot().totalAmount
        let dynamicsBefore = await dynamicsCurrentBalance(financeViewModel: financeViewModel, modelContext: ctx)
        #expect(abs(dashboardBefore - expected) < 0.01, "Стартовый тотал по ядру = 12 500")
        #expect(abs(dashboardBefore - dynamicsBefore) < 0.01, "Инвариант держится до смены группы")

        // Переносим счёт из группы A в группу B через updateAccount.
        try service.updateAccount(card, name: card.name, group: groupB)
        financeViewModel.handle(.loadAccounts)
        financeViewModel.handle(.loadGroups)

        let dashboardAfter = await financeViewModel.totalsService.calculateTotalsSnapshot().totalAmount
        let dynamicsAfter = await dynamicsCurrentBalance(financeViewModel: financeViewModel, modelContext: ctx)
        #expect(abs(dashboardAfter - expected) < 0.01, "Смена группы не меняет grand total")
        #expect(abs(dashboardAfter - dynamicsAfter) < 0.01, "Инвариант Дашборд==Динамика держится после смены группы")
        #expect(card.group?.name == "Группа B", "Счёт действительно переехал в группу B")
    }
}
