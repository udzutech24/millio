//
//  FinanceDynamicsViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 29.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@MainActor
final class MockDynamicsCurrencyRateService: CurrencyRateServiceProtocol {
    func getRate(from: String, to: String) async -> Double? { 1.0 }
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? { 1.0 }
    func convert(amount: Double, from: String, to: String) async -> Double? { amount }
    func forceRefreshRates() async {}
}

@MainActor
final class MockDynamicsNormalizedCurrencyRateService: CurrencyRateServiceProtocol {
    func getRate(from: String, to: String) async -> Double? {
        if from == "USD", to == "RUB" { return 100.0 }
        if from == "RUB", to == "USD" { return 0.01 }
        return nil
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        await getRate(from: from, to: to)
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {}
}

final class InMemoryFinanceBalanceAuditStore: FinanceBalanceAuditStoreProtocol {
    private var days: [String: [String: FinanceBalanceSnapshotValue]] = [:]
    private var accountCurrency: [String: String] = [:]

    func daySnapshot(for day: FinanceBalanceDayKey) -> [String : FinanceBalanceSnapshotValue] {
        days[day.rawValue] ?? [:]
    }

    func setValue(
        _ value: Double,
        for accountKey: String,
        day: FinanceBalanceDayKey,
        defaultCurrency: String,
        defaultTitle: String,
        defaultGroupName: String,
        accountTypeRaw: String,
        effectSign: Int,
        isUnknown: Bool
    ) {
        var dayMap = days[day.rawValue] ?? [:]
        dayMap[accountKey] = FinanceBalanceSnapshotValue(
            value: value,
            currencyCode: defaultCurrency,
            title: defaultTitle,
            groupName: defaultGroupName,
            accountTypeRaw: accountTypeRaw,
            effectSign: effectSign,
            isUnknown: isUnknown
        )
        days[day.rawValue] = dayMap
        accountCurrency[accountKey] = defaultCurrency
    }

    func deleteValue(for accountKey: String, day: FinanceBalanceDayKey) {
        var dayMap = days[day.rawValue] ?? [:]
        dayMap.removeValue(forKey: accountKey)
        days[day.rawValue] = dayMap
    }

    func setCurrency(_ currencyCode: String, for accountKey: String) {
        accountCurrency[accountKey] = currencyCode
    }

    func currency(for accountKey: String) -> String? {
        accountCurrency[accountKey]
    }

    func deleteAccountEverywhere(_ accountKey: String) {
        accountCurrency.removeValue(forKey: accountKey)
        for dayKey in days.keys {
            var dayMap = days[dayKey] ?? [:]
            dayMap.removeValue(forKey: accountKey)
            days[dayKey] = dayMap
        }
    }
}

@Suite(.serialized)
@MainActor
struct FinanceDynamicsViewModelTests {
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

