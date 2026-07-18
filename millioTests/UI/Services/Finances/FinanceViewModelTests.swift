//
//  FinanceViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 23.01.2026.
//

import Foundation
import Testing
import SwiftData
import Combine
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
    var quotesBySymbol: [String: AssetSummary?]
    var errorsBySymbol: [String: Error]
    var latestPriceRequests: [String]
    var overrideFetchQuotes: [AssetSummary]?

    init(
        pricesBySymbol: [String: Double?] = [:],
        quotesBySymbol: [String: AssetSummary?] = [:],
        errorsBySymbol: [String: Error] = [:],
        overrideFetchQuotes: [AssetSummary]? = nil
    ) {
        self.pricesBySymbol = pricesBySymbol
        self.quotesBySymbol = quotesBySymbol
        self.errorsBySymbol = errorsBySymbol
        self.latestPriceRequests = []
        self.overrideFetchQuotes = overrideFetchQuotes
    }

    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] {
        []
    }

    func latestQuote(symbol: String, forceRefresh: Bool) async throws -> AssetSummary? {
        let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        latestPriceRequests.append(key)
        if let error = matchingValue(in: errorsBySymbol, for: key) {
            throw error
        }
        if let quote = matchingValue(in: quotesBySymbol, for: key) {
            return quote
        }
        guard let price = matchingValue(in: pricesBySymbol, for: key) ?? nil else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return AssetSummary(
            symbol: key,
            canonicalSymbol: key,
            providerSymbol: key,
            name: nil,
            exchange: nil,
            micCode: nil,
            currency: "USD",
            price: price,
            previousClose: nil,
            change: nil,
            percentChange: nil,
            isMarketOpen: nil,
            resolutionStatus: .fresh,
            updatedAt: formatter.string(from: Date()),
            isStale: false
        )
    }

    func allLatestPriceRequests() -> [String] {
        latestPriceRequests
    }

    func fetchQuotes(symbols: [String]) async throws -> [AssetSummary] {
        if let overrideFetchQuotes {
            for s in symbols {
                let key = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                latestPriceRequests.append(key)
            }
            return overrideFetchQuotes
        }

        var result: [AssetSummary] = []
        for s in symbols {
            let key = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            latestPriceRequests.append(key)
            if let error = matchingValue(in: errorsBySymbol, for: key) {
                throw error
            }
            if let quote = matchingValue(in: quotesBySymbol, for: key) {
                result.append(quote ?? AssetSummary(symbol: key, canonicalSymbol: key, providerSymbol: key, name: nil, exchange: nil, micCode: nil, currency: nil, price: nil, previousClose: nil, change: nil, percentChange: nil, isMarketOpen: nil, resolutionStatus: .notFound, updatedAt: "", isStale: false))
            } else if let price = matchingValue(in: pricesBySymbol, for: key) ?? nil {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                result.append(AssetSummary(symbol: key, canonicalSymbol: key, providerSymbol: key, name: nil, exchange: nil, micCode: nil, currency: "USD", price: price, previousClose: nil, change: nil, percentChange: nil, isMarketOpen: nil, resolutionStatus: .fresh, updatedAt: formatter.string(from: Date()), isStale: false))
            } else {
                result.append(AssetSummary(symbol: key, canonicalSymbol: key, providerSymbol: key, name: nil, exchange: nil, micCode: nil, currency: nil, price: nil, previousClose: nil, change: nil, percentChange: nil, isMarketOpen: nil, resolutionStatus: .notFound, updatedAt: "", isStale: false))
            }
        }
        return result
    }

    private func matchingValue<Value>(in values: [String: Value], for key: String) -> Value? {
        for candidate in aliasCandidates(for: key) {
            if let value = values[candidate] {
                return value
            }
        }
        return nil
    }

    private func aliasCandidates(for key: String) -> [String] {
        let canonical = MarketInstrumentIdentity.canonicalQuoteLookupKey(symbol: key, exchange: nil)
        let fallbacks = MarketInstrumentIdentity.fallbackQuoteLookupKeys(symbol: key, exchange: nil)
        var seen: Set<String> = []
        return ([key, canonical] + fallbacks)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { candidate in
                guard !candidate.isEmpty else { return false }
                return seen.insert(candidate).inserted
            }
    }
}

private func makeMarketQuote(
    symbol: String,
    canonicalSymbol: String? = nil,
    providerSymbol: String? = nil,
    exchange: String? = nil,
    currency: String? = "USD",
    price: Double?,
    resolutionStatus: MarketQuoteResolutionStatus,
    isStale: Bool = false
) -> AssetSummary {
    AssetSummary(
        symbol: symbol,
        canonicalSymbol: canonicalSymbol,
        providerSymbol: providerSymbol,
        name: nil,
        exchange: exchange,
        micCode: nil,
        currency: currency,
        price: price,
        previousClose: nil,
        change: nil,
        percentChange: nil,
        isMarketOpen: nil,
        resolutionStatus: resolutionStatus,
        updatedAt: "2026-03-16T00:00:00.000Z",
        isStale: isStale
    )
}

// MARK: - Тесты

@Suite(.serialized)
@MainActor
struct FinanceViewModelTests {
    // [Ф5c.7 contract] `Account`/`AccountGroup`/`AccountEvent`/`AccountDailySnapshot` добавлены —
    // без них `AccountGroup`/`Account`-фикстуры (портированные тесты reorder/ordering/mixed-store)
    // молча не сохраняются/не читаются (тип не зарегистрирован в Schema, не ошибка insert/save).
    private static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
        AssetCatalogItem.self,
        AssetProviderMapping.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        Account.self,
        AccountEvent.self,
        AccountGroup.self,
        AccountDailySnapshot.self,
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

    @Test("FinanceViewModel открывает редактор для выбранной группы")
    func testEditGroupShowsGroupEditorForSelectedGroup() throws {
        let modelContext = try createTestModelContext()
        let group = AccountGroup(name: "Накопления", colorHex: "#00AAFF")
        modelContext.insert(group)
        try modelContext.save()

        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)

        viewModel.handle(.editGroup(group))

