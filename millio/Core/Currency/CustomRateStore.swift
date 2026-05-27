//
//  CustomRateStore.swift
//  millio
//

import Foundation

/// Хранит курсы, введённые пользователем вручную.
/// rates[code] = «сколько единиц primaryCurrency за 1 единицу code».
/// Пишет/читает из UserDefaults; reset() вызывается из DataResetService.
struct CustomRateStore {
    static let shared = CustomRateStore()

    private enum Keys {
        static let rates = "custom_rates"
        static let primary = "custom_rates_primary"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Storage

    var rates: [String: Double] {
        get { (defaults.dictionary(forKey: Keys.rates) as? [String: Double]) ?? [:] }
        set { defaults.set(newValue, forKey: Keys.rates) }
    }

    var primaryForRates: String {
        get { defaults.string(forKey: Keys.primary) ?? "RUB" }
        set { defaults.set(newValue, forKey: Keys.primary) }
    }

    // MARK: - Validation

    /// true, если данных достаточно для конвертации (USD задан или primary == USD)
    var isConfigured: Bool {
        let r = rates
        guard !r.isEmpty else { return false }
        return primaryForRates.uppercased() == "USD" || r["USD"] != nil
    }

    // MARK: - USD-base conversion

    /// Конвертирует пользовательские курсы в USD-base для CurrencyRateService.cachedRates.
    /// Формат совпадает с er-api: cachedRates[X] = «сколько X за 1 USD».
    /// Например, cachedRates["RUB"]=72 означает 1 USD = 72 RUB.
    /// USD в результат не включается — сервис всегда держит его как 1.0.
    func toUSDBase(currentPrimary: String) -> [String: Double] {
        // Нормализуем ключи к uppercase при чтении
        let r = rates.reduce(into: [String: Double]()) { $0[$1.key.uppercased()] = $1.value }
        guard !r.isEmpty else { return [:] }

        let primary = currentPrimary.uppercased()

        // Сколько единиц primaryCurrency стоит 1 USD
        let usdInPrimary: Double
        if primary == "USD" {
            usdInPrimary = 1.0
        } else {
            guard let usdRate = r["USD"], usdRate > 0 else { return [:] }
            usdInPrimary = usdRate
        }

        var result: [String: Double] = [:]
        for (code, xPerForeign) in r {
            guard xPerForeign > 0 else { continue }
            // USD не сохраняем — CurrencyRateService обрабатывает его как 1.0 implicitly
            guard code != "USD" else { continue }
            // cachedRates[code] = «сколько code за 1 USD» = usdInPrimary / xPerForeign
            // (xPerForeign = primary/code; usdInPrimary = primary/USD → результат = code/USD)
            result[code] = usdInPrimary / xPerForeign
        }
        // PRIMARY в USD-base: cachedRates[primary] = usdInPrimary (primary за 1 USD)
        if primary != "USD" {
            result[primary] = usdInPrimary
        }
        return result
    }

    // MARK: - Reset

    func reset() {
        defaults.removeObject(forKey: Keys.rates)
        defaults.removeObject(forKey: Keys.primary)
    }
}