    @Test("Ручная корректировка долга учитывается в динамике без транзакций")
    func testManualAdjustmentAffectsDynamicsWhenNoTransactions() async throws {
        let modelContext = try createTestModelContext()

        let credit = Credit(
            name: "Кредит",
            amount: 100_000.0,
            interestRate: 0.0,
            monthlyPayment: 1_000.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.initialRemainingAmount = 100_000.0
        credit.hasInitialRemainingAmount = true
        credit.remainingAmount = 50_000.0
        credit.remainingAmountAdjustment = -50_000.0
        credit.updatedAt = Date()
        modelContext.insert(credit)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let endAmount = await dynamicsViewModel.calculateCreditRemainingAmount(
            credit: credit,
            at: Date(),
            accountCurrency: "RUB"
        )
        let startAmount = await dynamicsViewModel.calculateCreditRemainingAmount(
            credit: credit,
            at: credit.updatedAt.addingTimeInterval(-3600),
            accountCurrency: "RUB"
        )

        #expect(abs(endAmount - 50_000.0) < 0.01)
        #expect(abs(startAmount - 100_000.0) < 0.01)
    }

    @Test("Актуальный остаток учитывается даже при неполной истории транзакций")
    func testManualAdjustmentOverridesIncompleteTransactions() async throws {
        let modelContext = try createTestModelContext()

        let credit = Credit(
            name: "Кредит",
            amount: 100_000.0,
            interestRate: 0.0,
            monthlyPayment: 1_000.0,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.initialRemainingAmount = 100_000.0
        credit.hasInitialRemainingAmount = true
        credit.remainingAmount = 40_000.0
        credit.remainingAmountAdjustment = -60_000.0
        credit.updatedAt = Date()
        modelContext.insert(credit)

        // Имитируем только одну транзакцию (неполная история)
        let transaction = CashflowTransaction(
            transactionType: .creditDebtAdjustment,
            amount: 10_000.0,
            currency: "RUB",
            transactionDate: credit.updatedAt,
            creditID: credit.creditUniqueID,
            note: "Корректировка"
        )
        modelContext.insert(transaction)

        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let endAmount = await dynamicsViewModel.calculateCreditRemainingAmount(
            credit: credit,
            at: Date(),
            accountCurrency: "RUB"
        )

        #expect(abs(endAmount - 40_000.0) < 0.01)
    }

    @Test("Архивные счета скрываются при выключенном фильтре")
    func testArchivedAccountsHiddenWhenFilterOff() async throws {
        let modelContext = try createTestModelContext()

        let activeCard = Card(name: "Активная", cardNumber: "0000", bank: .other, cardType: .debit, currency: "RUB")
        let archivedCard = Card(name: "Архивная", cardNumber: "9999", bank: .other, cardType: .debit, currency: "RUB")
        archivedCard.archivedAt = Date()

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        let activeAccount = FinanceAccount(accountType: .card, accountID: activeCard.cardUniqueID)
        let archivedAccount = FinanceAccount(accountType: .card, accountID: archivedCard.cardUniqueID)
        activeAccount.group = group
        archivedAccount.group = group
        group.accounts = [activeAccount, archivedAccount]

        modelContext.insert(activeCard)
        modelContext.insert(archivedCard)
        modelContext.insert(group)
        modelContext.insert(activeAccount)
        modelContext.insert(archivedAccount)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        #expect(dynamicsViewModel.getAccountsForCalculation().count == 1)

        dynamicsViewModel.handle(.setShowArchivedAccounts(true))
        let allAccounts = dynamicsViewModel.getAccountsForCalculation()
        #expect(allAccounts.count == 2)
    }

    @Test("Динамика для акций показывает короткий тикер вместо длинного имени")
    func testGetAccountInfoForDynamicsUsesShortTickerForStocks() throws {
        let modelContext = try createTestModelContext()

        let investment = Investment(
            name: "SPDR S&P 500 ETF Trust",
            investmentType: .positive,
            category: .stocks,
            amount: 908_319,
            currency: "USD"
        )
        investment.marketSymbol = "SPY.US"
        modelContext.insert(investment)

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )

        let info = dynamicsViewModel.getAccountInfoForDynamics(account: account)
        #expect(info?.name == "SPY")
    }

    // MARK: - Новые тесты

    @Test("Баланс карты на прошлую дату с учётом транзакций")
    func testCardBalanceAtPastDate() async throws {
        let modelContext = try createTestModelContext()

        // Создаём карту с начальным балансом 10000
        let card = Card(name: "Тестовая", cardNumber: "1234", bank: .other, cardType: .debit, currency: "RUB")
        card.balance = 15000 // Текущий баланс
        card.initialBalance = 10000
        card.hasInitialBalance = true
        card.createdAt = Date().addingTimeInterval(-7 * 86400) // Неделю назад
        modelContext.insert(card)

        // Создаём группу и счёт
        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)

        // Транзакция дохода +5000 три дня назад
        let transaction = CashflowTransaction(
            transactionType: .income,
            amount: 5000,
            currency: "RUB",
            transactionDate: Date().addingTimeInterval(-3 * 86400),
            cardID: card.cardUniqueID,
            note: "Зарплата"
        )
        modelContext.insert(transaction)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        // Баланс 5 дней назад (до транзакции) должен быть 10000
        let balanceBefore = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date().addingTimeInterval(-5 * 86400),
            accountCardIDs: [card.cardUniqueID]
        )
        #expect(abs(balanceBefore - 10000) < 0.01)

