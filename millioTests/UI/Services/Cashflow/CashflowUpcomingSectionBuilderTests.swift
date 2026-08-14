//
//  CashflowUpcomingSectionBuilderTests.swift
//  millioTests
//
//  Фаза 0, Шаг 6 плана `2026-07-05__cashflow-add-transaction-redesign.md` — секция «Предстоящие»
//  на главном экране Cashflow. Покрывает merge источников, сортировку по дате, top-N cap и
//  пустое состояние (без View-харнеса — чистая логика).
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("CashflowUpcomingSectionBuilder")
struct CashflowUpcomingSectionBuilderTests {

    private func date(_ daysFromNow: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
    }

    private func incomeEntry(daysFromNow: Int, amount: Double = 1_000, currency: String = "RUB") -> CashflowScheduledEntry {
        let transaction = CashflowTransaction(
            transactionType: .income,
            amount: amount,
            currency: currency,
            transactionDate: date(daysFromNow),
            incomeCategory: .salary
        )
        return CashflowScheduledEntry(transaction: transaction, scheduledDate: date(daysFromNow), kind: .recurringMonthly)
    }

    private func expenseEntry(daysFromNow: Int, amount: Double = 500, currency: String = "RUB") -> CashflowScheduledEntry {
        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: amount,
            currency: currency,
            transactionDate: date(daysFromNow),
            expenseCategory: .other
        )
        return CashflowScheduledEntry(transaction: transaction, scheduledDate: date(daysFromNow), kind: .oneTimePlanned)
    }

    private func depositEvent(daysFromNow: Int, amount: Double = 250, currency: String = "RUB") -> AccountsCoreDepositCashflowBridge.UpcomingInterestEvent {
        AccountsCoreDepositCashflowBridge.UpcomingInterestEvent(
            date: date(daysFromNow),
            amount: amount,
            currencyCode: currency,
            accountID: UUID(),
            accountName: "Вклад"
        )
    }

    private func build(
        income: [CashflowScheduledEntry] = [],
        expense: [CashflowScheduledEntry] = [],
        deposits: [AccountsCoreDepositCashflowBridge.UpcomingInterestEvent] = [],
        limit: Int = CashflowUpcomingSectionBuilder.defaultVisibleCount
    ) -> [CashflowUpcomingItem] {
        CashflowUpcomingSectionBuilder.items(
            incomeEntries: income,
            expenseEntries: expense,
            depositInterestEvents: deposits,
            incomeCategoryTitle: { _ in "Доход" },
            expenseCategoryTitle: { _ in "Расход" },
            limit: limit
        )
    }

    @Test("Пустые все три источника — пустой результат (карточка не рендерится)")
    func emptySourcesProduceEmptyResult() {
        #expect(build().isEmpty)
    }

    @Test("Три источника объединяются и сортируются строго по дате (не по источнику)")
    func mergesAllSourcesSortedByDate() {
        let items = build(
            income: [incomeEntry(daysFromNow: 5)],
            expense: [expenseEntry(daysFromNow: 1)],
            deposits: [depositEvent(daysFromNow: 3)]
        )
        #expect(items.count == 3)
        #expect(items.map(\.kind) == [.expense, .income, .income]) // день 1 (расход), 3 (вклад), 5 (доход)
        #expect(items[0].date < items[1].date && items[1].date < items[2].date)
    }

    @Test("Cap по умолчанию — top-3, лишние ближайшие по дате остаются, дальние отсекаются")
    func capsToDefaultLimitKeepingNearestByDate() {
        let income = (0..<5).map { incomeEntry(daysFromNow: $0 * 2) }
        let items = build(income: income)
        #expect(items.count == CashflowUpcomingSectionBuilder.defaultVisibleCount)
        #expect(items.map(\.date) == income.prefix(3).map(\.scheduledDate))
    }

    @Test("Кастомный limit применяется")
    func respectsCustomLimit() {
        let income = (0..<5).map { incomeEntry(daysFromNow: $0) }
        let items = build(income: income, limit: 2)
        #expect(items.count == 2)
    }

    @Test("Полный source не имеет compact cap, а карточка берёт prefix того же набора")
    func fullSourceAndCompactPrefixHaveParity() {
        let full = build(income: (0..<5).map { incomeEntry(daysFromNow: $0) }, limit: .max)
        let compact = Array(full.prefix(CashflowUpcomingSectionBuilder.defaultVisibleCount))
        #expect(full.count == 5)
        #expect(compact.map(\.id) == full.prefix(3).map(\.id))
    }

    @Test("Доход → kind .income, сумма положительная как есть")
    func incomeItemKindAndAmount() {
        let items = build(income: [incomeEntry(daysFromNow: 1, amount: 1_500)])
        #expect(items.first?.kind == .income)
        #expect(items.first?.amount == 1_500)
        #expect(items.first?.title == "Доход")
    }

    @Test("Расход → kind .expense, сумма хранится положительной (знак — на уровне отображения)")
    func expenseItemKindAndAmount() {
        let items = build(expense: [expenseEntry(daysFromNow: 1, amount: 750)])
        #expect(items.first?.kind == .expense)
        #expect(items.first?.amount == 750)
        #expect(items.first?.title == "Расход")
    }

    @Test("Проценты по вкладу → kind .income, категория резолвится через тот же incomeCategoryTitle")
    func depositInterestItemIsIncomeKind() {
        let items = build(deposits: [depositEvent(daysFromNow: 2, amount: 300)])
        #expect(items.first?.kind == .income)
        #expect(items.first?.amount == 300)
        #expect(items.first?.title == "Вклад")
        #expect(items.first?.categoryTitle == "Доход")
        #expect(items.first?.source == .depositInterest)
    }

    @Test("Плановый тип и заметка не теряются в компактной карточке")
    func plannedSourceAndNoteArePreserved() throws {
        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: 200,
            currency: "RUB",
            transactionDate: date(1),
            expenseCategory: .other,
            note: "Оплата сервиса"
        )
        let entry = CashflowScheduledEntry(
            transaction: transaction,
            scheduledDate: date(1),
            kind: .oneTimePlanned
        )

        let item = try #require(build(expense: [entry]).first)
        #expect(item.title == "Оплата сервиса")
        #expect(item.categoryTitle == "Расход")
        #expect(item.source == .oneTimePlanned)
        #expect(item.reference == .transaction(persistentID: transaction.persistentModelID))
    }

    @Test("Ссылка на editor различает две локальные записи с одинаковым uniqueID")
    func editorReferenceUsesExactPersistentIdentity() throws {
        let first = incomeEntry(daysFromNow: 1)
        let second = incomeEntry(daysFromNow: 2)
        first.transaction.uniqueID = "duplicate-business-id"
        second.transaction.uniqueID = "duplicate-business-id"

        let items = build(income: [first, second], limit: 2)
        #expect(items[0].reference == .transaction(persistentID: first.transaction.persistentModelID))
        #expect(items[1].reference == .transaction(persistentID: second.transaction.persistentModelID))
        #expect(items[0].reference != items[1].reference)
    }

    @Test("Идентификаторы разных источников не пересекаются даже при совпадающей дате")
    func idsAreNamespacedPerSource() {
        let sharedDay = 4
        let items = build(
            income: [incomeEntry(daysFromNow: sharedDay)],
            expense: [expenseEntry(daysFromNow: sharedDay)],
            deposits: [depositEvent(daysFromNow: sharedDay)]
        )
        let ids = Set(items.map(\.id))
        #expect(ids.count == 3)
    }
}
