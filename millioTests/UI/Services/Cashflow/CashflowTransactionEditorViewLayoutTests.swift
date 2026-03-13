//
//  CashflowTransactionEditorViewLayoutTests.swift
//  millioTests
//
//  Created by Codex on 01.03.2026.
//

import Foundation
import Testing
@testable import millio

struct CashflowTransactionEditorViewLayoutTests {
    @Test("Для дохода показываются только карты в выбранной валюте")
    func incomeFiltersCardsByCurrency() {
        let rubCard = Card(name: "RUB", cardNumber: "1111", bank: .sberbank, cardType: .debit, priority: .normal, currency: "RUB")
        let usdCard = Card(name: "USD", cardNumber: "2222", bank: .tinkoff, cardType: .debit, priority: .normal, currency: "USD")

        let accounts = CashflowTransactionEditorView.selectableAccounts(
            cards: [rubCard, usdCard],
            investments: [],
            transactionType: .income,
            currency: "usd"
        )

        #expect(accounts.count == 1)
        #expect(accounts.first?.currency == "USD")
        #expect(accounts.first?.cardID == usdCard.cardUniqueID)
    }

    @Test("Для расхода приоритет продукта важнее избранного")
    func expensePrioritizesProductPriorityBeforeFavoriteFlag() {
        let lowFavorite = Card(name: "Low Favorite", cardNumber: "1111", bank: .sberbank, cardType: .debit, priority: .low, currency: "EUR", isFavorite: true)
        let highRegular = Card(name: "High Regular", cardNumber: "2222", bank: .tinkoff, cardType: .debit, priority: .high, currency: "EUR")
        let usdCard = Card(name: "USD", cardNumber: "3333", bank: .tinkoff, cardType: .debit, priority: .high, currency: "USD", isFavorite: true)

        let accounts = CashflowTransactionEditorView.selectableAccounts(
            cards: [lowFavorite, highRegular, usdCard],
            investments: [],
            transactionType: .expense,
            currency: "eur"
        )

        #expect(accounts.count == 2)
        #expect(accounts.map(\.cardID) == [highRegular.cardUniqueID, lowFavorite.cardUniqueID])
        #expect(Set(accounts.map(\.currency)) == Set(["EUR"]))
    }

    @Test("Для дохода показываются счета из финансов вместе с картами")
    func incomeIncludesCashAccountsFromInvestments() {
        let debitCard = Card(name: "Debit", cardNumber: "1111", bank: .sberbank, cardType: .debit, priority: .normal, currency: "RUB")
        let account = Investment(
            name: "Reserve",
            investmentType: .positive,
            category: .other,
            amount: 500,
            currency: "RUB",
            includeInTotal: true,
            priority: .high,
            isFavorite: false
        )
        let asset = Investment(
            name: "Gold",
            investmentType: .positive,
            category: .metals,
            amount: 900,
            currency: "RUB",
            includeInTotal: true,
            priority: .high,
            isFavorite: true
        )

        let accounts = CashflowTransactionEditorView.selectableAccounts(
            cards: [debitCard],
            investments: [account, asset],
            transactionType: .income,
            currency: "RUB"
        )

        #expect(accounts.count == 2)
        #expect(accounts.map(\.id) == ["investment:\(account.investmentUniqueID)", "card:\(debitCard.cardUniqueID)"])
    }

    @Test("Для перевода фильтрации по валюте нет")
    func transferDoesNotFilterCardsByCurrency() {
        let rubCard = Card(name: "RUB", cardNumber: "1111", bank: .sberbank, cardType: .debit, priority: .normal, currency: "RUB")
        let usdCard = Card(name: "USD", cardNumber: "2222", bank: .tinkoff, cardType: .debit, priority: .normal, currency: "USD")

        let accounts = CashflowTransactionEditorView.selectableAccounts(
            cards: [rubCard, usdCard],
            investments: [],
            transactionType: .transfer,
            currency: "RUB"
        )

        #expect(accounts.count == 2)
    }

    @Test("Основная информация для дохода: карта между суммой и валютой")
    func incomeMainInfoRows() {
        let rows = CashflowTransactionEditorView.mainInfoRows(for: .income)
        #expect(rows == [.amount, .fromCard, .currency, .date])
    }

