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

    @Test("Для расхода показываются только карты в выбранной валюте, а избранные идут первыми")
    func expenseFiltersCardsByCurrencyAndPrioritizesFavorites() {
        let regularEurCard = Card(name: "EUR Regular", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "EUR")
        let favoriteEurCard = Card(name: "EUR Favorite", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "EUR", isFavorite: true)
        let usdCard = Card(name: "USD", cardNumber: "3333", bank: .tinkoff, cardType: .debit, currency: "USD", isFavorite: true)

        let cards = CashflowTransactionEditorView.cardsForCurrency(
            [regularEurCard, favoriteEurCard, usdCard],
            transactionType: .expense,
            currency: "eur"
        )

        #expect(cards.count == 2)
        #expect(cards.map(\.cardUniqueID) == [favoriteEurCard.cardUniqueID, regularEurCard.cardUniqueID])
        #expect(Set(cards.map(\.currency)) == Set(["EUR"]))
    }

    @Test("Список карт сортирует избранные раньше обычных")
    func cardPickerPrioritizesFavorites() {
        let regular = Card(name: "Regular", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        let favorite = Card(name: "Favorite", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "RUB", isFavorite: true)

        let cards = CashflowTransactionEditorView.cardsForCurrency(
            [regular, favorite],
            transactionType: .transfer,
            currency: "RUB"
        )

        #expect(cards.map(\.cardUniqueID) == [favorite.cardUniqueID, regular.cardUniqueID])
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

    @Test("Для расходов быстрые переходы собраны в один горизонтальный ряд")
    func expenseManagementEntries() {
        let entries = CashflowManagementEntry.entries(for: .expense)

        #expect(entries.map(\.destination) == [.bulkImport, .recurring, .planned])
    }

    @Test("Для доходов быстрые переходы не показывают массовый импорт")
    func incomeManagementEntries() {
        let entries = CashflowManagementEntry.entries(for: .income)

        #expect(entries.map(\.destination) == [.recurring, .planned])
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