        #expect(viewModel.state.showGroupEditor)
        #expect(viewModel.state.editingGroup?.groupUniqueID == group.groupUniqueID)
    }

    @Test("FinanceViewModel предвыбирает группу при открытии добавления счета")
    func testShowAddAccountSheetStoresSelectedGroup() throws {
        let modelContext = try createTestModelContext()
        let group = AccountGroup(name: "Инвестиции", colorHex: "#22CC88")
        modelContext.insert(group)
        try modelContext.save()

        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)

        viewModel.handle(.showAddAccountSheet(group))

        #expect(viewModel.state.showAddAccountSheet)
        #expect(viewModel.state.selectedGroupForAccount?.groupUniqueID == group.groupUniqueID)
    }

    @Test("FinanceViewModel мигрирует legacy market investments на assetID-first при загрузке")
    func testLoadAccountsMigratesMarketAssetIdentity() throws {
        let modelContext = try createTestModelContext()
        let investment = Investment(
            name: "Apple",
            investmentType: .positive,
            category: .stocks,
            amount: 1000,
            currency: "USD",
            includeInTotal: true,
            priority: .normal,
            isFavorite: true
        )
        investment.marketSymbol = "AAPL.US"
        investment.marketExchange = "US"
        investment.marketMICCode = "XNAS"
        investment.marketCurrency = "USD"
        investment.marketProviderRaw = "market-backend"
        modelContext.insert(investment)
        try modelContext.save()

        _ = FinanceViewModel(modelContext: modelContext)

        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        let assetCatalogItems = try modelContext.fetch(FetchDescriptor<AssetCatalogItem>())
        let providerMappings = try modelContext.fetch(FetchDescriptor<AssetProviderMapping>())

        #expect(investments.first?.assetID == "asset.stocks.aapl")
        #expect(assetCatalogItems.first?.assetID == "asset.stocks.aapl")
        #expect(providerMappings.first?.assetID == "asset.stocks.aapl")
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
        #expect(accounts[0].group?.name == L("finances.group.ungrouped"))
    }

    @Test("Кредиты без FinanceAccount привязываются к \"Без группы\" и уменьшают Итого")
    func testMissingCreditLinksAreRecoveredIntoUngroupedGroup() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let credit = Credit(
            name: "Test Loan",
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
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: currencyService,
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: false
        )

        let accounts = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        let groups = try modelContext.fetch(FetchDescriptor<FinanceGroup>())

        #expect(accounts.count == 1)
        #expect(groups.count == 1)
        #expect(accounts[0].accountType == .credit)
        #expect(accounts[0].accountID == credit.creditUniqueID)
        #expect(accounts[0].group?.name == L("finances.group.ungrouped"))

        // Пустая core-точка входа для calculateGroupTotal(AccountGroup) — легаси-хвост считается по имени.
        let coreUngroupedEntry = AccountGroup(name: groups[0].name)
        modelContext.insert(coreUngroupedEntry)
        try modelContext.save()
        let total = await viewModel.calculateGroupTotal(group: coreUngroupedEntry, in: "RUB")
        #expect(abs(total + 2_500) < 0.01)
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

    /// [Ф5c.7 contract] Портировано на core-фикстуры — `.moveGroup` теперь core-primary.
    @Test("FinanceViewModel сохраняет ручной порядок групп после перетаскивания")
    func testMoveGroupReordersVisibleGroups() throws {
        let modelContext = try createTestModelContext()

        let first = AccountGroup(name: "Первая", order: 0)
        let second = AccountGroup(name: "Вторая", order: 1)
        let third = AccountGroup(name: "Третья", order: 2)
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

    /// [Ф5c.7 contract] Портировано на core-фикстуры — `orderedAccounts`/`moveAccount` теперь
    /// core-primary (было: легаси `FinanceAccount`). Контракт сохранён: сортировка по сумме убыв.,
    /// ручной порядок после `.moveAccount` — [small, large, medium].
    @Test("FinanceViewModel по умолчанию сортирует счета в группе по сумме по убыванию и сохраняет ручной порядок")
    func testOrderedAccountsUseAmountThenManualOrder() throws {
        let modelContext = try createTestModelContext()

        let group = AccountGroup(name: "Основная", order: 0)
        modelContext.insert(group)

        let coreService = AccountsCoreService(modelContext: modelContext)
        let small = try coreService.createAccount(name: "Small", kind: .debitCard, currency: "RUB", openingBalance: 100, group: group)
        let large = try coreService.createAccount(name: "Large", kind: .debitCard, currency: "RUB", openingBalance: 300, group: group)
        let medium = try coreService.createAccount(name: "Medium debt", kind: .debitCard, currency: "RUB", openingBalance: 200, group: group)
        try modelContext.save()

        let viewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)
        viewModel.handle(.loadGroups)

        let loadedGroup = try #require(viewModel.state.groups.first)
        #expect(viewModel.orderedAccounts(for: loadedGroup).map(\.id) == [large.id, medium.id, small.id])

        viewModel.handle(
            .moveAccount(
                sourceAccountID: small.accountUniqueID,
                destinationIndex: 0,
                groupID: loadedGroup.groupUniqueID
            )
        )

        let reorderedGroup = try #require(viewModel.state.groups.first)
        #expect(reorderedGroup.usesManualAccountOrdering)
        #expect(viewModel.orderedAccounts(for: reorderedGroup).map(\.id) == [small.id, large.id, medium.id])
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
        let coreGroup655 = AccountGroup(name: "Тестовая группа") // пустая core-точка входа для calculateGroupTotal
        modelContext.insert(coreGroup655)

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
        let total = await viewModel.calculateGroupTotal(group: coreGroup655, in: "RUB")

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
        let coreGroup745 = AccountGroup(name: "Группа с разными валютами") // пустая core-точка входа для calculateGroupTotal
        modelContext.insert(coreGroup745)

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
        let total = await viewModel.calculateGroupTotal(group: coreGroup745, in: "USD")

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
        // 6b Фаза 2 (single-world): агрегат «Общий баланс» считается по ЯДРУ (`AccountsTotalsService`),
        // поэтому фикстура — core-счёт (USD), а не легаси-карта. Инвариант теста тот же: конвертация
        // не должна триггерить force-refresh курсов.
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let modelContext = container.mainContext

        let mockRateService = MockCurrencyRateService()
        mockRateService.setRate(from: "USD", to: "RUB", rate: 100.0)

        let coreService = AccountsCoreService(modelContext: modelContext)
        _ = try coreService.createAccount(name: "USD счёт", kind: .debitCard, currency: "USD", openingBalance: 10)

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: mockRateService,
            skipInitialLoad: true
        )
        // [Фикс гонки тоталов, 2026-07-18] Не вызываем handle(.loadGroups)/.loadAccounts() —
        // они планируют СВОИ fire-and-forget scheduleBackgroundTask-пересчёты (не нужны тесту:
        // `calculateTotalAmountAsync` сам читает счета из modelContext, не из state.accounts) и
        // конкурируют с прямым await ниже за generation-watermark, делая тест недетерминированным.
        await viewModel.calculateTotalAmountAsync()

        // 10 USD × 100 = 1000 RUB (валюта экрана по умолчанию — RUB).
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
        let coreGroup863 = AccountGroup(name: "Группа с неизвестной валютой") // пустая core-точка входа для calculateGroupTotal
        modelContext.insert(coreGroup863)

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
        let total = await viewModel.calculateGroupTotal(group: coreGroup863, in: "RUB")

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
        let coreGroup928 = AccountGroup(name: "Крипто группа") // пустая core-точка входа для calculateGroupTotal
        modelContext.insert(coreGroup928)

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

        let total = await viewModel.calculateGroupTotal(group: coreGroup928, in: "RUB")
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
            L("finances.investment.unit.shares_short"),
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

        viewModel.updateLegacyAccountAmount(account: account, newAmount: 3.5)

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

    @Test("Ручное обновление акций показывает мягкое cache-first сообщение без ticker dump")
    func testRefreshStockPricesShowsFailedSymbolsNotification() async throws {
        let modelContext = try createTestModelContext()

        let apple = Investment(
            name: "Apple",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        apple.marketSymbol = "AAPL"
        apple.marketQuantity = 2
        apple.lastKnownUnitPrice = 50
        modelContext.insert(apple)

        let tesla = Investment(
            name: "Tesla",
            investmentType: .positive,
            category: .stocks,
            amount: 200,
            currency: "USD"
        )
        tesla.marketSymbol = "TSLA"
        tesla.marketQuantity = 2
        tesla.lastKnownUnitPrice = 100
        modelContext.insert(tesla)

        try modelContext.save()

        let marketClient = MockMarketDataClient(
            pricesBySymbol: ["AAPL": 125],
            errorsBySymbol: ["TSLA": URLError(.timedOut)]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        #expect(viewModel.state.showRefreshIssue == false)
        #expect(viewModel.state.refreshIssueMessage == nil)
    }

    @Test("Обновление акций использует один request symbol для market identity")
    func testRefreshStockPricesUsesSingleRequestSymbol() async throws {
        let modelContext = try createTestModelContext()

        let spy = Investment(
            name: "SPY",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        spy.marketSymbol = "NYSE:SPY"
        spy.marketQuantity = 1
        spy.lastKnownUnitPrice = 100
        modelContext.insert(spy)
        try modelContext.save()

        let marketClient = MockMarketDataClient(
            quotesBySymbol: [
                "SPY": makeMarketQuote(
                    symbol: "SPY",
                    canonicalSymbol: "SPY",
                    providerSymbol: "SPY",
                    exchange: "NYSE",
                    price: 677.03,
                    resolutionStatus: .fresh
                )
            ]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        let requests = await marketClient.latestPriceRequests
        #expect(requests == ["SPY"])
        #expect(abs((spy.lastKnownUnitPrice ?? 0) - 677.03) < 0.0001)
        #expect(spy.marketQuoteLookupKey == "SPY")
        #expect(viewModel.state.showRefreshIssue == false)
    }

    @Test("Обновление акций сопоставляет quote по canonical keys даже если backend вернул другой alias")
    func testRefreshStockPricesMatchesReturnedCanonicalAlias() async throws {
        let modelContext = try createTestModelContext()

        let qqq = Investment(
            name: "QQQ",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        qqq.marketSymbol = "NASDAQ:QQQ"
        qqq.marketExchange = "NASDAQ"
        qqq.marketQuantity = 1
        qqq.lastKnownUnitPrice = 100
        modelContext.insert(qqq)
        try modelContext.save()

        let marketClient = MockMarketDataClient(
            overrideFetchQuotes: [
                makeMarketQuote(
                    symbol: "QQQ",
                    canonicalSymbol: "QQQ",
                    providerSymbol: "QQQ",
                    exchange: "NASDAQ",
                    price: 512.42,
                    resolutionStatus: .fresh
                )
            ]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        let requests = await marketClient.latestPriceRequests
        #expect(requests == ["QQQ"])
        #expect(abs((qqq.lastKnownUnitPrice ?? 0) - 512.42) < 0.0001)
        #expect(qqq.marketQuoteLookupKey == "QQQ")
        #expect(viewModel.state.showRefreshIssue == false)
    }


    @Test("Stale котировка обновляет цену без refresh ошибки независимо от request alias")
    func testRefreshStockPricesTreatsStaleQuoteAsDegradedSuccess() async throws {
        let modelContext = try createTestModelContext()

        let gld = Investment(
            name: "Gold",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        gld.marketSymbol = "GLD"
        gld.marketExchange = "NYSE"
        gld.marketQuantity = 1
        gld.lastKnownUnitPrice = 100
        modelContext.insert(gld)
        try modelContext.save()

        let marketClient = MockMarketDataClient(
            overrideFetchQuotes: [
                makeMarketQuote(
                    symbol: "GLD",
                    canonicalSymbol: "GLD",
                    providerSymbol: "GLD",
                    exchange: "NYSE",
                    price: 301.5,
                    resolutionStatus: .stale,
                    isStale: true
                )
            ]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        let requests = await marketClient.latestPriceRequests
        #expect(requests == ["GLD"] || requests == ["GLD.US"])
        #expect(abs((gld.lastKnownUnitPrice ?? 0) - 301.5) < 0.0001)
        #expect(gld.marketQuoteLookupKey == "GLD")
        #expect(viewModel.state.showRefreshIssue == false)
        #expect(viewModel.state.refreshIssueMessage == nil)
    }

    @Test("Provider error не показывает глобальный toast при частичном обновлении")
    func testRefreshStockPricesSoftensProviderErrors() async throws {
        let modelContext = try createTestModelContext()

        let pall = Investment(
            name: "PALL",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        pall.marketSymbol = "PALL.US"
        pall.marketQuantity = 1
        pall.lastKnownUnitPrice = 100
        modelContext.insert(pall)
        try modelContext.save()

        let marketClient = MockMarketDataClient(
            quotesBySymbol: [
                "PALL.US": makeMarketQuote(
                    symbol: "PALL.US",
                    canonicalSymbol: "PALL",
                    providerSymbol: "PALL",
                    exchange: "NYSE",
                    price: nil,
                    resolutionStatus: .providerError
                )
            ]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        #expect(viewModel.state.showRefreshIssue == false)
        #expect(viewModel.state.refreshIssueMessage == nil)
    }

    @Test("Ошибки авторизации обновления акций показывают human-safe сообщение без ticker dump")
    func testRefreshStockPricesSeparatesAuthErrors() async throws {
        let modelContext = try createTestModelContext()

        let qqq = Investment(
            name: "QQQ",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        qqq.marketSymbol = "QQQ"
        qqq.marketExchange = "NASDAQ"
        qqq.marketQuantity = 1
        qqq.lastKnownUnitPrice = 100
        modelContext.insert(qqq)
        try modelContext.save()

        let marketClient = MockMarketDataClient(
            errorsBySymbol: [
                "QQQ": MarketAPIClientError.unauthorized(requestId: "req-auth-1")
            ]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        let message = viewModel.state.refreshIssueMessage ?? ""
        let supportedMessages = Set([
            MarketDataErrorPresentation.message(for: .authError),
            MarketDataErrorPresentation.degradedRefreshMessage()
        ])

        #expect(viewModel.state.showRefreshIssue)
        #expect(supportedMessages.contains(message))
        #expect(message.contains("QQQ") == false)
    }

    @Test("Котировка без цены не показывает глобальный toast")
    func testRefreshStockPricesSoftensPriceUnavailable() async throws {
        let modelContext = try createTestModelContext()

        let sivr = Investment(
            name: "SIVR",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        sivr.marketSymbol = "NYSE:SIVR"
        sivr.marketQuantity = 1
        sivr.lastKnownUnitPrice = 100
        modelContext.insert(sivr)
        try modelContext.save()

        let marketClient = MockMarketDataClient(
            quotesBySymbol: [
                "NYSE:SIVR": makeMarketQuote(
                    symbol: "NYSE:SIVR",
                    canonicalSymbol: "SIVR",
                    providerSymbol: "SIVR",
                    exchange: "NYSE",
                    price: nil,
                    resolutionStatus: .fresh
                )
            ]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        #expect(viewModel.state.showRefreshIssue == false)
        #expect(viewModel.state.refreshIssueMessage == nil)
    }

    @Test("Повторный ручной refresh не запускает повторный quote request во время cooldown")
    func testRefreshStockPricesCooldownPreventsRepeatedRefreshRequests() async throws {
        let modelContext = try createTestModelContext()
        let spy = Investment(
            name: "SPY",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        spy.marketSymbol = "SPY.US"
        spy.marketQuoteLookupKey = "SPY"
        spy.marketQuantity = 1
        modelContext.insert(spy)
        try modelContext.save()

        var now = Date(timeIntervalSince1970: 1_000)
        let marketClient = MockMarketDataClient(
            quotesBySymbol: [
                "SPY": makeMarketQuote(
                    symbol: "SPY",
                    canonicalSymbol: "SPY",
                    providerSymbol: "SPY",
                    exchange: "NYSE",
                    price: 650,
                    resolutionStatus: .fresh
                )
            ]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: marketClient,
            now: { now },
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()
        await viewModel.refreshStockPrices()
        now = now.addingTimeInterval(16)
        await viewModel.refreshStockPrices()

        let requests = await marketClient.latestPriceRequests
        #expect(requests == ["SPY", "SPY"])
    }

    @Test("Обновление акций предпочитает provider mapping для assetID-first инструмента")
    func testRefreshStockPricesPrefersProviderMapping() async throws {
        let modelContext = try createTestModelContext()

        let apple = Investment(
            name: "Apple",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        apple.assetID = "asset.stocks.aapl"
        apple.marketSymbol = "AAPL"
        apple.marketExchange = "NASDAQ"
        apple.marketQuantity = 1
        apple.lastKnownUnitPrice = 100
        modelContext.insert(apple)

        let mapping = AssetProviderMapping(
            mappingID: "asset.stocks.aapl|market-backend|aapl.us|us",
            assetID: "asset.stocks.aapl",
            providerName: "market-backend",
            providerSymbol: "AAPL.US",
            providerExchangeCode: "US",
            providerInstrumentID: nil,
            status: .active,
            lastVerifiedAt: Date()
        )
        modelContext.insert(mapping)
        try modelContext.save()

        let marketClient = MockMarketDataClient(
            quotesBySymbol: [
                "AAPL.US": makeMarketQuote(
                    symbol: "AAPL.US",
                    canonicalSymbol: "AAPL",
                    providerSymbol: "AAPL",
                    exchange: "NASDAQ",
                    price: 215.0,
                    resolutionStatus: .fresh
                )
            ]
        )
        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockInvestmentCurrencyService(),
            marketDataClient: marketClient,
            skipInitialLoad: true
        )
        viewModel.handle(.loadAccounts)

        await viewModel.refreshStockPrices()

        let requests = await marketClient.allLatestPriceRequests()
        #expect(requests.first == "AAPL.US")
        #expect(abs((apple.lastKnownUnitPrice ?? 0) - 215.0) < 0.0001)
        #expect(apple.marketQuoteLookupKey == "AAPL")
    }

    @Test("Загрузка финансов нормализует канонический ключ котировки для старых акций")
    func testLoadAccountsNormalizesMarketQuoteLookupKey() throws {
        let modelContext = try createTestModelContext()

        let qqq = Investment(
            name: "QQQ",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        qqq.marketSymbol = "NASDAQ:QQQ"
        qqq.marketExchange = "NASDAQ"
        qqq.marketQuoteLookupKey = nil
        modelContext.insert(qqq)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: true
        )

        viewModel.handle(.loadAccounts)

        #expect(qqq.marketQuoteLookupKey == "QQQ")
    }

    @Test("Загрузка финансов не перезаписывает уже сохраненный quote lookup key legacy alias-ом")
    func testLoadAccountsPreservesExistingMarketQuoteLookupKey() throws {
        let modelContext = try createTestModelContext()

        let spy = Investment(
            name: "SPY",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        spy.marketSymbol = "SPY.US"
        spy.marketQuoteLookupKey = "SPY"
        modelContext.insert(spy)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: true
        )

        viewModel.handle(.loadAccounts)

        #expect(spy.marketQuoteLookupKey == "SPY")
    }

    @Test("Загрузка финансов не канонизирует provider-style US symbol до первого успешного refresh")
    func testLoadAccountsKeepsProviderStyleUSSymbolWithoutStoredLookupKey() throws {
        let modelContext = try createTestModelContext()

        let gld = Investment(
            name: "Gold",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        gld.marketSymbol = "GLD.US"
        gld.marketExchange = nil
        gld.marketQuoteLookupKey = nil
        modelContext.insert(gld)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            marketDataClient: MockMarketDataClient(),
            skipInitialLoad: true
        )

        viewModel.handle(.loadAccounts)

        #expect(gld.marketQuoteLookupKey == nil)
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
        var didPublishCardsUpdated = false
        let subscriptionID = EventBus.shared.subscribe { event in
            switch event {
            case FinanceEvent.transactionsUpdated:
                didPublishTransactionsUpdated = true
            case FinanceEvent.cardsUpdated:
                didPublishCardsUpdated = true
            default:
                break
            }
        }
        defer { EventBus.shared.unsubscribe(subscriptionID) }

        viewModel.updateLegacyCreditCardQuickFields(account: account, creditLimit: 12_000, debt: 4_500)

        #expect(abs((card.creditLimit ?? 0) - 12_000) < 0.01)
        #expect(abs(card.balance - 7_500) < 0.01)
        #expect(didPublishTransactionsUpdated)
        #expect(didPublishCardsUpdated)

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = try modelContext.fetch(descriptor)
        #expect(transactions.count == 1)

        guard let transaction = transactions.first else { return }
        #expect(transaction.transactionType == .creditDebtAdjustment)
        #expect(abs(transaction.amount + 1_500) < 0.01)
        #expect(transaction.cardID == card.cardUniqueID)
    }

    @Test("Быстрое редактирование лимита кредитной карты публикует обновление карты даже без транзакции")
    func testQuickEditCreditCardFieldsPublishesCardsUpdatedWithoutDebtChange() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Карты", colorHex: "#22AAFF")
        modelContext.insert(group)

        let card = Card(
            name: "Кредитка",
            cardNumber: "5678",
            bank: .tinkoff,
            cardType: .credit,
            currency: "RUB",
            balance: 560_000,
            creditLimit: 560_000
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
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        var didPublishCardsUpdated = false
        var didPublishTransactionsUpdated = false
        let subscriptionID = EventBus.shared.subscribe { event in
            switch event {
            case FinanceEvent.cardsUpdated:
                didPublishCardsUpdated = true
            case FinanceEvent.transactionsUpdated:
                didPublishTransactionsUpdated = true
            default:
                break
            }
        }
        defer { EventBus.shared.unsubscribe(subscriptionID) }

        viewModel.updateLegacyCreditCardQuickFields(account: account, creditLimit: 700_000, debt: 0)

        #expect(abs((card.creditLimit ?? 0) - 700_000) < 0.01)
        #expect(abs(card.balance - 700_000) < 0.01)
        #expect(didPublishCardsUpdated)
        #expect(!didPublishTransactionsUpdated)

        let transactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(transactions.isEmpty)
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

    @Test("Для кредитной карты в списке показывается задолженность, а остаток лимита доступен отдельно")
    func testCreditCardAccountInfoUsesDebtForPrimaryAmount() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Карты", colorHex: "#22AAFF")
        modelContext.insert(group)

        let card = Card(
            name: "T-Bank Кредитная",
            cardNumber: "8888",
            bank: .tinkoff,
            cardType: .credit,
            currency: "RUB",
            balance: 213_641,
            creditLimit: 560_000
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

        let info = viewModel.getAccountInfo(account: account)
        let debtInfo = viewModel.getCreditCardDebt(account: account)

        #expect(info != nil)
        #expect(abs((info?.amount ?? 0) - 346_359) < 0.01)
        #expect(info?.isCreditCardDebt == true)
        #expect(abs((debtInfo?.amount ?? 0) - 346_359) < 0.01)
        #expect(debtInfo?.currency == "RUB")
    }

    @Test("FinanceViewModel для дубликатов карты использует самую новую запись")
    func testFinanceViewModelUsesNewestDuplicateCardForAccountInfo() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Карты", colorHex: "#22AAFF")
        modelContext.insert(group)

        let sharedID = "DUPLICATE-CREDIT-CARD-ID"

        let stale = Card(
            name: "T-Bank Кредитная",
            cardNumber: "1111",
            bank: .tinkoff,
            cardType: .credit,
            currency: "RUB",
            balance: 560_000,
            creditLimit: 560_000
        )
        stale.uniqueID = sharedID
        stale.updatedAt = Date(timeIntervalSince1970: 1)

        let fresh = Card(
            name: "T-Bank Кредитная",
            cardNumber: "1111",
            bank: .tinkoff,
            cardType: .credit,
            currency: "RUB",
            balance: 213_641,
            creditLimit: 560_000
        )
        fresh.uniqueID = sharedID
        fresh.updatedAt = Date(timeIntervalSince1970: 2)

        modelContext.insert(stale)
        modelContext.insert(fresh)

        let account = FinanceAccount(accountType: .card, accountID: sharedID)
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
        let limitInfo = viewModel.getCreditCardLimitRemaining(account: account)
        let debtInfo = viewModel.getCreditCardDebt(account: account)

        #expect(abs((info?.amount ?? 0) - 346_359) < 0.01)
        #expect(abs((limitInfo?.amount ?? 0) - 213_641) < 0.01)
        #expect(abs((debtInfo?.amount ?? 0) - 346_359) < 0.01)
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

    @Test("Дубликаты FinanceAccount для одной карты удаляются и не удваивают итоги")
    func testCleanupDeduplicatesFinanceAccountLinksForSingleCard() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let primaryGroup = FinanceGroup(name: "Основная", colorHex: "#123456")
        let staleGroup = FinanceGroup(name: L("finances.group.ungrouped"), colorHex: "#654321")
        modelContext.insert(primaryGroup)
        modelContext.insert(staleGroup)
        // Пустая core-точка входа — `refreshGroupTotalsAndAmounts`/`groupTotals` теперь итерируют
        // `state.groups` (core primary), легаси-сумма считается fallback'ом по имени.
        let corePrimaryGroup = AccountGroup(name: "Основная")
        modelContext.insert(corePrimaryGroup)

        let card = Card(
            name: "Карта",
            cardNumber: "9999",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
        )
        modelContext.insert(card)

        let staleLink = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        staleLink.group = staleGroup
        staleLink.updatedAt = Date(timeIntervalSince1970: 1)
        modelContext.insert(staleLink)

        let currentLink = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        currentLink.group = primaryGroup
        currentLink.updatedAt = Date(timeIntervalSince1970: 2)
        modelContext.insert(currentLink)

        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: currencyService,
            skipInitialLoad: true
        )

        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        // 6b Фаза 2: агрегат `state.totalAmount` считается по ЯДРУ (single-world), поэтому легаси-
        // фикстура в него не входит. Дедуп проверяем по per-group сумме (`groupTotals`, бывший
        // легаси+core-микс) и по числу junction'ов — это и есть цель теста.
        let didPropagate = await waitForAsyncStatePropagation {
            viewModel.state.groupTotals[corePrimaryGroup.groupUniqueID] == 1_000
        }

        #expect(didPropagate)

        let accounts = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(accounts.count == 1)
        #expect(accounts.first?.group?.groupUniqueID == primaryGroup.groupUniqueID)
        #expect(viewModel.state.groupTotals[corePrimaryGroup.groupUniqueID] == 1_000)
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
        // Пустая core-точка входа — `groupTotals` теперь считается по `state.groups` (core primary).
        let coreGroup = AccountGroup(name: "Группа")
        modelContext.insert(coreGroup)

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
        let trackedGroupID = coreGroup.groupUniqueID

        credit.remainingAmount = 500.0
        credit.updatedAt = Date()
        try modelContext.save()

        EventBus.shared.publish(FinanceEvent.creditsUpdated)
        
        // 6b Фаза 2: проверяем пересчёт per-group суммы (`groupTotals`) — это и есть предмет теста.
        // Агрегат `state.totalAmount` теперь считается по ЯДРУ (single-world) и легаси-кредит в него
        // не входит, поэтому из условия он убран.
        var didUpdate = false
        for _ in 0..<100 {
            let groupTotal = viewModel.state.groupTotals[trackedGroupID] ?? 0.0
            if abs(groupTotal + 500.0) < 0.01 {
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

        viewModel.deleteLegacyAccountPermanently(account)

        #expect(didPublish, "При удалении карты должно публиковаться событие обновления списка карт")
    }

    @Test("Удаление группы архивирует счета и сохраняет links в системной группе")
    func testDeleteGroupArchivesAccountsAndPreservesLinksInUngroupedGroup() throws {
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

        // [Ф5c.7 contract] Легаси-группа не входит в `state.groups` (теперь `[AccountGroup]`) —
        // легаси-путь удаления (архивирует underlying, invariant 5) дергается напрямую.
        viewModel.deleteLegacyGroup(group)

        let groups = (try? modelContext.fetch(FetchDescriptor<FinanceGroup>())) ?? []
        #expect(!groups.contains { $0.groupUniqueID == group.groupUniqueID })

        let ungroupedGroup = try #require(groups.first { $0.name == FinanceSystemGroups.ungroupedName })

        let links = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        #expect(links.count == 3)
        #expect(links.allSatisfy { $0.group?.groupUniqueID == ungroupedGroup.groupUniqueID })

        let cards = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        let credits = (try? modelContext.fetch(FetchDescriptor<Credit>())) ?? []
        let investments = (try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []

        let updatedCard = cards.first { $0.cardUniqueID == card.cardUniqueID }
        let updatedCredit = credits.first { $0.creditUniqueID == credit.creditUniqueID }
        let updatedInvestment = investments.first { $0.investmentUniqueID == investment.investmentUniqueID }

        #expect(updatedCard?.archivedAt != nil)
        #expect(updatedCredit?.archivedAt != nil)
        #expect(updatedInvestment?.archivedAt != nil)
        #expect(viewModel.visibleGroupsForList().isEmpty)
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

        // [Ф5c.7 contract] Легаси-группа не входит в `state.groups` (теперь `[AccountGroup]`) —
        // легаси-путь восстановления (invariant 5) дергается напрямую.
        viewModel.restoreLegacyArchivedAccountToGroup(
            accountType: .card,
            accountID: card.cardUniqueID,
            group: group
        )

        let cardsAfterRestore = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        let restoredCard = try #require(cardsAfterRestore.first { $0.cardUniqueID == card.cardUniqueID })
        #expect(restoredCard.archivedAt == nil)

        let linksAfterRestore = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        let link = try #require(linksAfterRestore.first { $0.accountType == .card && $0.accountID == card.cardUniqueID })

        viewModel.removeLegacyAccountFromGroup(link)

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
        let coreGroup2455 = AccountGroup(name: "Кредиты") // пустая core-точка входа для calculateGroupTotal
        modelContext.insert(coreGroup2455)

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

        let total = await viewModel.calculateGroupTotal(group: coreGroup2455, in: "RUB")
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
        let coreGroup2495 = AccountGroup(name: "Долги") // пустая core-точка входа для calculateGroupTotal
        modelContext.insert(coreGroup2495)

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

        let total = await viewModel.calculateGroupTotal(group: coreGroup2495, in: "RUB")
        #expect(abs(total + 2_500) < 0.01)
        #expect(abs(total + credit.amount) > 0.01)
    }

    @Test("Пустая группа 'Без группы' скрывается из списка групп")
    func testLoadGroupsHidesEmptyUngroupedGroup() throws {
        let modelContext = try createTestModelContext()

        let ungroupedName = L("finances.group.ungrouped")
        let ungroupedGroup = FinanceGroup(name: ungroupedName, colorHex: "#3C4B5E")
        let regularGroup = FinanceGroup(name: "Основная", colorHex: "#112233")
        modelContext.insert(ungroupedGroup)
        modelContext.insert(regularGroup)
        // Core-версия обычной группы — `state.groups` теперь core primary (легаси-Ungrouped
        // структурно исключён из core, поэтому вторая проверка ниже верна по построению).
        let coreRegularGroup = AccountGroup(name: "Основная")
        modelContext.insert(coreRegularGroup)
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

        let ungroupedName = L("finances.group.ungrouped")
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

        viewModel.addLegacyAccountToGroup(
            accountType: .card,
            accountID: card.cardUniqueID,
            group: nil
        )

        let links = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        let createdLink = try #require(links.first(where: {
            $0.accountType == .card && $0.accountID == card.cardUniqueID
        }))
        let ungroupedName = L("finances.group.ungrouped")
        #expect(createdLink.group?.name == ungroupedName)
    }

    @Test("Удаление карты из финансов архивирует Card и сохраняет FinanceAccount для истории")
    func testRemoveCardAccountFromGroupArchivesUnderlyingAndKeepsLink() async throws {
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

        viewModel.removeLegacyAccountFromGroup(accountLink)

        let linksAfter = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(linksAfter.count == 1)
        #expect(linksAfter.first?.accountID == card.cardUniqueID)

        let cards = try modelContext.fetch(FetchDescriptor<Card>())
        let updatedCard = try #require(cards.first)
        #expect(updatedCard.archivedAt != nil)
    }

    @Test("Удаление кредита из финансов архивирует Credit и сохраняет FinanceAccount для истории")
    func testRemoveCreditAccountFromGroupArchivesUnderlyingAndKeepsLink() async throws {
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

        viewModel.removeLegacyAccountFromGroup(accountLink)

        let linksAfter = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(linksAfter.count == 1)
        #expect(linksAfter.first?.accountID == credit.creditUniqueID)

        let credits = try modelContext.fetch(FetchDescriptor<Credit>())
        let updatedCredit = try #require(credits.first)
        #expect(updatedCredit.archivedAt != nil)
    }

    @Test("Удаление инвестиции из финансов архивирует Investment и сохраняет FinanceAccount для истории")
    func testRemoveInvestmentAccountFromGroupArchivesUnderlyingAndKeepsLink() async throws {
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

        viewModel.removeLegacyAccountFromGroup(accountLink)

        let linksAfter = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        #expect(linksAfter.count == 1)
        #expect(linksAfter.first?.accountID == investment.investmentUniqueID)

        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        let updatedInvestment = try #require(investments.first)
        #expect(updatedInvestment.archivedAt != nil)
    }

    // MARK: - Track D1 (2026-07-04): удаление актива не обновляло список/тотал без перезапуска

    @Test("Track D1: removeAccountFromGroup сразу скрывает актив из списка и уменьшает тотал группы")
    func testRemoveAccountFromGroupHidesFromListAndTotalWithoutRestart() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let group = FinanceGroup(name: "Test Group")
        let coreGroupEntry = AccountGroup(name: "Test Group") // пустая точка входа для calculateGroupTotal(AccountGroup)
        let investment = Investment(name: "Актив на удаление", category: .other, amount: 500, currency: "RUB")
        let accountLink = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        accountLink.group = group

        modelContext.insert(group)
        modelContext.insert(coreGroupEntry)
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

        // До удаления актив виден и учтён в тотале группы.
        #expect(viewModel.getAccountInfo(account: accountLink) != nil)
        let totalBefore = await viewModel.calculateGroupTotal(group: coreGroupEntry, in: "RUB")
        #expect(totalBefore == 500.0)

        viewModel.removeLegacyAccountFromGroup(accountLink)

        // Регрессия Track D1: до фикса investmentByID не пересобирался здесь (только в
        // addAccountToGroup/restoreArchivedAccountToGroup) — getAccountInfo продолжал находить
        // архивированный актив по устаревшему кэшу, и он «висел» в списке и тотале до перезапуска.
        #expect(
            viewModel.getAccountInfo(account: accountLink) == nil,
            "После removeAccountFromGroup актив должен сразу пропасть из списка без повторного loadAccounts"
        )
        let totalAfter = await viewModel.calculateGroupTotal(group: coreGroupEntry, in: "RUB")
        #expect(totalAfter == 0.0, "После removeAccountFromGroup тотал группы должен сразу исключить архивированный актив")
    }

    @Test("Track D1: deleteAccountPermanently сразу скрывает актив из списка и уменьшает тотал группы")
    func testDeleteAccountPermanentlyHidesFromListAndTotalWithoutRestart() async throws {
        let modelContext = try createTestModelContext()
        let currencyService = MockCurrencyRateService()

        let group = FinanceGroup(name: "Test Group")
        let coreGroupEntry = AccountGroup(name: "Test Group") // пустая точка входа для calculateGroupTotal(AccountGroup)
        let investment = Investment(name: "Актив на полное удаление", category: .other, amount: 300, currency: "RUB")
        let accountLink = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        accountLink.group = group

        modelContext.insert(group)
        modelContext.insert(coreGroupEntry)
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

        #expect(viewModel.getAccountInfo(account: accountLink) != nil)
        let totalBefore = await viewModel.calculateGroupTotal(group: coreGroupEntry, in: "RUB")
        #expect(totalBefore == 300.0)

        viewModel.deleteLegacyAccountPermanently(accountLink)

        #expect(
            viewModel.getAccountInfo(account: accountLink) == nil,
            "После deleteAccountPermanently актив должен сразу пропасть из списка без повторного loadAccounts"
        )
        let totalAfter = await viewModel.calculateGroupTotal(group: coreGroupEntry, in: "RUB")
        #expect(totalAfter == 0.0, "После deleteAccountPermanently тотал группы должен сразу исключить архивированный актив")
    }

    // MARK: - cardByID staleness fix (2026-05-17)

    @Test("cardByID обновляется после повторного loadAccounts — баг stale balance после QuickAudit")
    func testCardByIDReflectsUpdatedBalanceAfterSecondLoadAccounts() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Карты", colorHex: "#22AAFF")
        modelContext.insert(group)

        let card = Card(
            name: "Сбербанк Дебетовая",
            cardNumber: "1234",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 500
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

        // Симуляция save из AccountQuickAuditView
        card.balance = 800
        try modelContext.save()

        // Симуляция onCommitted → loadAccounts
        viewModel.handle(.loadAccounts)

        #expect(viewModel.cardByID[card.cardUniqueID]?.balance == 800)

        let info = viewModel.getAccountInfo(account: account)
        #expect(abs((info?.amount ?? 0) - 800) < 0.01)
        #expect(info?.isCreditCardDebt == false)
    }

    @Test("getAccountInfo возвращает обновлённый долг кредитной карты после повторного loadAccounts")
    func testCreditCardDebtAmountUpdatesAfterLoadAccounts() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Кредитки", colorHex: "#FF3344")
        modelContext.insert(group)

        // balance = остаток доступного лимита; долг = creditLimit - balance
        let card = Card(
            name: "Альфа Кредитная",
            cardNumber: "5678",
            bank: .other,
            cardType: .credit,
            currency: "RUB",
            balance: 45_000,
            creditLimit: 100_000
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

        // Начальный долг: 100_000 - 45_000 = 55_000
        let infoInitial = viewModel.getAccountInfo(account: account)
        #expect(abs((infoInitial?.amount ?? 0) - 55_000) < 0.01)
        #expect(infoInitial?.isCreditCardDebt == true)

        // AQA записывает новый долг 70_000 → balance = limit - debt = 100_000 - 70_000 = 30_000
        card.balance = 30_000
        try modelContext.save()
        viewModel.handle(.loadAccounts)

        let infoAfter = viewModel.getAccountInfo(account: account)
        #expect(abs((infoAfter?.amount ?? 0) - 70_000) < 0.01)
        #expect(infoAfter?.isCreditCardDebt == true)
        #expect(viewModel.cardByID[card.cardUniqueID]?.balance == 30_000)
    }

    @Test("@Published cardByID — objectWillChange стреляет после loadAccounts")
    func testCardByIDPublishedFiresObjectWillChange() throws {
        let modelContext = try createTestModelContext()

        let group = FinanceGroup(name: "Карты", colorHex: "#22AAFF")
        modelContext.insert(group)

        let card = Card(
            name: "Тинькофф",
            cardNumber: "9999",
            bank: .tinkoff,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
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

        var changeCount = 0
        var cancellables: Set<AnyCancellable> = []
        viewModel.objectWillChange.sink { _ in changeCount += 1 }.store(in: &cancellables)

        card.balance = 1_500
        try modelContext.save()
        viewModel.handle(.loadAccounts)

        #expect(changeCount > 0)
    }

    // MARK: - Синхронизация балансов

    @Test("updateAccountAmount обновляет getAccountInfo без дополнительного loadAccounts")
    func testUpdateAccountAmountReflectsInGetAccountInfo() throws {
        let modelContext = try createTestModelContext()
        EventBus.shared.removeAllSubscribers()

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        modelContext.insert(group)

        let card = Card(
            name: "Тестовая карта",
            cardNumber: "0001",
            bank: .sberbank,
            cardType: .debit,
            currency: "USD",
            balance: 1_311_111.0
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

        let infoBefore = viewModel.getAccountInfo(account: account)
        #expect(infoBefore?.amount == 1_311_111.0, "Исходный баланс должен быть 1 311 111")

        viewModel.updateLegacyAccountAmount(account: account, newAmount: 13_111.0)

        let infoAfter = viewModel.getAccountInfo(account: account)
        #expect(infoAfter?.amount == 13_111.0, "После updateAccountAmount getAccountInfo должен вернуть новый баланс без дополнительного loadAccounts")
    }

    @Test("addAccountToGroup сразу обновляет кэш счетов и показывает новый счёт в списке")
    func testAddAccountToGroupReloadsAccountsCacheAndShowsNewAccountImmediately() throws {
        let modelContext = try createTestModelContext()
        EventBus.shared.removeAllSubscribers()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        #expect(viewModel.visibleGroupsForList().isEmpty)

        let card = Card(
            name: "Новая карта",
            cardNumber: "0004",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 42_000.0
        )
        modelContext.insert(card)
        try modelContext.save()

        // [Ф5c.7 contract] `.addAccountToGroup` теперь core-типизирован — легаси-путь напрямую.
        viewModel.addLegacyAccountToGroup(
            accountType: .card,
            accountID: card.cardUniqueID,
            group: nil
        )

        // `visibleGroupsForList()` теперь core-only и структурно НЕ содержит Ungrouped (канон
        // `group == nil`) — проверяем легаси-привязку напрямую через junction.
        let link = try #require(viewModel.legacyAccountsMatchingGroupName(L("finances.group.ungrouped")).first)
        #expect(link.accountID == card.cardUniqueID)
        #expect(viewModel.getAccountInfo(account: link)?.amount == 42_000.0)
    }

    @Test("FinanceAccountService.addAccountToGroup обновляет кэш перед группами")
    func testAddAccountToGroupReloadsAccountsBeforeGroups() throws {
        let modelContext = try createTestModelContext()
        var callbackOrder: [String] = []
        var loadedCardIDs: Set<String> = []

        let group = FinanceGroup(name: "Сервисная группа", colorHex: "#FFFFFF")
        let card = Card(
            name: "Сервисная карта",
            cardNumber: "0005",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 15_000.0
        )
        modelContext.insert(group)
        modelContext.insert(card)
        try modelContext.save()

        var service: FinanceAccountService!
        service = FinanceAccountService(
            modelContext: modelContext,
            ungroupedGroupName: L("finances.group.ungrouped"),
            groupsProvider: { [group] },
            nextOrderProvider: { _ in 0 },
            onAccountsLoaded: { payload in
                loadedCardIDs = Set(payload.availableCards.map(\.cardUniqueID))
                callbackOrder.append("loadAccounts")
            },
            onCachesRebuilt: { _ in },
            onLoadAccounts: {
                service.loadAccounts()
            },
            onLoadGroups: {
                callbackOrder.append("loadGroups")
            },
            onUpdateUnattachedItems: {},
            onCalculateTotal: {
                callbackOrder.append("calculateTotal")
            },
            onScheduleGroupTotalRefresh: { _ in
                callbackOrder.append("scheduleRefresh")
            },
            onDismissAddAccountSheet: {
                callbackOrder.append("dismiss")
            }
        )

        service.addAccountToGroup(accountType: .card, accountID: card.cardUniqueID, group: group)

        #expect(loadedCardIDs.contains(card.cardUniqueID))
        #expect(callbackOrder.prefix(2) == ["loadAccounts", "loadGroups"])
    }

    @Test("EventBus cardsUpdated вызывает loadAccounts и обновляет getAccountInfo")
    func testEventBusCardsUpdatedTriggersLoadAccountsAndUpdatesInfo() throws {
        let modelContext = try createTestModelContext()
        EventBus.shared.removeAllSubscribers()

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        modelContext.insert(group)

        let card = Card(
            name: "Карта EventBus",
            cardNumber: "0002",
            bank: .tinkoff,
            cardType: .debit,
            currency: "RUB",
            balance: 500.0
        )
        modelContext.insert(card)

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        modelContext.insert(account)
        try modelContext.save()

        let viewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: false
        )

        let infoBefore = viewModel.getAccountInfo(account: account)
        #expect(infoBefore?.amount == 500.0)

        // Мутируем баланс напрямую (имитация внешнего сохранения, например из AQA)
        card.balance = 999.0
        try modelContext.save()
        EventBus.shared.publish(FinanceEvent.cardsUpdated)

        let infoAfter = viewModel.getAccountInfo(account: account)
        #expect(infoAfter?.amount == 999.0, "После EventBus.cardsUpdated getAccountInfo должен вернуть новый баланс")
    }

    @Test("Прямое изменение balance через SwiftData и loadAccounts синхронизирует список (путь AQA)")
    func testDirectSaveAndLoadAccountsSyncsBalance() throws {
        let modelContext = try createTestModelContext()
        EventBus.shared.removeAllSubscribers()

        let group = FinanceGroup(name: "Аудит", colorHex: "#FFFFFF")
        modelContext.insert(group)

        let card = Card(
            name: "AQA Карта",
            cardNumber: "0003",
            bank: .vtb,
            cardType: .debit,
            currency: "USD",
            balance: 10_000.0
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

        // Имитируем applyBalance из AccountQuickAuditView
        card.balance = 1_234.0
        try modelContext.save()
        // AQA публикует событие — ViewModel должен перечитать
        EventBus.shared.publish(FinanceEvent.cardsUpdated)

        let info = viewModel.getAccountInfo(account: account)
        #expect(info?.amount == 1_234.0, "После AQA-стиля сохранения и EventBus список должен показывать новый баланс")
    }
}
