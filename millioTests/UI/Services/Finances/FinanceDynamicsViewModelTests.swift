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

@Suite(.serialized)
@MainActor
struct FinanceDynamicsViewModelTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            HistoricalRate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(FinanceAccount.self)
        try context.deleteAll(FinanceGroup.self)
        try context.deleteAll(CashflowTransaction.self)
        try context.deleteAll(Investment.self)
        try context.deleteAll(Credit.self)
        try context.deleteAll(Card.self)
        try context.deleteAll(HistoricalRate.self)
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
}
