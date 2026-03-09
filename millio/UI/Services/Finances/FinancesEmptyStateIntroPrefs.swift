//
//  FinancesEmptyStateIntroPrefs.swift
//  millio
//

import Foundation

/// Persists whether the Finances "empty state intro" onboarding should be hidden.
struct FinancesEmptyStateIntroPrefs {
    static let hiddenKey = "finances_main_empty_intro_hidden"

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

