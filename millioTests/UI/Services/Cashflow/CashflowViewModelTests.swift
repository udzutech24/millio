//
//  CashflowViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 29.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowViewModelTests {
    private static let schema = Schema([
        Card.self,
        CashflowTransaction.self,
        CashflowCustomCategory.self,
        CashflowSystemCategoryOverride.self,
        HistoricalRate.self
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func createTestModelContext() throws -> ModelContext {
        let defaults = UserDefaults.standard
        defaults.set("RUB", forKey: "primaryCurrencyCode")

        // Вьюмодель запускает фоновые Task при инициализации.
        // Отдельный контейнер на тест исключает утечки данных между кейсами.
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }
}

extension CashflowViewModelTests {
    @Test("CashflowViewModel смена display валюты не меняет primary валюту профиля")
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

        let viewModel = CashflowViewModel(modelContext: modelContext)
        viewModel.handle(.setDisplayCurrency("AMD"))

        #expect(viewModel.state.displayCurrency == "AMD")
        #expect(SettingsManager.shared.primaryCurrencyCode == "USD")
    }

    @Test("CashflowViewModel синхронизирует display валюту при смене основной если модуль следовал прошлой основной")
    func testSyncPrimaryCurrencyChangeUpdatesFollowingDisplayCurrency() throws {
        let modelContext = try createTestModelContext()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        #expect(viewModel.state.displayCurrency == "RUB")

        viewModel.handle(.syncPrimaryCurrencyChange(old: "RUB", new: "USD"))

        #expect(viewModel.state.displayCurrency == "USD")
    }

    @Test("CashflowViewModel всегда синхронизирует display валюту с основной при ее смене")
    func testSyncPrimaryCurrencyChangeOverridesCustomDisplayCurrency() throws {
        let modelContext = try createTestModelContext()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        #expect(viewModel.state.displayCurrency == "RUB")
        viewModel.handle(.setDisplayCurrency("EUR"))
        #expect(viewModel.state.displayCurrency == "EUR")

        viewModel.handle(.syncPrimaryCurrencyChange(old: "RUB", new: "USD"))

        #expect(viewModel.state.displayCurrency == "USD")
    }

    @Test("Расход не превышает доступный баланс карты")
    func testExpenseCannotExceedBalance() async throws {
        let modelContext = try createTestModelContext()
        let card = Card(
            name: "Карта",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000.0
        )
        modelContext.insert(card)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        viewModel.handle(.loadCards)

        let available = try await viewModel.isAmountAvailable(
            amount: 1_500.0,
            currency: "RUB",
            fromCardID: card.cardUniqueID,
            on: Date()
        )
        #expect(!available)
    }

    @Test("Перевод разрешен в пределах доступного баланса")
    func testTransferWithinBalanceAllowed() async throws {
        let modelContext = try createTestModelContext()
        let card = Card(
            name: "Карта",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000.0
        )
        modelContext.insert(card)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        viewModel.handle(.loadCards)

        let available = try await viewModel.isAmountAvailable(
            amount: 500.0,
            currency: "RUB",
            fromCardID: card.cardUniqueID,
            on: Date()
        )
        #expect(available)
    }

    @Test("Cashflow обновляет историю по событию transactionsUpdated")
    func testTransactionsUpdatedEventReloadsTransactions() async throws {
        let modelContext = try createTestModelContext()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        #expect(viewModel.state.transactions.isEmpty)

        let transaction = CashflowTransaction(
            transactionType: .income,
            amount: 1000,
            currency: "RUB",
            transactionDate: Date(),
            cardID: nil,
            note: "Тест"
        )
        modelContext.insert(transaction)
        try modelContext.save()

        EventBus.shared.publish(FinanceEvent.transactionsUpdated)

        #expect(viewModel.state.transactions.count == 1)
        #expect(viewModel.state.transactions.first?.note == "Тест")
    }

    @Test("Стрелки периода переключают месяцы и не уходят в будущее")
    func testMonthNavigationByArrows() async throws {
        let modelContext = try createTestModelContext()
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 13)) ?? Date()
        let viewModel = CashflowViewModel(modelContext: modelContext, now: { fixedNow })

        let calendar = Calendar.current
        let initialMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: fixedNow)) ?? fixedNow

        #expect(!viewModel.canMovePeriodForward())

        viewModel.handle(.movePeriodBackward)
        #expect(viewModel.state.chartPeriod == .specificMonth)
        #expect(calendar.component(.month, from: viewModel.state.selectedMonth) == 1)
        #expect(calendar.component(.year, from: viewModel.state.selectedMonth) == 2026)
        #expect(viewModel.canMovePeriodForward())

        viewModel.handle(.movePeriodForward)
        #expect(calendar.component(.month, from: viewModel.state.selectedMonth) == calendar.component(.month, from: initialMonth))
        #expect(calendar.component(.year, from: viewModel.state.selectedMonth) == calendar.component(.year, from: initialMonth))
        #expect(!viewModel.canMovePeriodForward())

        viewModel.handle(.movePeriodForward)
        #expect(calendar.component(.month, from: viewModel.state.selectedMonth) == calendar.component(.month, from: initialMonth))
        #expect(calendar.component(.year, from: viewModel.state.selectedMonth) == calendar.component(.year, from: initialMonth))
    }

    @Test("Итог дохода за месяц учитывает только доходы выбранного месяца")
    func testMonthlyIncomeTotalUsesOnlySelectedMonthIncome() async throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current
        let februaryDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)) ?? Date()

        let incomeJanuary = CashflowTransaction(
            transactionType: .income,
            amount: 100,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 20)) ?? februaryDate,
            cardID: nil
        )
        let incomeFebruaryA = CashflowTransaction(
            transactionType: .income,
            amount: 300,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? februaryDate,
            cardID: nil
        )
        let incomeFebruaryB = CashflowTransaction(
            transactionType: .income,
            amount: 200,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 28)) ?? februaryDate,
            cardID: nil
        )
        let expenseFebruary = CashflowTransaction(
            transactionType: .expense,
            amount: 900,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 15)) ?? februaryDate,
            cardID: nil
        )

        modelContext.insert(incomeJanuary)
        modelContext.insert(incomeFebruaryA)
        modelContext.insert(incomeFebruaryB)
        modelContext.insert(expenseFebruary)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        let februaryTotal = await viewModel.monthlyIncomeTotal(for: februaryDate, in: "RUB")
        let januaryTotal = await viewModel.monthlyIncomeTotal(
            for: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? februaryDate,
            in: "RUB"
        )

        #expect(abs(februaryTotal - 500) < 0.01)
        #expect(abs(januaryTotal - 100) < 0.01)
    }

    @Test("Итог расхода за месяц учитывает только расходы выбранного месяца")
    func testMonthlyExpenseTotalUsesOnlySelectedMonthExpense() async throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current
        let marchDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()

        let expenseMarchA = CashflowTransaction(
            transactionType: .expense,
            amount: 150,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)) ?? marchDate,
            cardID: nil
        )
        let expenseMarchB = CashflowTransaction(
            transactionType: .expense,
            amount: 250,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 31)) ?? marchDate,
            cardID: nil
        )
        let expenseFebruary = CashflowTransaction(
            transactionType: .expense,
            amount: 70,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20)) ?? marchDate,
            cardID: nil
        )
        let incomeMarch = CashflowTransaction(
            transactionType: .income,
            amount: 500,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)) ?? marchDate,
            cardID: nil
        )

        modelContext.insert(expenseMarchA)
        modelContext.insert(expenseMarchB)
        modelContext.insert(expenseFebruary)
        modelContext.insert(incomeMarch)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        let marchTotal = await viewModel.monthlyExpenseTotal(for: marchDate, in: "RUB")
        let februaryTotal = await viewModel.monthlyExpenseTotal(
            for: calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? marchDate,
            in: "RUB"
        )

        #expect(abs(marchTotal - 400) < 0.01)
        #expect(abs(februaryTotal - 70) < 0.01)
    }

    @Test("Разбивка по категориям за месяц учитывает только выбранный тип и месяц")
    func testMonthlyCategoryTotalsByKindAndMonth() async throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current
        let marchDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()

        let salaryA = CashflowTransaction(
            transactionType: .income,
            amount: 300,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? marchDate,
            cardID: nil,
            incomeCategoryRaw: IncomeCategory.salary.rawValue
        )
        let salaryB = CashflowTransaction(
            transactionType: .income,
            amount: 100,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 20)) ?? marchDate,
            cardID: nil,
            incomeCategoryRaw: IncomeCategory.salary.rawValue
        )
        let gift = CashflowTransaction(
            transactionType: .income,
            amount: 250,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)) ?? marchDate,
            cardID: nil,
            incomeCategoryRaw: IncomeCategory.gift.rawValue
        )
        let februaryIncome = CashflowTransaction(
            transactionType: .income,
            amount: 999,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 15)) ?? marchDate,
            cardID: nil,
            incomeCategoryRaw: IncomeCategory.salary.rawValue
        )
        let marchExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 500,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 12)) ?? marchDate,
            cardID: nil,
            expenseCategoryRaw: ExpenseCategory.groceries.rawValue
        )

        modelContext.insert(salaryA)
        modelContext.insert(salaryB)
        modelContext.insert(gift)
        modelContext.insert(februaryIncome)
        modelContext.insert(marchExpense)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        let incomeTotals = await viewModel.monthlyCategoryTotals(for: .income, month: marchDate, in: "RUB")
        let expenseTotals = await viewModel.monthlyCategoryTotals(for: .expense, month: marchDate, in: "RUB")

        #expect(abs((incomeTotals[IncomeCategory.salary.rawValue] ?? 0) - 400) < 0.01)
        #expect(abs((incomeTotals[IncomeCategory.gift.rawValue] ?? 0) - 250) < 0.01)
        #expect(incomeTotals[ExpenseCategory.groceries.rawValue] == nil)
        #expect(abs((expenseTotals[ExpenseCategory.groceries.rawValue] ?? 0) - 500) < 0.01)
    }

    @Test("Сводка активов считает изменение стоимости по формуле и использует снапшот из Финансов")
    func testAssetsBreakdownFormula() async throws {
        let modelContext = try createTestModelContext()
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 13)) ?? Date()
        let defaults = UserDefaults.standard
        let previousDisplayCurrency = defaults.string(forKey: "cashflow_display_currency")
        defaults.set("RUB", forKey: "cashflow_display_currency")
        defer {
            if let previousDisplayCurrency {
                defaults.set(previousDisplayCurrency, forKey: "cashflow_display_currency")
            } else {
                defaults.removeObject(forKey: "cashflow_display_currency")
            }
        }

        let income = CashflowTransaction(
            transactionType: .income,
            amount: 500,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil
        )
        let expense = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil
        )
        modelContext.insert(income)
        modelContext.insert(expense)
        try modelContext.save()

        let viewModel = CashflowViewModel(
            modelContext: modelContext,
            now: { fixedNow },
            assetsSnapshotProvider: { _, _, _ in
                (start: 1_000, end: 1_300)
            }
        )

        viewModel.handle(.loadTransactions)

        try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            abs(viewModel.state.assetsAtPeriodStart - 1_000) < 0.01 &&
            abs(viewModel.state.assetsAtPeriodEnd - 1_300) < 0.01 &&
            abs(viewModel.state.totalIncome - 500) < 0.01 &&
            abs(viewModel.state.contributedExpense - 100) < 0.01 &&
            abs(viewModel.state.assetValueChange + 100) < 0.01 &&
            abs(viewModel.state.periodTotalChange - 300) < 0.01
        }

        #expect(abs(viewModel.state.assetsAtPeriodStart - 1_000) < 0.01)
        #expect(abs(viewModel.state.assetsAtPeriodEnd - 1_300) < 0.01)
        #expect(abs(viewModel.state.totalIncome - 500) < 0.01)
        #expect(abs(viewModel.state.contributedExpense - 100) < 0.01)
        #expect(abs(viewModel.state.assetValueChange + 100) < 0.01) // 300 - 500 + 100 = -100
        #expect(abs(viewModel.state.periodTotalChange - 300) < 0.01)
    }

    @Test("Детализация расходов сортируется по убыванию и учитывает доходы отдельно")
    func testBreakdownSortingByAmount() async throws {
        let modelContext = try createTestModelContext()
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 13)) ?? Date()
        let defaults = UserDefaults.standard
        let previousDisplayCurrency = defaults.string(forKey: "cashflow_display_currency")
        defaults.set("RUB", forKey: "cashflow_display_currency")
        defer {
            if let previousDisplayCurrency {
                defaults.set(previousDisplayCurrency, forKey: "cashflow_display_currency")
            } else {
                defaults.removeObject(forKey: "cashflow_display_currency")
            }
        }

        let expenseSmall = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil,
            expenseCategory: .groceries,
            note: "Small"
        )
        let expenseLarge = CashflowTransaction(
            transactionType: .expense,
            amount: 300,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil,
            expenseCategory: .shopping,
            note: "Large"
        )
        let expenseMedium = CashflowTransaction(
            transactionType: .expense,
            amount: 200,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil,
            expenseCategory: .cafe,
            note: "Medium"
        )
        let income = CashflowTransaction(
            transactionType: .income,
            amount: 400,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil,
            incomeCategory: .salary,
            note: "Income"
        )

        modelContext.insert(expenseSmall)
        modelContext.insert(expenseLarge)
        modelContext.insert(expenseMedium)
        modelContext.insert(income)
        try modelContext.save()

        let viewModel = CashflowViewModel(
            modelContext: modelContext,
            now: { fixedNow },
            assetsSnapshotProvider: { _, _, _ in
                (start: 0, end: 0)
            }
        )

        viewModel.handle(.loadTransactions)

        try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            viewModel.state.expenseBreakdown.count == 3 &&
            viewModel.state.incomeBreakdown.count == 1
        }

        let expenseBreakdown = viewModel.state.expenseBreakdown
        #expect(expenseBreakdown.map { $0.title } == ["Покупки", "Кафе", "Продукты"])
        #expect(expenseBreakdown.map { $0.convertedAmount } == [300, 200, 100])
        #expect(viewModel.state.incomeBreakdown.first?.title == "Зарплата")
        #expect(viewModel.state.incomeBreakdown.first?.convertedAmount == 400)
    }

    @Test("Кастомная категория расхода создается и попадает в опции")
    func testCreateCustomExpenseCategory() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: modelContext)

        let created = viewModel.createCustomCategory(
            kind: .expense,
            name: "Книги",
            icon: "book.fill"
        )

        #expect(created != nil)
        #expect(created?.displayName == "Книги")
        #expect(created?.isCustom == true)
        #expect(viewModel.categoryOptions(for: .expense).contains { $0.displayName == "Книги" && $0.isCustom })
    }

    @Test("Системные категории доходов и расходов по умолчанию используют emoji-иконки")
    func testSystemCategoriesUseEmojiIconsByDefault() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: modelContext)

        let income = viewModel.categoryOption(for: IncomeCategory.salary.rawValue, kind: .income)
        let expense = viewModel.categoryOption(for: ExpenseCategory.groceries.rawValue, kind: .expense)

        #expect(income.icon == "💼")
        #expect(expense.icon == "🛒")
        #expect(!CashflowCustomCategory.isSFSymbolIcon(income.icon))
        #expect(!CashflowCustomCategory.isSFSymbolIcon(expense.icon))
    }

    @Test("Нормализация иконки поддерживает emoji и SF Symbols")
    func testNormalizeIconSupportsEmojiAndSFSymbol() {
        #expect(CashflowCustomCategory.normalizeIcon("🛒") == "🛒")
        #expect(CashflowCustomCategory.normalizeIcon("cart.fill") == "cart.fill")
        #expect(CashflowCustomCategory.normalizeIcon("unknown.icon") == CashflowCustomCategory.defaultIcon)
    }

    @Test("Удаление кастомной категории расхода мигрирует транзакции в Другое")
    func testDeleteCustomExpenseCategoryMigratesTransactions() async throws {
        let modelContext = try createTestModelContext()
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 13)) ?? Date()
        let defaults = UserDefaults.standard
        let previousDisplayCurrency = defaults.string(forKey: "cashflow_display_currency")
        defaults.set("RUB", forKey: "cashflow_display_currency")
        defer {
            if let previousDisplayCurrency {
                defaults.set(previousDisplayCurrency, forKey: "cashflow_display_currency")
            } else {
                defaults.removeObject(forKey: "cashflow_display_currency")
            }
        }

        let viewModel = CashflowViewModel(
            modelContext: modelContext,
            now: { fixedNow },
            assetsSnapshotProvider: { _, _, _ in
                (start: 0, end: 0)
            }
        )

        guard let custom = viewModel.createCustomCategory(kind: .expense, name: "Такси", icon: "car.fill") else {
            #expect(Bool(false), "Custom category was not created")
            return
        }

        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: 300,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil,
            expenseCategoryRaw: custom.rawValue
        )
        modelContext.insert(transaction)
        try modelContext.save()

        viewModel.handle(.loadTransactions)
        #expect(viewModel.expenseCategoryDisplayName(for: custom.rawValue) == "Такси")

        let deleted = viewModel.deleteCustomCategory(rawValue: custom.rawValue, kind: .expense)
        #expect(deleted)
        #expect(transaction.expenseCategoryRaw == ExpenseCategory.other.rawValue)

        viewModel.handle(.loadTransactions)
        try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            viewModel.state.expenseBreakdown.contains(where: {
                $0.title == ExpenseCategory.other.displayName && abs($0.convertedAmount - 300) < 0.01
            })
        }
    }

    @Test("Редактирование кастомной категории обновляет имя и иконку")
    func testRenameCustomCategoryUpdatesNameAndIcon() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: modelContext)

        guard let created = viewModel.createCustomCategory(
            kind: .income,
            name: "Подработка",
            icon: "briefcase.fill"
        ) else {
            #expect(Bool(false), "Custom category was not created")
            return
        }

        let renamed = viewModel.renameCustomCategory(
            rawValue: created.rawValue,
            kind: .income,
            newName: "Фриланс проекты",
            newIcon: "laptopcomputer"
        )

        #expect(renamed)
        let resolved = viewModel.categoryOption(for: created.rawValue, kind: .income)
        #expect(resolved.displayName == "Фриланс проекты")
        #expect(resolved.icon == "laptopcomputer")
        #expect(resolved.isCustom)
    }

    @Test("Редактирование системной категории сохраняет новое имя и иконку")
    func testRenameSystemCategoryUpdatesNameAndIcon() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: modelContext)

        let renamed = viewModel.renameCategory(
            rawValue: ExpenseCategory.groceries.rawValue,
            kind: .expense,
            newName: "Супермаркет",
            newIcon: "cart.fill"
        )

        #expect(renamed)
        let resolved = viewModel.categoryOption(for: ExpenseCategory.groceries.rawValue, kind: .expense)
        #expect(resolved.displayName == "Супермаркет")
        #expect(resolved.icon == "cart.fill")
        #expect(!resolved.isCustom)
    }

    @Test("Удаление системной категории скрывает ее и мигрирует транзакции в Другое")
    func testDeleteSystemCategoryHidesAndMigratesTransactions() async throws {
        let modelContext = try createTestModelContext()
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 13)) ?? Date()
        let viewModel = CashflowViewModel(
            modelContext: modelContext,
            now: { fixedNow },
            assetsSnapshotProvider: { _, _, _ in
                (start: 0, end: 0)
            }
        )

        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: 750,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil,
            expenseCategoryRaw: ExpenseCategory.shopping.rawValue
        )
        modelContext.insert(transaction)
        try modelContext.save()

        viewModel.handle(.loadTransactions)
        #expect(viewModel.canDeleteCategory(rawValue: ExpenseCategory.shopping.rawValue, kind: .expense))
        #expect(!viewModel.canDeleteCategory(rawValue: ExpenseCategory.other.rawValue, kind: .expense))

        let deleted = viewModel.deleteCategory(rawValue: ExpenseCategory.shopping.rawValue, kind: .expense)
        #expect(deleted)
        #expect(transaction.expenseCategoryRaw == ExpenseCategory.other.rawValue)

        let options = viewModel.categoryOptions(for: .expense)
        #expect(!options.contains(where: { $0.rawValue == ExpenseCategory.shopping.rawValue }))
    }

    @Test("Ежемесячный автоповтор создаёт пропущенные операции и не дублирует месяцы")
    func testMonthlyRecurringGeneratesMissingTransactions() async throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20)) ?? Date()
        let card = Card(
            name: "Основная",
            cardNumber: "1234",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
        )
        modelContext.insert(card)
        let template = CashflowTransaction(
            transactionType: .income,
            amount: 100,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 15)) ?? fixedNow,
            cardID: card.cardUniqueID,
            incomeCategory: .salary,
            note: "Recurring salary",
            recurrenceRule: .monthly,
            recurrenceSeriesID: "series-monthly-salary"
        )
        modelContext.insert(template)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext, now: { fixedNow })
        // Стартовая загрузка и генерация происходят асинхронно — принудительно
        // триггерим повторную загрузку, чтобы тест не флапал по таймингу.
        viewModel.handle(.loadTransactions)

        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            viewModel.state.transactions.count == 3
        }

        let months = viewModel.state.transactions
            .map { calendar.component(.month, from: $0.transactionDate) }
            .sorted()
        #expect(months == [1, 2, 3])
        #expect(abs(card.balance - 1_200) < 0.01)

        viewModel.handle(.loadTransactions)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(viewModel.state.transactions.count == 3)
    }

    @Test("Ежемесячный автоповтор корректно клампит 31 число к концу месяца")
    func testMonthlyRecurringClampsDayToMonthEnd() async throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31)) ?? Date()
        let template = CashflowTransaction(
            transactionType: .income,
            amount: 50,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? fixedNow,
            incomeCategory: .salary,
            recurrenceRule: .monthly,
            recurrenceSeriesID: "series-day-31"
        )
        modelContext.insert(template)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext, now: { fixedNow })
        // Стартовая загрузка и генерация происходят асинхронно — принудительно
        // триггерим повторную загрузку, чтобы тест не флапал по таймингу.
        viewModel.handle(.loadTransactions)

        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            viewModel.state.transactions.count == 3
        }

        let dayByMonth = viewModel.state.transactions
            .map {
                (
                    month: calendar.component(.month, from: $0.transactionDate),
                    day: calendar.component(.day, from: $0.transactionDate)
                )
            }
            .sorted { $0.month < $1.month }

        #expect(dayByMonth.map(\.month) == [1, 2, 3])
        #expect(dayByMonth.map(\.day) == [31, 28, 31])
    }

    @Test("Регулярные шаблоны фильтруются по типу и сортируются по ближайшей дате")
    func testRecurringTemplatesFilterAndSortByNextOccurrence() throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()

        let recurringDayFive = CashflowTransaction(
            transactionType: .income,
            amount: 100,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? fixedNow,
            incomeCategory: .salary,
            recurrenceRule: .monthly,
            recurrenceSeriesID: "series-income-5"
        )
        let recurringDayTwentyFive = CashflowTransaction(
            transactionType: .income,
            amount: 120,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 25)) ?? fixedNow,
            incomeCategory: .bonus,
            recurrenceRule: .monthly,
            recurrenceSeriesID: "series-income-25"
        )
        let recurringExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 200,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 8)) ?? fixedNow,
            expenseCategory: .bills,
            recurrenceRule: .monthly,
            recurrenceSeriesID: "series-expense-8"
        )
        let oneTimeIncome = CashflowTransaction(
            transactionType: .income,
            amount: 90,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 12)) ?? fixedNow,
            incomeCategory: .gift,
            recurrenceRule: .none
        )

        modelContext.insert(recurringDayFive)
        modelContext.insert(recurringDayTwentyFive)
        modelContext.insert(recurringExpense)
        modelContext.insert(oneTimeIncome)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext, now: { fixedNow })
        let templates = viewModel.recurringTemplates(for: .income, relativeTo: fixedNow)

        #expect(templates.count == 2)
        #expect(templates.first?.recurrenceSeriesID == "series-income-25")
        #expect(templates.last?.recurrenceSeriesID == "series-income-5")

        let nextForDayFive = viewModel.nextOccurrenceDate(for: recurringDayFive, relativeTo: fixedNow)
        let nextComponents = nextForDayFive.map { calendar.dateComponents([.year, .month, .day], from: $0) }
        #expect(nextComponents?.year == 2026)
        #expect(nextComponents?.month == 4)
        #expect(nextComponents?.day == 5)
    }

    @Test("Запланированные одноразовые операции включают только будущие без автоповтора")
    func testPlannedOneTimeTransactionsIncludeFutureNonRecurringOnly() throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()

        let plannedA = CashflowTransaction(
            transactionType: .expense,
            amount: 50,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 12)) ?? fixedNow,
            expenseCategory: .transport
        )
        let plannedB = CashflowTransaction(
            transactionType: .expense,
            amount: 70,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 20)) ?? fixedNow,
            expenseCategory: .shopping
        )
        let pastOneTime = CashflowTransaction(
            transactionType: .expense,
            amount: 30,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)) ?? fixedNow,
            expenseCategory: .cafe
        )
        let todayOneTime = CashflowTransaction(
            transactionType: .expense,
            amount: 40,
            currency: "RUB",
            transactionDate: fixedNow,
            expenseCategory: .groceries
        )
        let recurringFuture = CashflowTransaction(
            transactionType: .expense,
            amount: 90,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)) ?? fixedNow,
            expenseCategory: .bills,
            recurrenceRule: .monthly,
            recurrenceSeriesID: "series-expense-future"
        )
        let incomePlanned = CashflowTransaction(
            transactionType: .income,
            amount: 100,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 18)) ?? fixedNow,
            incomeCategory: .salary
        )

        modelContext.insert(plannedA)
        modelContext.insert(plannedB)
        modelContext.insert(pastOneTime)
        modelContext.insert(todayOneTime)
        modelContext.insert(recurringFuture)
        modelContext.insert(incomePlanned)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext, now: { fixedNow })
        let planned = viewModel.plannedOneTimeTransactions(for: .expense, relativeTo: fixedNow)

        #expect(planned.count == 2)
        #expect(planned.map(\.amount) == [50, 70])
        #expect(planned.allSatisfy { $0.recurrenceRule == .none })
        #expect(planned.allSatisfy { $0.transactionType == .expense })
    }

    @Test("Удаление операции исключает ее из регулярных и запланированных списков")
    func testDeleteTransactionRemovesItFromScheduledCollections() throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current
        let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()

        let recurringIncome = CashflowTransaction(
            transactionType: .income,
            amount: 1200,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 15)) ?? fixedNow,
            incomeCategory: .salary,
            recurrenceRule: .monthly,
            recurrenceSeriesID: "series-income-delete"
        )
        let plannedExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 300,
            currency: "RUB",
            transactionDate: calendar.date(from: DateComponents(year: 2026, month: 3, day: 18)) ?? fixedNow,
            expenseCategory: .shopping
        )

        modelContext.insert(recurringIncome)
        modelContext.insert(plannedExpense)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext, now: { fixedNow })
        #expect(viewModel.recurringTemplates(for: .income, relativeTo: fixedNow).count == 1)
        #expect(viewModel.plannedOneTimeTransactions(for: .expense, relativeTo: fixedNow).count == 1)

        viewModel.handle(.deleteTransaction(recurringIncome))
        viewModel.handle(.deleteTransaction(plannedExpense))

        #expect(viewModel.recurringTemplates(for: .income, relativeTo: fixedNow).isEmpty)
        #expect(viewModel.plannedOneTimeTransactions(for: .expense, relativeTo: fixedNow).isEmpty)
    }

    @Test("История фильтруется по диапазону дат включительно и сохраняет сортировку по дате")
    func testHistoryTransactionsFiltersByDateRangeInclusively() throws {
        let modelContext = try createTestModelContext()
        let calendar = Calendar.current

        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()
        let secondDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)) ?? Date()
        let thirdDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3)) ?? Date()

        let t1 = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: firstDay,
            cardID: nil
        )
        let t2 = CashflowTransaction(
            transactionType: .expense,
            amount: 200,
            currency: "RUB",
            transactionDate: secondDay,
            cardID: nil
        )
        let t3 = CashflowTransaction(
            transactionType: .expense,
            amount: 300,
            currency: "RUB",
            transactionDate: thirdDay,
            cardID: nil
        )

        modelContext.insert(t1)
        modelContext.insert(t2)
        modelContext.insert(t3)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        let result = viewModel.historyTransactions(
            matching: CashflowHistoryQuery(
                typeFilter: .all,
                searchText: "",
                startDate: thirdDay,
                endDate: secondDay
            )
        )

        #expect(result.count == 2)
        #expect(result.map(\.amount) == [300, 200])
    }

    @Test("История фильтруется по типу и поиску по имени карты")
    func testHistoryTransactionsFiltersByTypeAndCardNameSearch() throws {
        let modelContext = try createTestModelContext()
        let operationDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()

        let alphaCard = Card(
            name: "Alpha Black",
            cardNumber: "1111",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1000
        )
        let betaCard = Card(
            name: "Beta Blue",
            cardNumber: "2222",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1000
        )
        modelContext.insert(alphaCard)
        modelContext.insert(betaCard)

        let alphaExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 450,
            currency: "RUB",
            transactionDate: operationDate,
            cardID: alphaCard.cardUniqueID,
            expenseCategoryRaw: ExpenseCategory.groceries.rawValue
        )
        let alphaIncome = CashflowTransaction(
            transactionType: .income,
            amount: 900,
            currency: "RUB",
            transactionDate: operationDate,
            cardID: alphaCard.cardUniqueID,
            incomeCategoryRaw: IncomeCategory.salary.rawValue
        )
        let betaExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 330,
            currency: "RUB",
            transactionDate: operationDate,
            cardID: betaCard.cardUniqueID,
            expenseCategoryRaw: ExpenseCategory.shopping.rawValue
        )
        modelContext.insert(alphaExpense)
        modelContext.insert(alphaIncome)
        modelContext.insert(betaExpense)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        let result = viewModel.historyTransactions(
            matching: CashflowHistoryQuery(
                typeFilter: .expense,
                searchText: "alpha",
                startDate: nil,
                endDate: nil
            )
        )

        #expect(result.count == 1)
        #expect(result.first?.amount == 450)
        #expect(result.first?.transactionType == .expense)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64,
        intervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        #expect(Bool(false), "Condition was not met before timeout")
    }
}
