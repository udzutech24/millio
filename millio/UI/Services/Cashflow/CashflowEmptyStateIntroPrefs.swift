//
//  CashflowEmptyStateIntroPrefs.swift
//  millio
//

import Foundation

/// Persists whether the Cashflow "empty state intro" onboarding should be hidden.
struct CashflowEmptyStateIntroPrefs {
    static let hiddenKey = "cashflow_main_empty_intro_hidden"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isHidden() -> Bool {
        defaults.bool(forKey: Self.hiddenKey)
    }

    func setHidden(_ hidden: Bool) {
        defaults.set(hidden, forKey: Self.hiddenKey)
    }
}
