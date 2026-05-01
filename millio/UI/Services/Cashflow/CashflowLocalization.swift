//
//  CashflowLocalization.swift
//  millio
//

import Foundation

enum CashflowLocalization {
    private static func tr(_ key: String, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: AppLocalization.currentAppLocale, fallback: fallback)
    }

    // MARK: — Period display names

    static var periodMonth: String   { tr("cashflow.period_selector.month") }
    static var periodQuarter: String { tr("cashflow.period_selector.quarter") }
    static var periodYear: String    { tr("cashflow.period_selector.year") }
    static var periodWeek: String    { tr("cashflow.common.period.week") }
    static var periodCustom: String  { tr("cashflow.common.period.custom") }

    // MARK: — Transaction type display names

    static var typeIncome: String               { tr("cashflow.common.type.income") }
    static var typeExpense: String              { tr("cashflow.common.type.expense") }
    static var typeTransfer: String             { tr("cashflow.common.type.transfer") }
    static var typeBalanceAdjustment: String    { tr("cashflow.common.type.balance_adjustment") }
    static var typeCardBalanceAdjustment: String { tr("cashflow.common.type.card_balance_adjustment") }
    static var typeDebtAdjustment: String       { tr("cashflow.common.type.debt_adjustment") }

    // MARK: — Recurrence display names

    static var recurrenceNone: String    { tr("cashflow.common.recurrence.none") }
    static var recurrenceMonthly: String { tr("cashflow.common.recurrence.monthly") }

    // MARK: — Misc

    static var uncategorized: String { tr("cashflow.common.uncategorized") }
}
