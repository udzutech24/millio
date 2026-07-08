//
//  CashflowUpcomingSectionBuilder.swift
//  millio
//
//  Секция «Предстоящие» на главном экране Cashflow (Фаза 0, Шаг 6, план
//  `2026-07-05__cashflow-add-transaction-redesign.md`).
//

import Foundation

/// Единичный элемент секции «Предстоящие» — унифицированное представление recurring/разовых
/// плановых транзакций и будущих процентов по вкладам для компактной карточки на главном экране.
struct CashflowUpcomingItem: Identifiable, Equatable {
    let id: String
    let date: Date
    let kind: CashflowCategoryKind
    let title: String
    /// Всегда положительная — знак при отображении определяется `kind`.
    let amount: Double
    let currencyCode: String
}

/// Собирает и упорядочивает элементы секции «Предстоящие». Никакие даты/суммы здесь не
/// пересчитываются — источники уже посчитаны на своих сервисах: recurring/разовые плановые
/// транзакции (`CashflowScheduledService.scheduledPlannerEntries`, тот же движок, что использует
/// полный `CashflowScheduledTransactionsView`/«Планировщик») и будущие проценты по вкладам
/// (`AccountsCoreDepositCashflowBridge.upcomingInterestEvents`). Единственная новая логика —
/// merge разных источников, сортировка по дате и top-N (тот же приём, что `CashflowBreakdownCapPolicy`
/// применяет к breakdown-списку).
enum CashflowUpcomingSectionBuilder {
    static let defaultVisibleCount = 3

    static func items(
        incomeEntries: [CashflowScheduledEntry],
        expenseEntries: [CashflowScheduledEntry],
        depositInterestEvents: [AccountsCoreDepositCashflowBridge.UpcomingInterestEvent],
        incomeCategoryTitle: (String?) -> String,
        expenseCategoryTitle: (String?) -> String,
        limit: Int = defaultVisibleCount
    ) -> [CashflowUpcomingItem] {
        var merged: [CashflowUpcomingItem] = incomeEntries.map { entry in
            CashflowUpcomingItem(
                id: "income-\(entry.id)",
                date: entry.scheduledDate,
                kind: .income,
                title: incomeCategoryTitle(entry.transaction.incomeCategoryRaw),
                amount: entry.transaction.amount,
                currencyCode: entry.transaction.currency
            )
        }

        merged += expenseEntries.map { entry in
            CashflowUpcomingItem(
                id: "expense-\(entry.id)",
                date: entry.scheduledDate,
                kind: .expense,
                title: expenseCategoryTitle(entry.transaction.expenseCategoryRaw),
                amount: entry.transaction.amount,
                currencyCode: entry.transaction.currency
            )
        }

        merged += depositInterestEvents.map { event in
            CashflowUpcomingItem(
                id: "deposit-interest-\(event.accountID.uuidString)-\(Int(event.date.timeIntervalSince1970))",
                date: event.date,
                kind: .income,
                title: incomeCategoryTitle(IncomeCategory.interest.rawValue),
                amount: event.amount,
                currencyCode: event.currencyCode
            )
        }

        return Array(merged.sorted { $0.date < $1.date }.prefix(limit))
    }
}