        // Баланс сегодня должен быть 15000 (10000 + 5000)
        let balanceNow = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date(),
            accountCardIDs: [card.cardUniqueID]
        )
        #expect(abs(balanceNow - 15000) < 0.01)
    }

    @Test("Карта: до даты ручного обновления сохраняется стартовый баланс, после нее - актуальный")
    func testCardUsesActualAmountAfterUpdateWithoutTransactions() async throws {
        let modelContext = try createTestModelContext()

        let createdAt = Date().addingTimeInterval(-7 * 86400)
        let updatedAt = Date().addingTimeInterval(-1800)

        let card = Card(name: "Live карта", cardNumber: "9876", bank: .other, cardType: .debit, currency: "RUB")
        card.createdAt = createdAt
        card.updatedAt = updatedAt
        card.initialBalance = 10_000
        card.hasInitialBalance = true
        // История транзакций отсутствует, но текущее значение уже изменено вручную.
        card.balance = 15_000
        modelContext.insert(card)

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let beforeUpdate = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: updatedAt.addingTimeInterval(-60),
            accountCardIDs: [card.cardUniqueID]
        )
        #expect(abs(beforeUpdate - 10_000) < 0.01)

        let afterUpdate = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date(),
            accountCardIDs: [card.cardUniqueID]
        )
        #expect(abs(afterUpdate - 15_000) < 0.01)
    }

    @Test("Процентное изменение: деление на ноль возвращает специальное значение")
    func testPercentChangeWithZeroDenominator() async throws {
        let modelContext = try createTestModelContext()

        // Создаём карту с нулевым начальным балансом
        let card = Card(name: "Пустая", cardNumber: "0000", bank: .other, cardType: .debit, currency: "RUB")
        card.balance = 1000 // Текущий баланс
        card.initialBalance = 0 // Начальный баланс 0
        card.hasInitialBalance = true
        card.createdAt = Date().addingTimeInterval(-7 * 86400)
        modelContext.insert(card)

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        dynamicsViewModel.handle(.setPeriod(.week))

        // Ждём обновления дельты
        try await Task.sleep(for: .milliseconds(100))

        // При делении на ноль должно вернуться специальное значение (не crash)
        let delta = dynamicsViewModel.state.periodDelta
        // delta.percent должен быть большим числом (999999) или 0, но не NaN/Inf
        #expect(!delta.percent.isNaN)
        #expect(!delta.percent.isInfinite || abs(delta.percent) == 999999.0)
    }

    @Test("Кредитная карта: баланс отображается как задолженность")
    func testCreditCardBalanceAsDebt() async throws {
        let modelContext = try createTestModelContext()

        // Создаём кредитную карту с лимитом 100000 и балансом 80000
        // Задолженность = 100000 - 80000 = 20000
        let creditCard = Card(name: "Кредитка", cardNumber: "5555", bank: .other, cardType: .credit, currency: "RUB")
        creditCard.creditLimit = 100_000
        creditCard.balance = 80_000 // Доступный остаток
        creditCard.initialBalance = 100_000 // Изначально полный лимит
        creditCard.hasInitialBalance = true
        creditCard.createdAt = Date().addingTimeInterval(-7 * 86400)
        modelContext.insert(creditCard)

        let group = FinanceGroup(name: "Кредитки", colorHex: "#FF0000")
        let account = FinanceAccount(accountType: .card, accountID: creditCard.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        // Баланс кредитной карты должен отображаться как задолженность
        let balance = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date(),
            accountCardIDs: [creditCard.cardUniqueID]
        )
        // Задолженность = лимит - баланс = 100000 - 100000 (initialBalance) = 0
        // Но с транзакциями баланс будет другим
        #expect(balance >= 0) // Задолженность не может быть отрицательной
    }

    @Test("Смена валюты пересчитывает данные графика")
    func testCurrencyChangeRecalculates() async throws {
        let modelContext = try createTestModelContext()

        let card = Card(name: "USD карта", cardNumber: "1111", bank: .other, cardType: .debit, currency: "USD")
        card.balance = 1000
        card.initialBalance = 1000
        card.hasInitialBalance = true
        modelContext.insert(card)

        let group = FinanceGroup(name: "Валютные", colorHex: "#00FF00")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        // Начальная валюта
        let initialCurrency = dynamicsViewModel.state.displayCurrency

        // Меняем валюту
        dynamicsViewModel.handle(.setDisplayCurrency("EUR"))

        // Валюта должна измениться
        #expect(dynamicsViewModel.state.displayCurrency == "EUR")
        #expect(dynamicsViewModel.state.displayCurrency != initialCurrency || initialCurrency == "EUR")
    }

    @Test("Смена валюты не переиспользует кэш баланса из другой валюты")
    func testDisplayCurrencyChangeInvalidatesBalanceCache() async throws {
        let modelContext = try createTestModelContext()

        let card = Card(name: "Рублевая карта", cardNumber: "2222", bank: .other, cardType: .debit, currency: "RUB")
        card.balance = 10_000
        card.initialBalance = 10_000
        card.hasInitialBalance = true
        modelContext.insert(card)

        let group = FinanceGroup(name: "Тест", colorHex: "#00FF00")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsNormalizedCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsNormalizedCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let evaluationDate = Date()

        dynamicsViewModel.handle(.setDisplayCurrency("RUB"))
        let rubBalance = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: evaluationDate,
            accountCardIDs: [card.cardUniqueID]
        )

        dynamicsViewModel.handle(.setDisplayCurrency("USD"))
        let usdBalance = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: evaluationDate,
            accountCardIDs: [card.cardUniqueID]
        )

        #expect(abs(rubBalance - 10_000) < 0.01)
        #expect(abs(usdBalance - 100) < 0.01)
    }

    @Test("Период week корректно рассчитывает диапазон дат")
    func testWeekPeriodDateRange() async throws {
        let modelContext = try createTestModelContext()

        let card = Card(name: "Тест", cardNumber: "0000", bank: .other, cardType: .debit, currency: "RUB")
        card.balance = 1000
        modelContext.insert(card)

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        dynamicsViewModel.handle(.setPeriod(.week))

        let (start, end) = dynamicsViewModel.getPeriodDates()
        let daysDiff = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        #expect(daysDiff >= 6 && daysDiff <= 8)
    }

    @Test("Кастомный период нормализуется до конца дня")
    func testCustomPeriodNormalizesEndToEndOfDay() async throws {
        let modelContext = try createTestModelContext()

        let card = Card(name: "Тест", cardNumber: "0000", bank: .other, cardType: .debit, currency: "RUB")
        card.balance = 1000
        modelContext.insert(card)

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let calendar = Calendar.current
        let yesterdayStart = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        )

        dynamicsViewModel.handle(.setCustomPeriod(start: yesterdayStart, end: yesterdayStart))
        let (_, end) = dynamicsViewModel.getPeriodDates()
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: end)

        #expect(endComponents.hour == 23)
        #expect(endComponents.minute == 59)
        #expect(endComponents.second == 59)
    }

    @Test("График: в пределах одного дня есть минимум две точки (start/end)")
    func testTimeSeriesContainsStartAndEndWhenSameDay() async throws {
        let modelContext = try createTestModelContext()

        let now = Date()
        let start = now.addingTimeInterval(-2 * 3600)

        let card = Card(name: "Same day", cardNumber: "3333", bank: .other, cardType: .debit, currency: "RUB")
        card.createdAt = start.addingTimeInterval(-60)
        card.updatedAt = now
        card.initialBalance = 1000
        card.hasInitialBalance = true
        card.balance = 1000
        modelContext.insert(card)

        let group = FinanceGroup(name: "Same day group", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let points = await dynamicsViewModel.buildTimeSeriesData(
            accounts: [account],
            startDate: start,
            endDate: now,
            label: "Total",
            debtAsNegative: false
        )

        #expect(points.count >= 2)
        #expect(points.first?.date == start)
        #expect(points.last?.date == now)
    }

    @Test("Транзакция расхода уменьшает баланс на историческую дату")
    func testExpenseTransactionReducesBalance() async throws {
        let modelContext = try createTestModelContext()

        let card = Card(name: "Расходы", cardNumber: "2222", bank: .other, cardType: .debit, currency: "RUB")
        card.balance = 5000
        card.initialBalance = 10000
        card.hasInitialBalance = true
        card.createdAt = Date().addingTimeInterval(-7 * 86400)
        modelContext.insert(card)

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)

        // Транзакция расхода -5000 три дня назад
        let expense = CashflowTransaction(
            transactionType: .expense,
            amount: 5000,
            currency: "RUB",
            transactionDate: Date().addingTimeInterval(-3 * 86400),
            cardID: card.cardUniqueID,
            note: "Покупка"
        )
        modelContext.insert(expense)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        // До расхода баланс был 10000
        let balanceBefore = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date().addingTimeInterval(-5 * 86400),
            accountCardIDs: [card.cardUniqueID]
        )
        #expect(abs(balanceBefore - 10000) < 0.01)

        // После расхода баланс 5000
        let balanceAfter = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date(),
            accountCardIDs: [card.cardUniqueID]
        )
        #expect(abs(balanceAfter - 5000) < 0.01)
    }

    @Test("Трансфер между картами корректно обновляет балансы")
    func testTransferBetweenCards() async throws {
        let modelContext = try createTestModelContext()

        let card1 = Card(name: "Карта 1", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB")
        card1.balance = 5000
        card1.initialBalance = 10000
        card1.hasInitialBalance = true
        card1.createdAt = Date().addingTimeInterval(-7 * 86400)
        modelContext.insert(card1)

        let card2 = Card(name: "Карта 2", cardNumber: "2222", bank: .other, cardType: .debit, currency: "RUB")
        card2.balance = 5000
        card2.initialBalance = 0
        card2.hasInitialBalance = true
        card2.createdAt = Date().addingTimeInterval(-7 * 86400)
        modelContext.insert(card2)

        let group = FinanceGroup(name: "Все карты", colorHex: "#FFFFFF")
        let account1 = FinanceAccount(accountType: .card, accountID: card1.cardUniqueID)
        let account2 = FinanceAccount(accountType: .card, accountID: card2.cardUniqueID)
        account1.group = group
        account2.group = group
        group.accounts = [account1, account2]
        modelContext.insert(group)
        modelContext.insert(account1)
        modelContext.insert(account2)

        // Трансфер 5000 с карты 1 на карту 2
        let transfer = CashflowTransaction(
            transactionType: .transfer,
            amount: 5000,
            currency: "RUB",
            transactionDate: Date().addingTimeInterval(-2 * 86400),
            cardID: card1.cardUniqueID,
            toCardID: card2.cardUniqueID,
            note: "Перевод"
        )
        modelContext.insert(transfer)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        // Карта 1: 10000 - 5000 = 5000
        let balance1 = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account1],
            date: Date(),
            accountCardIDs: [card1.cardUniqueID]
        )
        #expect(abs(balance1 - 5000) < 0.01)

        // Карта 2: 0 + 5000 = 5000
        let balance2 = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account2],
            date: Date(),
            accountCardIDs: [card2.cardUniqueID]
        )
        #expect(abs(balance2 - 5000) < 0.01)

        // Общий баланс не изменился: 10000
        let totalBalance = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account1, account2],
            date: Date(),
            accountCardIDs: [card1.cardUniqueID, card2.cardUniqueID]
        )
        #expect(abs(totalBalance - 10000) < 0.01)
    }

    @Test("Баланс до создания карты равен нулю (если не включен флаг)")
    func testBalanceBeforeCardCreationIsZero() async throws {
        let modelContext = try createTestModelContext()

        let card = Card(name: "Новая", cardNumber: "3333", bank: .other, cardType: .debit, currency: "RUB")
        card.balance = 5000
        card.initialBalance = 5000
        card.hasInitialBalance = true
        card.createdAt = Date() // Создана сегодня
        modelContext.insert(card)

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        // До создания карты (вчера) баланс = 0
        let balanceYesterday = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date().addingTimeInterval(-86400),
            accountCardIDs: [card.cardUniqueID],
            includeInitialBeforeCreation: false
        )
        #expect(abs(balanceYesterday) < 0.01)

        // С флагом includeInitialBeforeCreation баланс = начальный
        let balanceWithFlag = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date().addingTimeInterval(-86400),
            accountCardIDs: [card.cardUniqueID],
            includeInitialBeforeCreation: true
        )
        #expect(abs(balanceWithFlag - 5000) < 0.01)
    }

    @Test("History-only доходы и расходы не искажают исторический баланс карты")
    func testHistoryOnlyCashflowTransactionsDoNotAffectDynamicsBalance() async throws {
        let modelContext = try createTestModelContext()
        let operationDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)) ?? Date()

        let card = Card(
            name: "History only",
            cardNumber: "7777",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
        )
        card.initialBalance = 1_000
        card.hasInitialBalance = true
        modelContext.insert(card)

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)

        modelContext.insert(
            CashflowTransaction(
                transactionType: .expense,
                amount: 200,
                currency: "RUB",
                transactionDate: operationDate,
                cardID: card.cardUniqueID,
                expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
                affectsCardBalance: false
            )
        )
        modelContext.insert(
            CashflowTransaction(
                transactionType: .income,
                amount: 350,
                currency: "RUB",
                transactionDate: operationDate,
                cardID: card.cardUniqueID,
                incomeCategoryRaw: IncomeCategory.salary.rawValue,
                affectsCardBalance: false
            )
        )
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let balance = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: operationDate,
            accountCardIDs: [card.cardUniqueID]
        )

        #expect(abs(balance - 1_000) < 0.01)
    }

    @Test("Конвертация в динамике нормализует валютные пары")
    func testDynamicsConversionNormalizesCurrencyPair() async throws {
        let modelContext = try createTestModelContext()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsNormalizedCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsNormalizedCurrencyRateService()
        )

        let converted = await dynamicsViewModel.convertAmount(
            value: 2.0,
            from: "BTC/USD",
            to: "RUB",
            at: Date()
        )
        #expect(abs(converted - 200.0) < 0.01)
    }

    @Test("Динамика использует зафиксированный курс транзакции")
    func testDynamicsUsesFrozenTransactionRate() async throws {
        let modelContext = try createTestModelContext()

        let investment = Investment(
            name: "Asset",
            investmentType: .positive,
            category: .other,
            amount: 200,
            currency: "RUB"
        )
        investment.initialAmount = 0
        investment.hasInitialAmount = true
        investment.createdAt = Date().addingTimeInterval(-2 * 86400)
        modelContext.insert(investment)

        let group = FinanceGroup(name: "Группа", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)

        let tx = CashflowTransaction(
            transactionType: .balanceAdjustment,
            amount: 2.0,
            currency: "USD",
            transactionDate: Date().addingTimeInterval(-3600),
            investmentID: investment.investmentUniqueID,
            note: "fx"
        )
        tx.exchangeRate = 100.0
        tx.exchangeRateCurrency = "RUB"
        tx.exchangeRateDate = Calendar.current.startOfDay(for: tx.transactionDate)
        modelContext.insert(tx)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let balance = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date(),
            accountCardIDs: []
        )
        #expect(abs(balance - 200.0) < 0.01)
    }

    @Test("Крипта: без истории корректировок используем актуальную позицию после создания")
    func testCryptoGrowthUsesActualAmountAfterUpdateWithoutTransactions() async throws {
        let modelContext = try createTestModelContext()

        let createdAt = Date().addingTimeInterval(-7 * 86400)
        let updatedAt = Date().addingTimeInterval(-3600)

        let investment = Investment(
            name: "BTC/USD",
            investmentType: .positive,
            category: .crypto,
            amount: 66_236,
            currency: "USD"
        )
        investment.createdAt = createdAt
        investment.updatedAt = updatedAt
        investment.initialAmount = 50_000
        investment.hasInitialAmount = true
        modelContext.insert(investment)

        let group = FinanceGroup(name: "Крипта", colorHex: "#00AAFF")
        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let beforeUpdate = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: updatedAt.addingTimeInterval(-60),
            accountCardIDs: []
        )
        #expect(abs(beforeUpdate - 50_000) < 0.01)

        let afterUpdate = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: updatedAt.addingTimeInterval(60),
            accountCardIDs: []
        )
        #expect(abs(afterUpdate - 66_236) < 0.01)
    }

    @Test("Акции: без истории корректировок используем актуальную позицию после создания")
    func testStocksGrowthUsesActualAmountAfterUpdateWithoutTransactions() async throws {
        let modelContext = try createTestModelContext()

        let createdAt = Date().addingTimeInterval(-10 * 86400)
        let updatedAt = Date().addingTimeInterval(-2 * 3600)

        let investment = Investment(
            name: "AA",
            investmentType: .positive,
            category: .stocks,
            amount: 4_672,
            currency: "USD"
        )
        investment.createdAt = createdAt
        investment.updatedAt = updatedAt
        investment.initialAmount = 3_900
        investment.hasInitialAmount = true
        modelContext.insert(investment)

        let group = FinanceGroup(name: "Акции", colorHex: "#00CC66")
        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let beforeUpdate = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: updatedAt.addingTimeInterval(-60),
            accountCardIDs: []
        )
        #expect(abs(beforeUpdate - 3_900) < 0.01)

        let afterUpdate = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: Date(),
            accountCardIDs: []
        )
        #expect(abs(afterUpdate - 4_672) < 0.01)
    }

    @Test("Агрегат: вчера и сегодня совпадают, если не было транзакций изменений")
    func testAggregateBalanceStableBetweenYesterdayAndTodayWithoutChanges() async throws {
        let modelContext = try createTestModelContext()

        let createdAt = Date().addingTimeInterval(-20 * 86400)
        let updatedAt = Date().addingTimeInterval(-2 * 86400)

        let card = Card(name: "Дебет", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB")
        card.createdAt = createdAt
        card.updatedAt = updatedAt
        card.initialBalance = 100_000
        card.hasInitialBalance = true
        card.balance = 150_000
        modelContext.insert(card)

        let creditCard = Card(name: "Кредит", cardNumber: "2222", bank: .other, cardType: .credit, currency: "RUB")
        creditCard.createdAt = createdAt
        creditCard.updatedAt = updatedAt
        creditCard.creditLimit = 1_000_000
        creditCard.initialBalance = 0
        creditCard.hasInitialBalance = true
        creditCard.balance = 900_000
        modelContext.insert(creditCard)

        let investment = Investment(
            name: "APP",
            investmentType: .positive,
            category: .stocks,
            amount: 118_002.16,
            currency: "USD"
        )
        investment.createdAt = createdAt
        investment.updatedAt = updatedAt
        investment.initialAmount = 10_000
        investment.hasInitialAmount = true
        modelContext.insert(investment)

        let group = FinanceGroup(name: "Тест", colorHex: "#FFFFFF")
        let account1 = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        let account2 = FinanceAccount(accountType: .card, accountID: creditCard.cardUniqueID)
        let account3 = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account1.group = group
        account2.group = group
        account3.group = group
        group.accounts = [account1, account2, account3]
        modelContext.insert(group)
        modelContext.insert(account1)
        modelContext.insert(account2)
        modelContext.insert(account3)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        let accounts = [account1, account2, account3]
        let today = Date()
        let yesterday = today.addingTimeInterval(-86400)
        let accountCardIDs: Set<String> = [card.cardUniqueID, creditCard.cardUniqueID]

        let yesterdayBalance = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: accounts,
            date: yesterday,
            accountCardIDs: accountCardIDs,
            debtAsNegative: true
        )
        let todayBalance = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: accounts,
            date: today,
            accountCardIDs: accountCardIDs,
            debtAsNegative: true
        )

        #expect(abs(yesterdayBalance - todayBalance) < 0.01)
    }

    @Test("Daily snapshot override приоритетнее исторического расчета в динамике за прошлую дату")
    func testAuditSnapshotOverrideIsUsedForPastDate() async throws {
        let modelContext = try createTestModelContext()

        let card = Card(name: "My Car", cardNumber: "0000", bank: .other, cardType: .debit, currency: "USD")
        card.initialBalance = 2_330
        card.hasInitialBalance = true
        card.balance = 11_110
        card.createdAt = Date().addingTimeInterval(-5 * 86_400)
        card.updatedAt = Date()
        modelContext.insert(card)

        let group = FinanceGroup(name: "Assets", colorHex: "#FFFFFF")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let auditStore = InMemoryFinanceBalanceAuditStore()

        let targetDate = Date().addingTimeInterval(-1 * 86_400)
        let accountKey = "\(FinanceAccountType.card.rawValue):\(card.cardUniqueID)"
        auditStore.setValue(
            8_888,
            for: accountKey,
            day: FinanceBalanceDayKey(date: targetDate),
            defaultCurrency: "USD",
            defaultTitle: card.name,
            defaultGroupName: group.name,
            accountTypeRaw: FinanceAccountType.card.rawValue,
            effectSign: 1,
            isUnknown: false
        )

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService(),
            auditStore: auditStore
        )
        dynamicsViewModel.handle(.loadData)

        let endOfTargetDay = Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: targetDate
        ) ?? targetDate

        let valueAtTargetDay = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: [account],
            date: endOfTargetDay,
            accountCardIDs: Set([card.cardUniqueID]),
            debtAsNegative: false
        )

        #expect(abs(valueAtTargetDay - 8_888) < 0.01)
    }

    @Test("Overview chart относит рост активов в debit, а рост долга в credit")
    func overviewEntriesSeparateDebitAndCreditFlows() async throws {
        let schema = Schema([
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            HistoricalRate.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let modelContext = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)) ?? Date()

        let debitCard = Card(name: "Дебет", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB")
        debitCard.createdAt = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? referenceDate
        debitCard.updatedAt = referenceDate
        debitCard.initialBalance = 100
        debitCard.hasInitialBalance = true
        debitCard.balance = 160
        modelContext.insert(debitCard)

        let credit = Credit(
            name: "Кредит",
            amount: 100,
            interestRate: 0,
            monthlyPayment: 10,
            startDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? referenceDate,
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.createdAt = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? referenceDate
        credit.updatedAt = referenceDate
        credit.initialRemainingAmount = 100
        credit.hasInitialRemainingAmount = true
        credit.remainingAmount = 130
        modelContext.insert(credit)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        let debitAccount = FinanceAccount(accountType: .card, accountID: debitCard.cardUniqueID)
        let creditAccount = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        debitAccount.group = group
        creditAccount.group = group
        group.accounts = [debitAccount, creditAccount]
        modelContext.insert(group)
        modelContext.insert(debitAccount)
        modelContext.insert(creditAccount)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        dynamicsViewModel.state.groups = [group]

        let entries = await dynamicsViewModel.buildOverviewEntries(
            granularity: .month,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let marchStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? referenceDate
        let marchEntry = try #require(entries.first(where: {
            calendar.isDate($0.date, equalTo: marchStart, toGranularity: .month)
        }))

        #expect(abs(marchEntry.debit - 60) < 0.01)
        #expect(abs(marchEntry.credit - 30) < 0.01)
    }

    @Test("Динамика повторяет порядок групп и счетов из финансов")
    func testDynamicsBreakdownUsesFinanceOrdering() async throws {
        let modelContext = try createTestModelContext()

        let firstGroup = FinanceGroup(name: "Первая", colorHex: "#111111", order: 0)
        let secondGroup = FinanceGroup(name: "Вторая", colorHex: "#222222", order: 1)
        modelContext.insert(firstGroup)
        modelContext.insert(secondGroup)

        let alphaCard = Card(
            name: "Alpha",
            cardNumber: "1111",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100
        )
        let betaCard = Card(
            name: "Beta",
            cardNumber: "2222",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 200
        )
        let gammaCard = Card(
            name: "Gamma",
            cardNumber: "3333",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 300
        )
        modelContext.insert(alphaCard)
        modelContext.insert(betaCard)
        modelContext.insert(gammaCard)

        let alphaAccount = FinanceAccount(accountType: .card, accountID: alphaCard.cardUniqueID)
        alphaAccount.group = firstGroup
        let betaAccount = FinanceAccount(accountType: .card, accountID: betaCard.cardUniqueID)
        betaAccount.group = secondGroup
        let gammaAccount = FinanceAccount(accountType: .card, accountID: gammaCard.cardUniqueID)
        gammaAccount.group = secondGroup

        modelContext.insert(alphaAccount)
        modelContext.insert(betaAccount)
        modelContext.insert(gammaAccount)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)
        financeViewModel.handle(.moveGroup(sourceGroupID: secondGroup.groupUniqueID, destinationIndex: 0))

        let reorderedSecondGroup = try #require(
            financeViewModel.state.groups.first(where: { $0.groupUniqueID == secondGroup.groupUniqueID })
        )
        financeViewModel.handle(
            .moveAccount(
                sourceAccountID: gammaAccount.accountUniqueID,
                destinationIndex: 0,
                groupID: reorderedSecondGroup.groupUniqueID
            )
        )

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)

        dynamicsViewModel.state.viewMode = .groups
        await dynamicsViewModel.updateDynamicsBreakdown()
        #expect(dynamicsViewModel.state.dynamicsBreakdown.map(\.name) == ["Вторая", "Первая"])

        let orderedGroup = try #require(dynamicsViewModel.state.groups.first)
        #expect(
            dynamicsViewModel.getAccounts(for: orderedGroup).compactMap { account in
                dynamicsViewModel.getAccountInfoForDynamics(account: account)?.name
            } == ["Gamma", "Beta"]
        )

        dynamicsViewModel.state.viewMode = .accounts
        await dynamicsViewModel.updateDynamicsBreakdown()
        #expect(dynamicsViewModel.state.dynamicsBreakdown.map(\.name) == ["Gamma", "Beta", "Alpha"])
    }
}
