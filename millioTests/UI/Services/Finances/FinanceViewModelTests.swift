//
//  FinanceViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 23.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

// MARK: - Мок сервиса курсов валют

@MainActor
final class MockCurrencyRateService: CurrencyRateServiceProtocol {
    /// Курсы: [fromCurrency: [toCurrency: rate]]
    var rates: [String: [String: Double]] = [:]
    private(set) var forceRefreshCallCount: Int = 0

    func setRate(from: String, to: String, rate: Double) {
        if rates[from] == nil { rates[from] = [:] }
        rates[from]![to] = rate
        if rates[to] == nil { rates[to] = [:] }
        rates[to]![from] = 1.0 / rate
    }

    func getRate(from: String, to: String) async -> Double? {
        if from == to { return 1.0 }
        return rates[from]?[to]
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        return await getRate(from: from, to: to)
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {
        forceRefreshCallCount += 1
    }
}

actor MockMarketDataClient: MarketDataClientProtocol {
    var pricesBySymbol: [String: Double?]

    init(pricesBySymbol: [String: Double?] = [:]) {
        self.pricesBySymbol = pricesBySymbol
    }

    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] {
        []
    }

    func latestPrice(symbol: String, forceRefresh: Bool) async throws -> Double? {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return pricesBySymbol[key] ?? nil
    }
}

// MARK: - Тесты

