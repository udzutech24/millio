//
//  BudgetAutoRepeatPrefs.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

/// Хранит UX-настройку автоповтора месячных лимитов между месяцами.
/// Это именно пользовательское предпочтение, а не часть данных бюджета.
struct BudgetAutoRepeatPrefs {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "cashflow_budget_auto_repeat_monthly_limits_v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: key) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }
}

struct BudgetRepeatSuggestion: Equatable {
    let totalAmount: Double
    let categoryLimits: [String: Double]
    let sourceMonth: Date
}
