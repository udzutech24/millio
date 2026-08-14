//
//  CashflowUpcomingSectionBuilder.swift
//  millio
//
//  Секция «Предстоящие» на главном экране Cashflow (Фаза 0, Шаг 6, план
//  `2026-07-05__cashflow-add-transaction-redesign.md`).
//

import Foundation
import SwiftData

enum CashflowUpcomingSource: Equatable {
    case recurring
    case oneTimePlanned
    case depositInterest
}

enum CashflowUpcomingReference: Equatable {
    /// Exact local model identity. Business `uniqueID` may legitimately be duplicated while
    /// scope-merge keeps stale/fresh records, so it is unsafe for editor navigation.
    case transaction(persistentID: PersistentIdentifier)
    case deposit(accountID: UUID)
}

/// Единичный элемент секции «Предстоящие» — унифицированное представление recurring/разовых
/// плановых транзакций и будущих процентов по вкладам для компактной карточки на главном экране.
struct CashflowUpcomingItem: Identifiable, Equatable {
    let id: String
    let date: Date
    let kind: CashflowCategoryKind
    let title: String
    let categoryTitle: String
    let source: CashflowUpcomingSource
    let reference: CashflowUpcomingReference
    /// Всегда положительная — знак при отображении определяется `kind`.
    let amount: Double
    let currencyCode: String
}

/// Собирает и упорядочивает элементы секции «Предстоящие». Никакие даты/суммы здесь не
/// пересчитываются — источники уже посчитаны на своих сервисах: recurring/разовые плановые
/// транзакции (`CashflowScheduledService.scheduledPlannerEntries`, тот же движок, что использует
/// полный `CashflowScheduledTransactionsView`/«Планировщик») и будущие проценты по вкладам
/// (`AccountsCoreDepositCashflowBridge.upcomingInterestEvents`). Единственная новая логика —
/// merge разных источников и стабильная сортировка. Ограничение количества — ответственность
/// компактной карточки, чтобы полный destination не определял собственный набор данных.
enum CashflowUpcomingSectionBuilder {
    static let defaultVisibleCount = 3

    static func items(
        incomeEntries: [CashflowScheduledEntry],
        expenseEntries: [CashflowScheduledEntry],
        depositInterestEvents: [AccountsCoreDepositCashflowBridge.UpcomingInterestEvent],
        incomeCategoryTitle: (String?) -> String,
        expenseCategoryTitle: (String?) -> String,
        limit: Int? = nil
    ) -> [CashflowUpcomingItem] {
        var merged: [CashflowUpcomingItem] = incomeEntries.map { entry in
            let categoryTitle = incomeCategoryTitle(entry.transaction.incomeCategoryRaw)
            return CashflowUpcomingItem(
                id: "income-\(entry.id)",
                date: entry.scheduledDate,
                kind: .income,
                title: displayTitle(for: entry.transaction, fallback: categoryTitle),
                categoryTitle: categoryTitle,
                source: entry.kind == .recurringMonthly ? .recurring : .oneTimePlanned,
                reference: .transaction(persistentID: entry.transaction.persistentModelID),
                amount: entry.transaction.amount,
                currencyCode: entry.transaction.currency
            )
        }

        merged += expenseEntries.map { entry in
            let categoryTitle = expenseCategoryTitle(entry.transaction.expenseCategoryRaw)
            return CashflowUpcomingItem(
                id: "expense-\(entry.id)",
                date: entry.scheduledDate,
                kind: .expense,
                title: displayTitle(for: entry.transaction, fallback: categoryTitle),
                categoryTitle: categoryTitle,
                source: entry.kind == .recurringMonthly ? .recurring : .oneTimePlanned,
                reference: .transaction(persistentID: entry.transaction.persistentModelID),
                amount: entry.transaction.amount,
                currencyCode: entry.transaction.currency
            )
        }

        merged += depositInterestEvents.map { event in
            CashflowUpcomingItem(
                id: "deposit-interest-\(event.accountID.uuidString)-\(Int(event.date.timeIntervalSince1970))",
                date: event.date,
                kind: .income,
                title: event.accountName,
                categoryTitle: incomeCategoryTitle(IncomeCategory.interest.rawValue),
                source: .depositInterest,
                reference: .deposit(accountID: event.accountID),
                amount: event.amount,
                currencyCode: event.currencyCode
            )
        }

        let sorted = merged.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }

    private static func displayTitle(for transaction: CashflowTransaction, fallback: String) -> String {
        let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? fallback : note
    }
}
