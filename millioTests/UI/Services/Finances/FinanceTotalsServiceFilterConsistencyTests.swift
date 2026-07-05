//
//  FinanceTotalsServiceFilterConsistencyTests.swift
//  millioTests
//
//  Регрессионный тест консистентности тоталов — plans/2026-07-05__unified-totals.md.
//  На одном и том же наборе legacy-счетов (обычный / includeInTotal=false у карты /
//  архивная карта / архивный кредит / кредитная карта с долгом / мультивалюта)
//  заголовок «Динамика» (FinanceDynamicsViewModel.state.currentBalance) и тотал
//  Дашборда/«Счетов» (FinanceTotalsService.calculateTotalsSnapshot) обязаны давать
//  ОДИНАКОВОЕ число. До фикса TotalsService не фильтровал archivedAt вообще (для всех
//  трёх типов) — этот тест ловит регрессию, если фильтры снова разойдутся.
//
//  ВАЖНО: сценарий "кредит с includeInTotal=false" сюда сознательно НЕ включён —
//  FinanceAccountService.normalizeCreditsIncludeInTotal принудительно сбрасывает этот
//  флаг в true при каждой loadAccounts(), поэтому такое состояние недостижимо в проде
//  (проверено экспериментально при написании этого теста). Это отдельный,
//  не связанный с текущим фиксом баг — см. Фазу 4 в plans/2026-07-05__unified-totals.md.
//  Чистая логика AccountTotalPolicy для credit.includeInTotal=false покрыта отдельно
//  в AccountTotalPolicyTests (там нормализатор не участвует).
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct FinanceTotalsServiceFilterConsistencyTests {
    private static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        HistoricalRate.self
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func createTestModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }

    @Test("Динамика и TotalsService дают одинаковый тотал на смешанном наборе счетов")
    func dynamicsAndTotalsServiceAgreeOnMixedAccounts() async throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Тестовая группа", colorHex: "#FF0000")
        group.displayCurrency = "RUB"
        modelContext.insert(group)

        // 1. Обычная дебетовая карта RUB — учитывается везде.
        let cardActive = Card(
            name: "Активная карта",
            cardNumber: "0001",
            cardType: .debit,
            currency: "RUB",
            balance: 10_000.0
        )
        modelContext.insert(cardActive)

        // 2. Карта, исключённая пользователем из тотала — НЕ должна учитываться нигде.
        let cardExcluded = Card(
            name: "Исключённая карта",
            cardNumber: "0002",
            cardType: .debit,
            currency: "RUB",
            balance: 5_000.0,
            includeInTotal: false
        )
        modelContext.insert(cardExcluded)

        // 3. Архивная карта (была активна, потом архивирована вчера) — НЕ должна учитываться
        //    в "сегодняшнем" тотале ни на одном экране (ключевой регресс-кейс: раньше
        //    TotalsService не проверял archivedAt вообще).
        let cardArchived = Card(
            name: "Архивная карта",
            cardNumber: "0003",
            cardType: .debit,
            currency: "RUB",
            balance: 7_000.0
        )
        cardArchived.archivedAt = Date().addingTimeInterval(-86_400)
        modelContext.insert(cardArchived)

        // 4. Кредитная карта с долгом: лимит 50000, остаток 20000 → долг 30000 (liability).
        let creditCard = Card(
            name: "Кредитка",
            cardNumber: "0004",
            cardType: .credit,
            currency: "RUB",
            balance: 20_000.0,
            creditLimit: 50_000.0
        )
        modelContext.insert(creditCard)

        // 5. Обычный кредит — liability, учитывается везде.
        let creditActive = Credit(
            name: "Кредит",
            amount: 40_000.0,
            interestRate: 0.0,
            monthlyPayment: 1_000.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB"
        )
        creditActive.remainingAmount = 40_000.0
        creditActive.updatedAt = Date()
        modelContext.insert(creditActive)

        // 6. Архивный кредит — ключевой регресс-кейс: TotalsService раньше не фильтровал
        //    archivedAt для кредитов вообще, поэтому погашенный/архивированный кредит
        //    продолжал бы вычитаться из Дашборда бесконечно.
        let creditArchived = Credit(
            name: "Погашенный кредит",
            amount: 15_000.0,
            interestRate: 0.0,
            monthlyPayment: 500.0,
            startDate: Date(),
            termMonths: 6,
            currency: "RUB"
        )
        creditArchived.remainingAmount = 15_000.0
        creditArchived.updatedAt = Date()
        creditArchived.archivedAt = Date().addingTimeInterval(-86_400)
        modelContext.insert(creditArchived)

        // 7. Мультивалютная инвестиция (USD) — курс задаём мок-сервисом 1 USD = 100 RUB.
        let investmentUSD = Investment(
            name: "Инвестиция USD",
            investmentType: .positive,
            category: .stocks,
            amount: 100.0,
            currency: "USD"
        )
        modelContext.insert(investmentUSD)

        let accounts: [(FinanceAccountType, String)] = [
            (.card, cardActive.cardUniqueID),
            (.card, cardExcluded.cardUniqueID),
            (.card, cardArchived.cardUniqueID),
            (.card, creditCard.cardUniqueID),
            (.credit, creditActive.creditUniqueID),
            (.credit, creditArchived.creditUniqueID),
            (.investment, investmentUSD.investmentUniqueID)
        ]
        for (type, id) in accounts {
            let account = FinanceAccount(accountType: type, accountID: id)
            account.group = group
            modelContext.insert(account)
        }

        try modelContext.save()

        let mockRateService = MockCurrencyRateService()
        mockRateService.setRate(from: "USD", to: "RUB", rate: 100.0)

        // --- Дашборд / «Счета» ---
        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )
        financeViewModel.handle(.loadAccounts)
        financeViewModel.handle(.loadGroups)
        let totalsSnapshot = await financeViewModel.totalsService.calculateTotalsSnapshot()

        // --- Динамика ---
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: mockRateService
        )
        dynamicsViewModel.handle(.loadData)
        await dynamicsViewModel.updateCurrentBalanceAndDelta()

        // Ожидание: 10000 (активная карта) − 30000 (долг кредитки) − 40000 (кредит)
        // + 100*100 (инвестиция USD→RUB) = −50000. Исключённые/архивные счета вклада НЕ дают.
        let expected = 10_000.0 - 30_000.0 - 40_000.0 + 10_000.0

        #expect(abs(totalsSnapshot.totalAmount - expected) < 0.01, "TotalsService (Дашборд/Счета) разошёлся с ожидаемым")
        #expect(abs(dynamicsViewModel.state.currentBalance - expected) < 0.01, "Динамика разошлась с ожидаемым")
        #expect(
            abs(totalsSnapshot.totalAmount - dynamicsViewModel.state.currentBalance) < 0.01,
            "Дашборд/Счета и Динамика должны совпадать до копейки"
        )
    }
}
