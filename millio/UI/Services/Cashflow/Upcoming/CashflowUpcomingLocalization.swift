import Foundation

enum CashflowUpcomingLocalization {
    private static func value(ru: String, en: String, zh: String) -> String {
        switch LocalizationSupport.effectiveLanguage(for: AppLocalization.currentAppLocale) {
        case Language.russian.rawValue: ru
        case Language.simplifiedChinese.rawValue: zh
        default: en
        }
    }

    static var recurring: String { value(ru: "Ежемесячная операция", en: "Monthly transaction", zh: "每月交易") }
    static var oneTime: String { value(ru: "Разовая операция", en: "One-time transaction", zh: "一次性交易") }
    static var depositInterest: String { value(ru: "Проценты по вкладу", en: "Deposit interest", zh: "存款利息") }
    static var navigationTitle: String { value(ru: "Предстоящие", en: "Upcoming", zh: "即将到来") }
    static var empty: String { value(ru: "Нет предстоящих операций", en: "No upcoming transactions", zh: "没有即将到来的交易") }
    static var addIncome: String { value(ru: "Добавить доход", en: "Add income", zh: "添加收入") }
    static var addExpense: String { value(ru: "Добавить расход", en: "Add expense", zh: "添加支出") }
    static var addAccessibilityLabel: String { value(ru: "Добавить план", en: "Add plan", zh: "添加计划") }
    static var filterAccessibilityLabel: String { value(ru: "Фильтр предстоящих", en: "Upcoming filter", zh: "即将到来筛选") }
    static var editHint: String { value(ru: "Открывает редактор", en: "Opens the editor", zh: "打开编辑器") }
    static var readOnlyHint: String { value(ru: "Прогноз только для чтения", en: "Read-only forecast", zh: "只读预测") }
    static var openAccountHint: String { value(ru: "Открывает счёт вклада", en: "Opens the deposit account", zh: "打开存款账户") }

    static func title(for filter: CashflowUpcomingFilter) -> String {
        switch filter {
        case .all: value(ru: "Все", en: "All", zh: "全部")
        case .income: value(ru: "Доходы", en: "Income", zh: "收入")
        case .expenses: value(ru: "Расходы", en: "Expenses", zh: "支出")
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
            ? value(ru: "доход", en: "income", zh: "收入")
            : value(ru: "расход", en: "expense", zh: "支出")
        let signedAmount = item.kind == .income ? item.amount : -item.amount
        return "\(item.title), \(subtitle(for: item)), \(direction), \(date), \(cashflowSignedAmountText(signedAmount)) \(cashflowCurrencyCodeLabel(item.currencyCode))"
    }
}
