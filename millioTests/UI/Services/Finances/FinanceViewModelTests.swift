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
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    /// Получить чистый контекст (очищаем данные от предыдущих тестов)
    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        // Очищаем все данные от предыдущих тестов
        try context.delete(model: FinanceAccount.self)
        try context.delete(model: FinanceGroup.self)
        try context.delete(model: Card.self)
        try context.delete(model: Credit.self)
        try context.delete(model: Investment.self)
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
}
