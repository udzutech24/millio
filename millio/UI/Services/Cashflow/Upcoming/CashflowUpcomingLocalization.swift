import Foundation

enum CashflowUpcomingLocalization {
    static var recurring: String { L("cashflow.upcoming.source.recurring") }
    static var oneTime: String { L("cashflow.upcoming.source.one_time") }
    static var depositInterest: String { L("cashflow.upcoming.source.deposit_interest") }
    static var navigationTitle: String { L("cashflow.upcoming.section_title") }
    static var empty: String { L("cashflow.upcoming.empty") }
    static var addIncome: String { L("cashflow.upcoming.add_income") }
    static var addExpense: String { L("cashflow.upcoming.add_expense") }
    static var addAccessibilityLabel: String { L("cashflow.upcoming.accessibility.add") }
    static var filterAccessibilityLabel: String { L("cashflow.upcoming.accessibility.filter") }
    static var editHint: String { L("cashflow.upcoming.accessibility.edit_hint") }
    static var readOnlyHint: String { L("cashflow.upcoming.accessibility.read_only_hint") }
    static var openAccountHint: String { L("cashflow.upcoming.accessibility.open_account_hint") }

    static func title(for filter: CashflowUpcomingFilter) -> String {
        switch filter {
        case .all: L("cashflow.upcoming.filter.all")
        case .income: L("cashflow.upcoming.filter.income")
        case .expenses: L("cashflow.upcoming.filter.expenses")
        }
    }

    static func subtitle(for item: CashflowUpcomingItem) -> String {
        let source: String = switch item.source {
        case .recurring: recurring
        case .oneTimePlanned: oneTime
        case .depositInterest: depositInterest
        }
        guard item.source != .depositInterest, item.title != item.categoryTitle else { return source }
        return "\(source) • \(item.categoryTitle)"
    }

    static func accessibilityLabel(for item: CashflowUpcomingItem, date: String) -> String {
        let direction = item.kind == .income
            ? L("cashflow.upcoming.accessibility.direction_income")
            : L("cashflow.upcoming.accessibility.direction_expense")
        let signedAmount = item.kind == .income ? item.amount : -item.amount
        return "\(item.title), \(subtitle(for: item)), \(direction), \(date), \(cashflowSignedAmountText(signedAmount)) \(cashflowCurrencyCodeLabel(item.currencyCode))"
    }
}
