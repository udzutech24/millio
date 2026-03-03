//
//  CashbackCardPickerRecommendationPrefs.swift
//  millio
//

import Foundation

/// Хранилище флага скрытия рекомендации в выборе карты кешбэка.
struct CashbackCardPickerRecommendationPrefs {
    static let shared = CashbackCardPickerRecommendationPrefs()
    static let hiddenKey = "cashback_card_picker_recommendation_hidden"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isHidden() -> Bool {
        defaults.bool(forKey: Self.hiddenKey)
    }

    func setHidden(_ isHidden: Bool) {
        defaults.set(isHidden, forKey: Self.hiddenKey)
    }
}

