//
//  MainLocalization.swift
//  millio
//
//  Created by Codex on 04.03.2026.
//

import Foundation

enum MainLocalization {
    static let historyAccessibility = "main.history.accessibility"

    static let quickActionExpense = "main.quick_action.expense"
    static let quickActionIncome = "main.quick_action.income"

    static let serviceFinances = "main.service.finances"
    static let serviceCourses = "main.service.courses"
    static let serviceCashback = "main.service.cashback"
    static let serviceCashflow = "main.service.cashflow"

    static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
