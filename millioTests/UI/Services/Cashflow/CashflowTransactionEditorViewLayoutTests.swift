//
//  CashflowTransactionEditorViewLayoutTests.swift
//  millioTests
//
//  Created by Codex on 01.03.2026.
//

import Testing
@testable import millio

struct CashflowTransactionEditorViewLayoutTests {
    @Test("Для дохода показываются только карты в выбранной валюте")
    func incomeFiltersCardsByCurrency() {
        let rubCard = Card(name: "RUB", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        let usdCard = Card(name: "USD", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "USD")

        let cards = CashflowTransactionEditorView.cardsForCurrency(
            [rubCard, usdCard],
            transactionType: .income,
            currency: "usd"
        )

        #expect(cards.count == 1)
        #expect(cards.first?.currency == "USD")
    }

    @Test("Для расхода показываются только карты в выбранной валюте")
    func expenseFiltersCardsByCurrency() {
        let eurCard = Card(name: "EUR", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "EUR")
        let usdCard = Card(name: "USD", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "USD")

        let cards = CashflowTransactionEditorView.cardsForCurrency(
            [eurCard, usdCard],
            transactionType: .expense,
            currency: "eur"
        )

        #expect(cards.count == 1)
        #expect(cards.first?.currency == "EUR")
    }

    @Test("Для перевода фильтрации по валюте нет")
    func transferDoesNotFilterCardsByCurrency() {
        let rubCard = Card(name: "RUB", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        let usdCard = Card(name: "USD", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "USD")

        let cards = CashflowTransactionEditorView.cardsForCurrency(
            [rubCard, usdCard],
            transactionType: .transfer,
            currency: "RUB"
        )

        #expect(cards.count == 2)
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
        #expect(kind.navigationTitle == "New income")
        #expect(kind.monthlyTotalTitle == "Total income for month")
        #expect(kind.categoryKind == .income)
        #expect(kind.transactionType == .income)
        #expect(kind.historyFilter == .income)
    }

    @Test("Конфигурация cashflow-листа для расхода")
    func expenseSheetConfiguration() {
        let kind = CashflowCategoryTransactionSheetKind.expense
        #expect(kind.navigationTitle == "New expense")
        #expect(kind.monthlyTotalTitle == "Total expense for month")
        #expect(kind.categoryKind == .expense)
        #expect(kind.transactionType == .expense)
        #expect(kind.historyFilter == .expense)
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
}
