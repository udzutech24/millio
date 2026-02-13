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
        // Ничего не делаем в тестах
    }
}

// MARK: - Тесты

@Suite(.serialized)
@MainActor
struct FinanceViewModelTests {

    /// Общий контейнер для всех тестов (SwiftData крашится при создании нескольких контейнеров)
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    /// Получить чистый контекст (очищаем данные от предыдущих тестов)
    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        // Очищаем все данные от предыдущих тестов
        try context.deleteAll(FinanceAccount.self)
        try context.deleteAll(FinanceGroup.self)
        try context.deleteAll(Card.self)
        try context.deleteAll(Credit.self)
        try context.deleteAll(Investment.self)
        try context.deleteAll(CashflowTransaction.self)
        try context.save()
        return context
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

    @Test("Предзагрузка курсов для всех валют группы работает корректно")
    func testPreloadRatesForAllCurrencies() async throws {
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
        #expect(subtitle?.contains("шт.") == true)
        #expect(subtitle?.contains("/шт.") == true)
        #expect(subtitle?.contains("500") == true)
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

        credit.remainingAmount = 500.0
        credit.updatedAt = Date()
        try modelContext.save()

        EventBus.shared.publish(FinanceEvent.creditsUpdated)
        
        var didUpdate = false
        for _ in 0..<100 {
            let groupTotal = viewModel.state.groupTotals[group.groupUniqueID] ?? 0.0
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
}