@Suite(.serialized)
@MainActor
struct FinanceViewModelTests {
    private static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
    ])
    private static var retainedContainers: [ModelContainer] = []

    /// Получить изолированный контекст на тест.
    /// Повторное использование одного mainContext между кейсами приводит к use-after-reset в SwiftData.
    private func createTestModelContext() throws -> ModelContext {
        let defaults = UserDefaults.standard
        defaults.set("RUB", forKey: "primaryCurrencyCode")
        defaults.set(false, forKey: "finance_savings_goal_enabled")
        defaults.set(0, forKey: "finance_savings_goal_amount")
        defaults.removeObject(forKey: "finance_savings_goal_currency")

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }

    private func waitForAsyncStatePropagation(
        until condition: @escaping @MainActor () -> Bool = { true }
    ) async -> Bool {
        // В ViewModel используются fire-and-forget Task, поэтому ждем до таймаута.
        for _ in 0..<100 {
            await Task.yield()
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("FinanceViewModel синхронизирует display валюту при смене основной если модуль следовал прошлой основной")
    func testSyncPrimaryCurrencyChangeUpdatesFollowingDisplayCurrency() throws {
        let modelContext = try createTestModelContext()

        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)
        #expect(viewModel.state.displayCurrency == "RUB")

        viewModel.handle(.syncPrimaryCurrencyChange(old: "RUB", new: "USD"))

        #expect(viewModel.state.displayCurrency == "USD")
    }

    @Test("Инвестиции без FinanceAccount привязываются к \"Без группы\" и становятся видимыми")
    func testMissingInvestmentLinksAreRecoveredIntoUngroupedGroup() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let investment = Investment(
            name: "Test ETF",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        modelContext.insert(investment)
        try modelContext.save()

        _ = FinanceViewModel(
            modelContext: modelContext,
            currencyService: currencyService,
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: false
        )

        let accounts = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        let groups = try modelContext.fetch(FetchDescriptor<FinanceGroup>())

        #expect(accounts.count == 1)
        #expect(groups.count == 1)
        #expect(accounts[0].accountType == .investment)
        #expect(accounts[0].accountID == investment.investmentUniqueID)
        #expect(accounts[0].group?.name == String(localized: "finances.group.ungrouped"))
    }

    @Test("Негативные инвестиции подсвечиваются как обязательства")
    func testNegativeInvestmentsAreDetectedAsLiabilities() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let investment = Investment(
            name: "Test Debt",
            investmentType: .negative,
            category: .debt,
            amount: 1000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        modelContext.insert(investment)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: currencyService,
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: false
        )

        _ = await waitForAsyncStatePropagation(until: { !viewModel.state.groups.isEmpty })

        let accounts = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(accounts.count == 1)
        #expect(viewModel.isAccountLiabilityForTotals(account: accounts[0]) == true)
    }

    @Test("FinanceViewModel смена display валюты не меняет primary валюту профиля")
    func testSetDisplayCurrencyDoesNotChangePrimaryCurrency() throws {
        let modelContext = try createTestModelContext()
        let defaults = UserDefaults.standard
        let primaryKey = "primaryCurrencyCode"
        let originalPrimary = defaults.string(forKey: primaryKey)
        defer {
            if let originalPrimary {
                defaults.set(originalPrimary, forKey: primaryKey)
            } else {
                defaults.removeObject(forKey: primaryKey)
            }
        }
        defaults.set("USD", forKey: primaryKey)

        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)
        viewModel.handle(.setDisplayCurrency("AMD"))

        #expect(viewModel.state.displayCurrency == "AMD")
        #expect(SettingsManager.shared.primaryCurrencyCode == "USD")
    }

    @Test("FinanceViewModel раскрывает и сворачивает группу по groupUniqueID")
    func testToggleGroupExpandedTracksGroupUniqueID() throws {
        let modelContext = try createTestModelContext()
        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF", order: 0)
        let groupID = group.groupUniqueID

        #expect(viewModel.state.expandedGroupIDs.contains(groupID) == false)

        viewModel.handle(.toggleGroupExpanded(groupID))
        #expect(viewModel.state.expandedGroupIDs.contains(groupID))

        viewModel.handle(.toggleGroupExpanded(groupID))
        #expect(viewModel.state.expandedGroupIDs.contains(groupID) == false)
    }

    @Test("FinanceViewModel сохраняет ручной порядок групп после перетаскивания")
    func testMoveGroupReordersVisibleGroups() throws {
        let modelContext = try createTestModelContext()

        let first = FinanceGroup(name: "Первая", colorHex: "#111111", order: 0)
        let second = FinanceGroup(name: "Вторая", colorHex: "#222222", order: 1)
        let third = FinanceGroup(name: "Третья", colorHex: "#333333", order: 2)
        modelContext.insert(first)
        modelContext.insert(second)
        modelContext.insert(third)
        try modelContext.save()

        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)
        viewModel.handle(.loadGroups)

        viewModel.handle(.moveGroup(sourceGroupID: third.groupUniqueID, destinationIndex: 0))

        #expect(viewModel.visibleGroupsForList().map(\.name) == ["Третья", "Первая", "Вторая"])
        #expect(viewModel.state.groups.map(\.order) == [0, 1, 2])
    }

    @Test("FinanceViewModel по умолчанию сортирует счета в группе по сумме по убыванию и сохраняет ручной порядок")
    func testOrderedAccountsUseAmountThenManualOrder() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF", order: 0)
        modelContext.insert(group)

        let small = Card(
            name: "Small",
            cardNumber: "1111",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100
        )
        let large = Card(
            name: "Large",
            cardNumber: "2222",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 300
        )
        let medium = Credit(
            name: "Medium debt",
            amount: 1_000,
            interestRate: 10,
            monthlyPayment: 100,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        medium.remainingAmount = 200

        modelContext.insert(small)
        modelContext.insert(large)
        modelContext.insert(medium)

        let smallAccount = FinanceAccount(accountType: .card, accountID: small.cardUniqueID)
        smallAccount.group = group
        let largeAccount = FinanceAccount(accountType: .card, accountID: large.cardUniqueID)
        largeAccount.group = group
        let mediumAccount = FinanceAccount(accountType: .credit, accountID: medium.creditUniqueID)
        mediumAccount.group = group

        modelContext.insert(smallAccount)
        modelContext.insert(largeAccount)
        modelContext.insert(mediumAccount)
        try modelContext.save()

        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        let loadedGroup = try #require(viewModel.state.groups.first)
        #expect(viewModel.orderedAccounts(for: loadedGroup).map(\.accountID) == [
            large.cardUniqueID,
            medium.creditUniqueID,
            small.cardUniqueID,
        ])

        viewModel.handle(
            .moveAccount(
                sourceAccountID: smallAccount.accountUniqueID,
                destinationIndex: 0,
                groupID: loadedGroup.groupUniqueID
            )
        )

        let reorderedGroup = try #require(viewModel.state.groups.first)
        #expect(reorderedGroup.usesManualAccountOrdering)
        #expect(viewModel.orderedAccounts(for: reorderedGroup).map(\.accountID) == [
            small.cardUniqueID,
            large.cardUniqueID,
            medium.creditUniqueID,
        ])
    }

    @Test("FinanceViewModel пересчитывает сумму цели накопления при смене display валюты")
    func testSetDisplayCurrencyConvertsSavingsGoalAmount() async throws {
        let modelContext = try createTestModelContext()
        let mockRateService = MockCurrencyRateService()
        mockRateService.setRate(from: "RUB", to: "USD", rate: 0.01)

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )

        viewModel.handle(.setDisplayCurrency("RUB"))
        _ = await waitForAsyncStatePropagation { viewModel.state.displayCurrency == "RUB" }
        viewModel.handle(.setSavingsGoalAmount(100_000))
        viewModel.handle(.setDisplayCurrency("USD"))
        let didReachExpectedState = await waitForAsyncStatePropagation {
            viewModel.state.displayCurrency == "USD" && abs(viewModel.state.savingsGoalAmount - 1_000) < 0.01
        }

        #expect(didReachExpectedState)
        #expect(viewModel.state.displayCurrency == "USD")
        #expect(abs(viewModel.state.savingsGoalAmount - 1_000) < 0.01)
    }

    @Test("FinanceViewModel не перезаписывает кастомную display валюту при смене основной")
    func testSyncPrimaryCurrencyChangeKeepsCustomDisplayCurrency() throws {
        let modelContext = try createTestModelContext()

        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)
        #expect(viewModel.state.displayCurrency == "RUB")
        viewModel.handle(.setDisplayCurrency("EUR"))
        #expect(viewModel.state.displayCurrency == "EUR")

        viewModel.handle(.syncPrimaryCurrencyChange(old: "RUB", new: "USD"))

        #expect(viewModel.state.displayCurrency == "EUR")
    }

    @Test("FinanceViewModel пересчитывает сумму цели при sync primary currency")
    func testSyncPrimaryCurrencyChangeConvertsSavingsGoalAmount() async throws {
        let modelContext = try createTestModelContext()
        let mockRateService = MockCurrencyRateService()
        mockRateService.setRate(from: "RUB", to: "USD", rate: 0.01)

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )

        viewModel.handle(.setDisplayCurrency("RUB"))
        _ = await waitForAsyncStatePropagation { viewModel.state.displayCurrency == "RUB" }
        viewModel.handle(.setSavingsGoalAmount(50_000))
        viewModel.handle(.syncPrimaryCurrencyChange(old: "RUB", new: "USD"))
        let didReachExpectedState = await waitForAsyncStatePropagation {
            viewModel.state.displayCurrency == "USD" && abs(viewModel.state.savingsGoalAmount - 500) < 0.01
        }

        #expect(didReachExpectedState)
        #expect(viewModel.state.displayCurrency == "USD")
        #expect(abs(viewModel.state.savingsGoalAmount - 500) < 0.01)
    }

    @Test("FinanceViewModel пересчитывает сохраненную цель при новом входе после смены основной валюты")
    func testInitConvertsSavedGoalFromStoredCurrencyToPrimaryCurrency() async throws {
        let modelContext = try createTestModelContext()
        let defaults = UserDefaults.standard
        defaults.set("RUB", forKey: "primaryCurrencyCode")
        defaults.set(1_000_000, forKey: "finance_savings_goal_amount")
        defaults.set("USD", forKey: "finance_savings_goal_currency")

        let mockRateService = MockCurrencyRateService()
        mockRateService.setRate(from: "USD", to: "RUB", rate: 100)

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )
        let didReachExpectedState = await waitForAsyncStatePropagation {
            viewModel.state.displayCurrency == "RUB" && abs(viewModel.state.savingsGoalAmount - 100_000_000) < 0.01
        }

        #expect(didReachExpectedState)
        #expect(viewModel.state.displayCurrency == "RUB")
        #expect(abs(viewModel.state.savingsGoalAmount - 100_000_000) < 0.01)
    }

    @Test("Расчет суммы группы с разными валютами работает корректно")
    func testCalculateGroupTotalWithMultipleCurrencies() async throws {
        let modelContext = try createTestModelContext()

        // Создаем группу
        let group = FinanceGroup(name: "Тестовая группа", colorHex: "#FF0000")
        group.displayCurrency = "RUB"
        modelContext.insert(group)

        // Создаем карту в RUB
        let cardRUB = Card(
            name: "Карта RUB",
            cardNumber: "1234",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 10000.0
        )
        cardRUB.includeInTotal = true
        modelContext.insert(cardRUB)

        // Создаем карту в USD
        let cardUSD = Card(
            name: "Карта USD",
            cardNumber: "5678",
            bank: .tinkoff,
            cardType: .debit,
            currency: "USD",
            balance: 100.0
        )
        cardUSD.includeInTotal = true
        modelContext.insert(cardUSD)

        // Создаем инвестицию в EUR
        let investmentEUR = Investment(
            name: "Инвестиция EUR",
            investmentType: .positive,
            category: .stocks,
            amount: 500.0,
            currency: "EUR"
        )
        investmentEUR.includeInTotal = true
        modelContext.insert(investmentEUR)

        // Создаем счета и привязываем к группе
        let accountRUB = FinanceAccount(accountType: .card, accountID: cardRUB.cardUniqueID)
        accountRUB.group = group

        let accountUSD = FinanceAccount(accountType: .card, accountID: cardUSD.cardUniqueID)
        accountUSD.group = group

        let accountEUR = FinanceAccount(accountType: .investment, accountID: investmentEUR.investmentUniqueID)
        accountEUR.group = group

        modelContext.insert(accountRUB)
        modelContext.insert(accountUSD)
        modelContext.insert(accountEUR)

        try modelContext.save()

        // Настраиваем мок-сервис курсов
        let mockRateService = MockCurrencyRateService()
        // USD → RUB = 100, EUR → RUB = 111.11
        mockRateService.setRate(from: "USD", to: "RUB", rate: 100.0)
        mockRateService.setRate(from: "EUR", to: "RUB", rate: 111.11)

        // Создаем ViewModel без автозагрузки
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        // Рассчитываем сумму группы в RUB
        // Ожидаемый результат:
        // - RUB: 10000.0 (без конвертации)
        // - USD: 100.0 * 100.0 = 10000.0 RUB
        // - EUR: 500.0 * 111.11 = 55555.0 RUB
        // Итого: 10000 + 10000 + 55555 = 75555.0 RUB
        let total = await viewModel.calculateGroupTotal(group: group, in: "RUB")

        #expect(total > 10000.0, "Сумма должна быть больше суммы только в RUB, что означает успешную конвертацию")
        #expect(total >= 10000.0, "Сумма должна включать хотя бы сумму в RUB")

        // Проверяем точное значение с учетом курсов мока
        let expected = 10000.0 + (100.0 * 100.0) + (500.0 * 111.11)
        #expect(abs(total - expected) < 0.01, "Сумма должна соответствовать ожидаемому значению с учетом курсов")
    }

    @Test("Расчет суммы группы с разными валютами работает без потери конвертаций")
    func testCalculateGroupTotalWithMultipleCurrenciesAndCredit() async throws {
        let modelContext = try createTestModelContext()

        // Создаем группу
        let group = FinanceGroup(name: "Группа с разными валютами", colorHex: "#00FF00")
        group.displayCurrency = "USD"
        modelContext.insert(group)

        // Создаем счета в разных валютах
        let cardRUB = Card(
            name: "Карта RUB",
            cardNumber: "1111",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 5000.0
        )
        cardRUB.includeInTotal = true

        let cardEUR = Card(
            name: "Карта EUR",
            cardNumber: "2222",
            bank: .vtb,
            cardType: .debit,
            currency: "EUR",
            balance: 200.0
        )
        cardEUR.includeInTotal = true

        let creditUSD = Credit(
            name: "Кредит USD",
            amount: 10000.0,
            interestRate: 10.0,
            monthlyPayment: 500.0,
            startDate: Date(),
            termMonths: 24,
            currency: "USD"
        )
        creditUSD.remainingAmount = 5000.0
        creditUSD.includeInTotal = true

        modelContext.insert(cardRUB)
        modelContext.insert(cardEUR)
        modelContext.insert(creditUSD)

        // Создаем счета и привязываем к группе
        let accountRUB = FinanceAccount(accountType: .card, accountID: cardRUB.cardUniqueID)
        accountRUB.group = group

        let accountEUR = FinanceAccount(accountType: .card, accountID: cardEUR.cardUniqueID)
        accountEUR.group = group

        let accountUSD = FinanceAccount(accountType: .credit, accountID: creditUSD.creditUniqueID)
        accountUSD.group = group

        modelContext.insert(accountRUB)
        modelContext.insert(accountEUR)
        modelContext.insert(accountUSD)

        try modelContext.save()

        // Настраиваем мок-сервис курсов
        let mockRateService = MockCurrencyRateService()
        mockRateService.setRate(from: "RUB", to: "USD", rate: 0.01) // 1 RUB = 0.01 USD
        mockRateService.setRate(from: "EUR", to: "USD", rate: 1.1)  // 1 EUR = 1.1 USD

        // Создаем ViewModel без автозагрузки
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        // Рассчитываем сумму группы в USD
        let total = await viewModel.calculateGroupTotal(group: group, in: "USD")

        // Ожидаемый результат:
        // - RUB 5000 * 0.01 = 50 USD
        // - EUR 200 * 1.1 = 220 USD
        // - USD кредит -5000 USD
        // Итого: 50 + 220 - 5000 = -4730 USD
        #expect(total != 0.0, "Сумма должна быть рассчитана с учетом всех валют")

        let usdOnlyAmount = -5000.0
        #expect(abs(total - usdOnlyAmount) > 0.01, "Сумма должна отличаться от суммы только в USD")
    }

    @Test("Пересчет общей суммы не делает принудительный refresh курсов")
    func testCalculateTotalAmountDoesNotForceRefreshRates() async throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Мультивалюта", colorHex: "#00AAFF")
        group.displayCurrency = "RUB"
        modelContext.insert(group)

        let cardUSD = Card(
            name: "USD карта",
            cardNumber: "1001",
            bank: .tinkoff,
            cardType: .debit,
            currency: "USD",
            balance: 10.0
        )
        cardUSD.includeInTotal = true
        modelContext.insert(cardUSD)

        let accountUSD = FinanceAccount(accountType: .card, accountID: cardUSD.cardUniqueID)
        accountUSD.group = group
        modelContext.insert(accountUSD)
        try modelContext.save()

        let mockRateService = MockCurrencyRateService()
        mockRateService.setRate(from: "USD", to: "RUB", rate: 100.0)

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        await viewModel.calculateTotalAmountAsync()

        #expect(mockRateService.forceRefreshCallCount == 0)
        #expect(abs(viewModel.state.totalAmount - 1000.0) < 0.01)
    }

    @Test("Суммы в валютах без курса конвертации пропускаются корректно")
    func testSkippedAmountsLogging() async throws {
        let modelContext = try createTestModelContext()

        // Создаем группу
        let group = FinanceGroup(name: "Группа с неизвестной валютой", colorHex: "#0000FF")
        group.displayCurrency = "RUB"
        modelContext.insert(group)

        // Создаем карту в известной валюте
        let cardRUB = Card(
            name: "Карта RUB",
            cardNumber: "3333",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 1000.0
        )
        cardRUB.includeInTotal = true

        // Создаем карту в несуществующей валюте
        let cardUnknown = Card(
            name: "Карта Unknown",
            cardNumber: "4444",
            bank: .other,
            cardType: .debit,
            currency: "XXX",
            balance: 500.0
        )
        cardUnknown.includeInTotal = true

        modelContext.insert(cardRUB)
        modelContext.insert(cardUnknown)

        // Создаем счета и привязываем к группе
        let accountRUB = FinanceAccount(accountType: .card, accountID: cardRUB.cardUniqueID)
        accountRUB.group = group

        let accountUnknown = FinanceAccount(accountType: .card, accountID: cardUnknown.cardUniqueID)
        accountUnknown.group = group

        modelContext.insert(accountRUB)
        modelContext.insert(accountUnknown)

        try modelContext.save()

        // Настраиваем мок-сервис БЕЗ курса для XXX
        let mockRateService = MockCurrencyRateService()
        // Не добавляем курс для XXX — getRate вернет nil

        // Создаем ViewModel без автозагрузки
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        // Рассчитываем сумму группы
        let total = await viewModel.calculateGroupTotal(group: group, in: "RUB")

        // Сумма должна включать только RUB (XXX пропущена)
        #expect(total >= 1000.0, "Сумма должна включать хотя бы сумму в RUB")
        #expect(total <= 1000.0 + 0.01, "Сумма не должна включать сумму в валюте без курса конвертации")
    }

    @Test("Суммы в стейблкоинах конвертируются как USD")
    func testStablecoinAmountsAreConvertedAsUSD() async throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Крипто группа", colorHex: "#00AAFF")
        group.displayCurrency = "RUB"
        modelContext.insert(group)

        let usdtInvestment = Investment(
            name: "BTC/USDT",
            investmentType: .positive,
            category: .crypto,
            amount: 100.0,
            currency: "USDT"
        )
        usdtInvestment.includeInTotal = true
        modelContext.insert(usdtInvestment)

        let account = FinanceAccount(accountType: .investment, accountID: usdtInvestment.investmentUniqueID)
        account.group = group
        modelContext.insert(account)

        try modelContext.save()

        let mockRateService = MockCurrencyRateService()
        mockRateService.setRate(from: "USD", to: "RUB", rate: 100.0)

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        let total = await viewModel.calculateGroupTotal(group: group, in: "RUB")
        #expect(abs(total - 10000.0) < 0.01, "USDT должен конвертироваться как USD")
    }

    @Test("Валюта инвестиции берется из marketSymbol, если currency пустая")
    func testInvestmentCurrencyFallbackFromMarketSymbol() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Крипто", colorHex: "#22AAFF")
        modelContext.insert(group)

        let investment = Investment(
            name: "BTC/USD",
            investmentType: .positive,
            category: .crypto,
            amount: 132_472,
            currency: ""
        )
        investment.marketSymbol = "BTC/USD"
        investment.marketCurrency = nil
        investment.includeInTotal = true
        modelContext.insert(investment)

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        modelContext.insert(account)

        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        let info = viewModel.getAccountInfo(account: account)
        #expect(info?.currency == "USD")
    }

    @Test("Для рыночной инвестиции показывается количество и цена за штуку")
    func testInvestmentPositionSubtitle() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Акции", colorHex: "#33AA44")
        modelContext.insert(group)

        let investment = Investment(
            name: "AAPL",
            investmentType: .positive,
            category: .stocks,
            amount: 1000,
            currency: "USD"
        )
        investment.marketQuantity = 2
        investment.lastKnownUnitPrice = 500
        investment.includeInTotal = true
        modelContext.insert(investment)

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        let subtitle = viewModel.getInvestmentPositionSubtitle(account: account)
        let expectedSubtitle = FinancesL10n.format(
            "finances.investment.position_subtitle",
            "2",
            String(localized: "finances.investment.unit.shares_short"),
            "500",
            "$"
        )
        #expect(subtitle == expectedSubtitle)
    }

    @Test("Для акций в финансах показывается короткий тикер без market prefix")
    func testInvestmentDisplayNameUsesShortTickerForStocks() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Акции", colorHex: "#33AA44")
        modelContext.insert(group)

        let investment = Investment(
            name: "SPDR Gold Shares",
            investmentType: .positive,
            category: .stocks,
            amount: 1500,
            currency: "USD"
        )
        investment.marketSymbol = "US:SIVR"
        investment.includeInTotal = true
        modelContext.insert(investment)

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        let info = viewModel.getAccountInfo(account: account)
        #expect(info?.name == "SIVR")
    }

    @Test("Для рыночной инвестиции показывается строка покупки и прироста")
    func testInvestmentPurchaseGrowthSubtitle() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Акции", colorHex: "#33AA44")
        modelContext.insert(group)

        let investment = Investment(
            name: "GLD",
            investmentType: .positive,
            category: .stocks,
            amount: 1500,
            currency: "USD"
        )
        investment.marketQuantity = 10
        investment.lastKnownUnitPrice = 150
        investment.averagePurchaseUnitPrice = 100
        investment.totalPurchaseCost = 1000
        investment.includeInTotal = true
        modelContext.insert(investment)

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        let performance = viewModel.getInvestmentPurchaseGrowthSubtitle(account: account)
        let expectedPerformanceText = FinancesL10n.format(
            "finances.investment.purchase_growth_subtitle",
            "100",
            "$",
            "+50%"
        )
        #expect(performance?.text == expectedPerformanceText)
        #expect(performance?.text.contains("+50%") == true)
        #expect(performance?.isPositive == true)
    }

    @Test("Быстрое редактирование рыночной инвестиции меняет количество, а не сумму напрямую")
    func testQuickEditMarketInvestmentUpdatesQuantity() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Крипто", colorHex: "#22AAFF")
        modelContext.insert(group)

        let investment = Investment(
            name: "BTC/USD",
            investmentType: .positive,
            category: .crypto,
            amount: 2000,
            currency: "USD"
        )
        investment.marketQuantity = 2
        investment.lastKnownUnitPrice = 1000
        investment.includeInTotal = true
        modelContext.insert(investment)

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        var didPublishTransactionsUpdated = false
        let subscriptionID = EventBus.shared.subscribe { event in
            if case FinanceEvent.transactionsUpdated = event {
                didPublishTransactionsUpdated = true
            }
        }
        defer { EventBus.shared.unsubscribe(subscriptionID) }

        viewModel.handle(.updateAccountAmount(account, 3.5))

        #expect(abs((investment.marketQuantity ?? 0) - 3.5) < 0.000001)
        #expect(abs(investment.amount - 3500) < 0.01)
        #expect(didPublishTransactionsUpdated)

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = try modelContext.fetch(descriptor)
        #expect(transactions.count == 1)
        guard let transaction = transactions.first else { return }
        #expect(abs(transaction.amount - 1500) < 0.01)
        #expect(transaction.investmentID == investment.investmentUniqueID)
        #expect(transaction.exchangeRate == 1.0)
        #expect(transaction.exchangeRateCurrency == "USD")
        #expect(transaction.exchangeRateDate != nil)
    }

    @Test("Покупка и продажа рыночной инвестиции через executeInvestmentOrder обновляет cost basis и транзакции")
    func testExecuteInvestmentOrderBuySell() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Акции", colorHex: "#3366FF")
        modelContext.insert(group)

        let investment = Investment(
            name: "AAPL",
            investmentType: .positive,
            category: .stocks,
            amount: 1000,
            currency: "USD"
        )
        investment.marketQuantity = 10
        investment.lastKnownUnitPrice = 100
        investment.averagePurchaseUnitPrice = 100
        investment.totalPurchaseCost = 1000
        investment.includeInTotal = true
        modelContext.insert(investment)

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        viewModel.handle(.executeInvestmentOrder(
            account: account,
            side: .buy,
            quantity: 10,
            unitPrice: 200
        ))

        #expect(abs((investment.marketQuantity ?? 0) - 20) < 0.0001)
        #expect(abs((investment.averagePurchaseUnitPrice ?? 0) - 150) < 0.0001)
        #expect(abs((investment.totalPurchaseCost ?? 0) - 3000) < 0.0001)
        #expect(abs(investment.amount - 4000) < 0.01)

        viewModel.handle(.executeInvestmentOrder(
            account: account,
            side: .sell,
            quantity: 5,
            unitPrice: 220
        ))

        #expect(abs((investment.marketQuantity ?? 0) - 15) < 0.0001)
        #expect(abs((investment.averagePurchaseUnitPrice ?? 0) - 150) < 0.0001)
        #expect(abs((investment.totalPurchaseCost ?? 0) - 2250) < 0.0001)
        #expect(abs(investment.amount - 3300) < 0.01)

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = try modelContext.fetch(descriptor)
        #expect(transactions.count == 2)
    }

    @Test("Обновление акций обновляет котировки только категории stocks")
    func testRefreshStockPricesUpdatesOnlyStocks() async throws {
        let modelContext = try createTestModelContext()

        let stockInvestment = Investment(
            name: "Apple",
            investmentType: .positive,
            category: .stocks,
            amount: 100.0,
            currency: "USD"
        )
        stockInvestment.marketSymbol = "AAPL"
        stockInvestment.marketQuantity = 2
        stockInvestment.lastKnownUnitPrice = 50
        modelContext.insert(stockInvestment)

        let cryptoInvestment = Investment(
            name: "Bitcoin",
            investmentType: .positive,
            category: .crypto,
            amount: 500.0,
            currency: "USD"
        )
        cryptoInvestment.marketSymbol = "BTC/USD"
        cryptoInvestment.marketQuantity = 0.01
        cryptoInvestment.lastKnownUnitPrice = 50_000
        modelContext.insert(cryptoInvestment)

        try modelContext.save()

        let marketClient = MockMarketDataClient(pricesBySymbol: [
            "AAPL": 120.0,
            "BTC/USD": 90_000.0
        ])

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        #expect(abs((stockInvestment.lastKnownUnitPrice ?? 0) - 120.0) < 0.000001)
        #expect(abs(stockInvestment.amount - 240.0) < 0.01)
        #expect(abs((cryptoInvestment.lastKnownUnitPrice ?? 0) - 50_000.0) < 0.000001)
        #expect(abs(cryptoInvestment.amount - 500.0) < 0.01)
        #expect(viewModel.state.isLoadingRates == false)
    }

    @Test("Быстрое редактирование кредитной карты обновляет лимит, долг и создает корректировку")
    func testQuickEditCreditCardFields() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Карты", colorHex: "#22AAFF")
        modelContext.insert(group)

        let card = Card(
            name: "Кредитка",
            cardNumber: "1234",
            bank: .tinkoff,
            cardType: .credit,
            currency: "RUB",
            balance: 7000,
            creditLimit: 10_000
        )
        card.includeInTotal = true
        modelContext.insert(card)

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        let oldDebt = max(0, (card.creditLimit ?? 0) - card.balance)
        #expect(abs(oldDebt - 3000) < 0.01)

        var didPublishTransactionsUpdated = false
        let subscriptionID = EventBus.shared.subscribe { event in
            if case FinanceEvent.transactionsUpdated = event {
                didPublishTransactionsUpdated = true
            }
        }
        defer { EventBus.shared.unsubscribe(subscriptionID) }

        viewModel.handle(.updateCreditCardQuickFields(account: account, creditLimit: 12_000, debt: 4_500))

        #expect(abs((card.creditLimit ?? 0) - 12_000) < 0.01)
        #expect(abs(card.balance - 7_500) < 0.01)
        #expect(didPublishTransactionsUpdated)

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = try modelContext.fetch(descriptor)
        #expect(transactions.count == 1)

        guard let transaction = transactions.first else { return }
        #expect(transaction.transactionType == .creditDebtAdjustment)
        #expect(abs(transaction.amount + 1_500) < 0.01)
        #expect(transaction.cardID == card.cardUniqueID)
    }

    @Test("Для кредитной карты возвращается остаток лимита")
    func testCreditCardLimitRemainingSubtitleData() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Карты", colorHex: "#22AAFF")
        modelContext.insert(group)

        let card = Card(
            name: "Кредитка",
            cardNumber: "9999",
            bank: .alfa,
            cardType: .credit,
            currency: "RUB",
            balance: 7_778,
            creditLimit: 10_000
        )
        modelContext.insert(card)

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        let limitInfo = viewModel.getCreditCardLimitRemaining(account: account)
        #expect(limitInfo != nil)
        #expect(abs((limitInfo?.amount ?? 0) - 7_778) < 0.01)
        #expect(limitInfo?.currency == "RUB")
    }

    @Test("Для дебетовой карты остаток лимита не возвращается")
    func testDebitCardHasNoCreditLimitRemaining() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Карты", colorHex: "#22AAFF")
        modelContext.insert(group)

        let card = Card(
            name: "Дебетовая",
            cardNumber: "1111",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 2_000
        )
        modelContext.insert(card)

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        let limitInfo = viewModel.getCreditCardLimitRemaining(account: account)
        #expect(limitInfo == nil)
    }

    @Test("Невалидные связи FinanceAccount очищаются при загрузке счетов")
    func testCleanupInvalidFinanceAccounts() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Тестовая группа", colorHex: "#123456")
        modelContext.insert(group)

        let card = Card(
            name: "Карта",
            cardNumber: "9999",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100.0
        )
        modelContext.insert(card)

        let validAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        validAccount.group = group
        modelContext.insert(validAccount)

        let missingCardAccount = FinanceAccount(accountType: .card, accountID: "missing-card-id")
        missingCardAccount.group = group
        modelContext.insert(missingCardAccount)

        let noGroupAccount = FinanceAccount(accountType: .credit, accountID: "missing-credit-id")
        modelContext.insert(noGroupAccount)

        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )

        viewModel.handle(.loadAccounts)

        let descriptor = FetchDescriptor<FinanceAccount>()
        let accounts = (try? modelContext.fetch(descriptor)) ?? []

        #expect(accounts.count == 1, "Должна остаться только валидная связь")
        #expect(accounts.first?.accountID == card.cardUniqueID, "Оставшаяся связь должна вести на существующую карту")
    }

    @Test("Валидные связи разных типов сохраняются при очистке")
    func testCleanupKeepsValidAccountsForAllTypes() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Группа", colorHex: "#ABCDEF")
        modelContext.insert(group)

        let card = Card(
            name: "Карта",
            cardNumber: "1111",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100.0
        )
        let credit = Credit(
            name: "Кредит",
            amount: 1000.0,
            interestRate: 10.0,
            monthlyPayment: 100.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        let investment = Investment(
            name: "Актив",
            investmentType: .positive,
            category: .stocks,
            amount: 500.0,
            currency: "RUB"
        )

        modelContext.insert(card)
        modelContext.insert(credit)
        modelContext.insert(investment)

        let cardAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        cardAccount.group = group
        let creditAccount = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        creditAccount.group = group
        let investmentAccount = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        investmentAccount.group = group

        modelContext.insert(cardAccount)
        modelContext.insert(creditAccount)
        modelContext.insert(investmentAccount)

        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )

        viewModel.handle(.loadAccounts)

        let descriptor = FetchDescriptor<FinanceAccount>()
        let accounts = (try? modelContext.fetch(descriptor)) ?? []
        let accountIDs = Set(accounts.map { $0.accountID })

        #expect(accounts.count == 3, "Все валидные связи должны сохраниться")
        #expect(accountIDs.contains(card.cardUniqueID))
        #expect(accountIDs.contains(credit.creditUniqueID))
        #expect(accountIDs.contains(investment.investmentUniqueID))
    }

    @Test("Событие обновления кредитов пересчитывает суммы групп")
    func testCreditsUpdatedEventRecalculatesGroupTotals() async throws {
        let modelContext = try createTestModelContext()
        
        let displayCurrencyKey = "finance_display_currency"
        let previousDisplayCurrency = UserDefaults.standard.string(forKey: displayCurrencyKey)
        defer {
            if let previousDisplayCurrency {
                UserDefaults.standard.set(previousDisplayCurrency, forKey: displayCurrencyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: displayCurrencyKey)
            }
        }
        UserDefaults.standard.set("RUB", forKey: displayCurrencyKey)

        let group = FinanceGroup(name: "Группа", colorHex: "#123456")
        modelContext.insert(group)

        let credit = Credit(
            name: "Кредит",
            amount: 1000.0,
            interestRate: 0.0,
            monthlyPayment: 100.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.remainingAmount = 1000.0
        credit.includeInTotal = true
        modelContext.insert(credit)

        let account = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        account.group = group
        modelContext.insert(account)
        group.accounts = [account]

        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)
        let trackedGroupID = try #require(viewModel.state.groups.first(where: { $0.name == group.name })?.groupUniqueID)

        credit.remainingAmount = 500.0
        credit.updatedAt = Date()
        try modelContext.save()

        EventBus.shared.publish(FinanceEvent.creditsUpdated)
        
        var didUpdate = false
        for _ in 0..<100 {
            let groupTotal = viewModel.state.groupTotals[trackedGroupID] ?? 0.0
            if abs(groupTotal + 500.0) < 0.01, abs(viewModel.state.totalAmount + 500.0) < 0.01 {
                didUpdate = true
                break
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
        
        #expect(didUpdate == true)
    }

    @Test("Удаление карты из финансов публикует событие обновления карт")
    func testDeleteCardPublishesCardsUpdatedEvent() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Группа", colorHex: "#123456")
        modelContext.insert(group)

        let card = Card(
            name: "Карта для удаления",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 10.0
        )
        modelContext.insert(card)

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        modelContext.insert(account)

        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )

        var didPublish = false
        let subscriptionID = EventBus.shared.subscribe { event in
            if case FinanceEvent.cardsUpdated = event {
                didPublish = true
            }
        }
        defer { EventBus.shared.unsubscribe(subscriptionID) }

        viewModel.handle(.deleteAccountPermanently(account))

        #expect(didPublish, "При удалении карты должно публиковаться событие обновления списка карт")
    }

    @Test("Удаление группы архивирует все привязанные счета и удаляет связи")
    func testDeleteGroupArchivesAccountsAndRemovesLinks() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Группа", colorHex: "#FF0000")
        modelContext.insert(group)

        let card = Card(
            name: "Карта",
            cardNumber: "1234",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 10.0
        )
        let credit = Credit(
            name: "Кредит",
            amount: 1000.0,
            interestRate: 10.0,
            monthlyPayment: 100.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.remainingAmount = 500.0
        let investment = Investment(
            name: "Актив",
            investmentType: .positive,
            category: .stocks,
            amount: 50.0,
            currency: "RUB"
        )

        modelContext.insert(card)
        modelContext.insert(credit)
        modelContext.insert(investment)

        let cardAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        cardAccount.group = group
        let creditAccount = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        creditAccount.group = group
        let investmentAccount = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        investmentAccount.group = group

        modelContext.insert(cardAccount)
        modelContext.insert(creditAccount)
        modelContext.insert(investmentAccount)

        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        let groupToDelete = try #require(viewModel.state.groups.first)
        viewModel.handle(.deleteGroup(groupToDelete))

        let groups = (try? modelContext.fetch(FetchDescriptor<FinanceGroup>())) ?? []
        #expect(groups.isEmpty)

        let links = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        #expect(links.isEmpty)

        let cards = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        let credits = (try? modelContext.fetch(FetchDescriptor<Credit>())) ?? []
        let investments = (try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []

        let updatedCard = cards.first { $0.cardUniqueID == card.cardUniqueID }
        let updatedCredit = credits.first { $0.creditUniqueID == credit.creditUniqueID }
        let updatedInvestment = investments.first { $0.investmentUniqueID == investment.investmentUniqueID }

        #expect(updatedCard?.archivedAt != nil)
        #expect(updatedCredit?.archivedAt != nil)
        #expect(updatedInvestment?.archivedAt != nil)
    }

    @Test("Восстановление из архива сбрасывает archivedAt и выставляет новую дату при повторной архивации")
    func testRestoreFromArchiveResetsDateAndReArchiveSetsNewDate() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Группа", colorHex: "#00FF00")
        modelContext.insert(group)

        let oldArchivedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let card = Card(
            name: "Архивная карта",
            cardNumber: "9999",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100.0
        )
        card.archivedAt = oldArchivedAt
        modelContext.insert(card)

        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        let targetGroup = try #require(viewModel.state.groups.first)
        viewModel.handle(.restoreArchivedAccountToGroup(
            accountType: .card,
            accountID: card.cardUniqueID,
            group: targetGroup
        ))

        let cardsAfterRestore = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        let restoredCard = try #require(cardsAfterRestore.first { $0.cardUniqueID == card.cardUniqueID })
        #expect(restoredCard.archivedAt == nil)

        let linksAfterRestore = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        let link = try #require(linksAfterRestore.first { $0.accountType == .card && $0.accountID == card.cardUniqueID })

        viewModel.handle(.removeAccountFromGroup(link))

        let cardsAfterReArchive = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        let reArchivedCard = try #require(cardsAfterReArchive.first { $0.cardUniqueID == card.cardUniqueID })
        let newArchivedAt = try #require(reArchivedCard.archivedAt)
        #expect(newArchivedAt > oldArchivedAt)
    }

    @Test("Кредит всегда уменьшает Итого даже при legacy includeInTotal = false")
    func testCreditAlwaysDecreasesTotal() async throws {
        let modelContext = try createTestModelContext()
        let group = FinanceGroup(name: "Кредиты", colorHex: "#112233")
        modelContext.insert(group)

        let credit = Credit(
            name: "Тестовый кредит",
            amount: 1_000,
            interestRate: 0,
            monthlyPayment: 100,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB"
        )
        credit.remainingAmount = 700
        credit.includeInTotal = false
        modelContext.insert(credit)

        let link = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        link.group = group
        modelContext.insert(link)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        let total = await viewModel.calculateGroupTotal(group: group, in: "RUB")
        #expect(abs(total + 700) < 0.01)

        let credits = (try? modelContext.fetch(FetchDescriptor<Credit>())) ?? []
        let normalized = try #require(credits.first(where: { $0.creditUniqueID == credit.creditUniqueID }))
        #expect(normalized.includeInTotal)
    }

    @Test("В Итого для кредита используется остаток долга, а не исходная сумма")
    func testCreditTotalUsesRemainingAmount() async throws {
        let modelContext = try createTestModelContext()
        let group = FinanceGroup(name: "Долги", colorHex: "#445566")
        modelContext.insert(group)

        let credit = Credit(
            name: "Кредит остаток",
            amount: 10_000,
            interestRate: 0,
            monthlyPayment: 500,
            startDate: Date(),
            termMonths: 24,
            currency: "RUB"
        )
        credit.remainingAmount = 2_500
        credit.includeInTotal = true
        modelContext.insert(credit)

        let link = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        link.group = group
        modelContext.insert(link)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        let total = await viewModel.calculateGroupTotal(group: group, in: "RUB")
        #expect(abs(total + 2_500) < 0.01)
        #expect(abs(total + credit.amount) > 0.01)
    }

    @Test("Пустая группа 'Без группы' скрывается из списка групп")
    func testLoadGroupsHidesEmptyUngroupedGroup() throws {
        let modelContext = try createTestModelContext()

        let ungroupedName = String(localized: "finances.group.ungrouped")
        let ungroupedGroup = FinanceGroup(name: ungroupedName, colorHex: "#3C4B5E")
        let regularGroup = FinanceGroup(name: "Основная", colorHex: "#112233")
        modelContext.insert(ungroupedGroup)
        modelContext.insert(regularGroup)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )

        viewModel.handle(.loadGroups)

        #expect(viewModel.state.groups.contains(where: { $0.name == "Основная" }))
        #expect(!viewModel.state.groups.contains(where: { $0.name == ungroupedName }))
    }

    @Test("Группа 'Без группы' скрывается, если в ней только архивные счета")
    func testVisibleGroupsHidesUngroupedWithArchivedAccounts() throws {
        let modelContext = try createTestModelContext()

        let ungroupedName = String(localized: "finances.group.ungrouped")
        let ungroupedGroup = FinanceGroup(name: ungroupedName, colorHex: "#3C4B5E")
        modelContext.insert(ungroupedGroup)

        let archivedCard = Card(
            name: "Архивная карта",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100
        )
        archivedCard.archivedAt = Date()
        modelContext.insert(archivedCard)

        let link = FinanceAccount(accountType: .card, accountID: archivedCard.cardUniqueID)
        link.group = ungroupedGroup
        modelContext.insert(link)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )

        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        let visibleGroups = viewModel.visibleGroupsForList()
        #expect(!visibleGroups.contains(where: { $0.name == ungroupedName }))
    }

    @Test("Добавление счета без выбранной группы создает и использует системную группу")
    func testAddAccountWithoutSelectedGroupUsesSystemUngrouped() throws {
        let modelContext = try createTestModelContext()
        let card = Card(
            name: "Новая карта",
            cardNumber: "1234",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 10
        )
        modelContext.insert(card)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )

        viewModel.handle(
            .addAccountToGroup(
                accountType: .card,
                accountID: card.cardUniqueID,
                group: nil
            )
        )

        let links = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        let createdLink = try #require(links.first(where: {
            $0.accountType == .card && $0.accountID == card.cardUniqueID
        }))
        let ungroupedName = String(localized: "finances.group.ungrouped")
        #expect(createdLink.group?.name == ungroupedName)
    }

    @Test("Удаление карты из финансов архивирует Card и удаляет FinanceAccount")
    func testRemoveCardAccountFromGroupArchivesUnderlyingAndDeletesLink() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let group = FinanceGroup(name: "Test Group")
        let card = Card(name: "Test Card", cardNumber: "1234", cardType: .debit, currency: "RUB", balance: 10)
        let accountLink = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        accountLink.group = group

        modelContext.insert(group)
        modelContext.insert(card)
        modelContext.insert(accountLink)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: currencyService,
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: false
        )
        _ = await waitForAsyncStatePropagation(until: { !viewModel.state.groups.isEmpty })

        let linksBefore = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(linksBefore.count == 1)

        viewModel.handle(.removeAccountFromGroup(accountLink))

        let linksAfter = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(linksAfter.isEmpty)

        let cards = try modelContext.fetch(FetchDescriptor<Card>())
        let updatedCard = try #require(cards.first)
        #expect(updatedCard.archivedAt != nil)
    }

    @Test("Удаление кредита из финансов архивирует Credit и удаляет FinanceAccount")
    func testRemoveCreditAccountFromGroupArchivesUnderlyingAndDeletesLink() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let group = FinanceGroup(name: "Test Group")
        let credit = Credit(
            name: "Test Credit",
            amount: 1000,
            interestRate: 10,
            monthlyPayment: 100,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        let accountLink = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        accountLink.group = group

        modelContext.insert(group)
        modelContext.insert(credit)
        modelContext.insert(accountLink)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: currencyService,
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: false
        )
        _ = await waitForAsyncStatePropagation(until: { !viewModel.state.groups.isEmpty })

        viewModel.handle(.removeAccountFromGroup(accountLink))

        let linksAfter = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(linksAfter.isEmpty)

        let credits = try modelContext.fetch(FetchDescriptor<Credit>())
        let updatedCredit = try #require(credits.first)
        #expect(updatedCredit.archivedAt != nil)
    }

    @Test("Удаление инвестиции из финансов архивирует Investment и удаляет FinanceAccount")
    func testRemoveInvestmentAccountFromGroupArchivesUnderlyingAndDeletesLink() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let group = FinanceGroup(name: "Test Group")
        let investment = Investment(name: "Test Investment", category: .other, amount: 50, currency: "USD")
        let accountLink = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        accountLink.group = group

        modelContext.insert(group)
        modelContext.insert(investment)
        modelContext.insert(accountLink)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: currencyService,
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: false
        )
        _ = await waitForAsyncStatePropagation(until: { !viewModel.state.groups.isEmpty })

        viewModel.handle(.removeAccountFromGroup(accountLink))

        let linksAfter = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(linksAfter.isEmpty)

        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        let updatedInvestment = try #require(investments.first)
        #expect(updatedInvestment.archivedAt != nil)
    }
}
