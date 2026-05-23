//
//  RateSourcePreferenceStore.swift
//  millio
//

import Foundation

/// Хранилище пользовательского выбора источника курсов.
/// store.preferred пишется строго через CurrencyRateService.setRateSource — нигде больше.
struct RateSourcePreferenceStore {
    static let shared = RateSourcePreferenceStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Глобальный предпочтительный источник курсов.
    /// Читают все — пишет только CurrencyRateService.setRateSource.
    var preferred: RateSource {
        get {
            guard let raw = defaults.string(forKey: "preferred_rate_source"),
                  let source = RateSource(rawValue: raw) else {
                return .millio
            }
            return source
        }
        set {
            defaults.set(newValue.rawValue, forKey: "preferred_rate_source")
        }
    }

    /// Источник конвертера — nil означает «использовать глобальный preferred».
    var converterOverride: RateSource? {
        get {
            guard let raw = defaults.string(forKey: "conv_rate_source") else { return nil }
            return RateSource(rawValue: raw)
        }
        set {
            if let source = newValue {
                defaults.set(source.rawValue, forKey: "conv_rate_source")
            } else {
                defaults.removeObject(forKey: "conv_rate_source")
            }
        }
    }

    func reset() {
        defaults.removeObject(forKey: "preferred_rate_source")
        defaults.removeObject(forKey: "conv_rate_source")
    }
}