    @Test("Основная информация для расхода: карта между суммой и валютой")
    func expenseMainInfoRows() {
        let rows = CashflowTransactionEditorView.mainInfoRows(for: .expense)
        #expect(rows == [.amount, .fromCard, .currency, .date])
    }

    @Test("Основная информация для перевода: обе карты между суммой и валютой")
    func transferMainInfoRows() {
        let rows = CashflowTransactionEditorView.mainInfoRows(for: .transfer)
        #expect(rows == [.amount, .fromCard, .toCard, .currency, .date])
    }

    @Test("Конфигурация cashflow-листа для дохода")
    func incomeSheetConfiguration() {
        let kind = CashflowCategoryTransactionSheetKind.income
        #expect(kind.navigationTitle == String(localized: "cashflow.operation.new_income"))
        #expect(kind.monthlyTotalTitle == String(localized: "cashflow.operation.total_income_for_month"))
        #expect(kind.categoryKind == .income)
        #expect(kind.transactionType == .income)
        #expect(kind.historyFilter == .income)
    }

    @Test("Конфигурация cashflow-листа для расхода")
    func expenseSheetConfiguration() {
        let kind = CashflowCategoryTransactionSheetKind.expense
        #expect(kind.navigationTitle == String(localized: "cashflow.operation.new_expense"))
        #expect(kind.monthlyTotalTitle == String(localized: "cashflow.operation.total_expense_for_month"))
        #expect(kind.categoryKind == .expense)
        #expect(kind.transactionType == .expense)
        #expect(kind.historyFilter == .expense)
    }

    @Test("Для расходов быстрые переходы собраны в один горизонтальный ряд")
    func expenseManagementEntries() {
        let entries = CashflowManagementEntry.entries(for: .expense)

        #expect(entries.map(\.destination) == [.bulkImport, .planned])
        #expect(entries.map(\.lineLimit) == [2, 2])
    }

    @Test("Для доходов быстрые переходы не показывают массовый импорт")
    func incomeManagementEntries() {
        let entries = CashflowManagementEntry.entries(for: .income)

        #expect(entries.map(\.destination) == [.recurring, .planned])
        #expect(entries.map(\.lineLimit) == [1, 2])
        #expect(entries[1].title == String(localized: "cashflow.management.income_plan.title"))
    }

    @Test("Селектор валюты операции закрепляет основную валюту профиля")
    func operationCurrencyPrimaryPinnedCodeNormalization() {
        #expect(CashflowTransactionEditorView.operationCurrencyPrimaryPinnedCode(from: " rub ") == "RUB")
        #expect(CashflowTransactionEditorView.operationCurrencyPrimaryPinnedCode(from: "") == nil)
        #expect(CashflowTransactionEditorView.operationCurrencyPrimaryPinnedCode(from: nil) == nil)
    }

    @Test("Сумма в cashflow принимает запятую и копейки")
    func cashflowAmountSupportsCommaAndCents() {
        let sanitized = CashflowTransactionEditorView.sanitizedAmountText(from: "1 234,56")
        let displayed = CashflowTransactionEditorView.formattedAmountDisplayText(from: sanitized)

        #expect(sanitized == "1234.56")
        #expect(displayed == "1 234.56")
    }

    @Test("Сумма в cashflow ограничена двумя знаками после запятой")
    func cashflowAmountTrimsExtraFractionDigits() {
        let sanitized = CashflowTransactionEditorView.sanitizedAmountText(from: "99,9999")

        #expect(sanitized == "99.99")
    }

    @Test("Поле суммы уменьшает шрифт для длинных значений")
    func amountFieldUsesCompactFontForLongValues() {
        #expect(CashflowTransactionEditorView.amountFontSize(for: "12 345") == CashflowTransactionEditorView.amountBaseFontSize)
        #expect(CashflowTransactionEditorView.amountFontSize(for: "1234567") == CashflowTransactionEditorView.amountCompactFontSize)
        #expect(CashflowTransactionEditorView.amountFontSize(for: "1 234 567.89") == CashflowTransactionEditorView.amountCompactFontSize)
    }
}
