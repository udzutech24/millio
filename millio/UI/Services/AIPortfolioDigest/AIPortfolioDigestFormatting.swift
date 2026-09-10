//
//  AIPortfolioDigestFormatting.swift
//  millio
//

import Foundation

/// Форматирование дайджеста — теми же форматтерами, что hero рыночной позиции, иначе цифры
/// двух экранов разошлись бы в копейках и знаках после запятой.
enum AIPortfolioDigestFormatting {
    static func money(_ value: Decimal, currency: String, isHidden: Bool = false) -> String {
        let symbol = MonetaCurrency(rawValue: currency)?.symbol ?? currency
        guard !isHidden else { return "••• \(symbol)" }
        return DepositAmountTextFormatter.string(
            value,
            currency: currency,
            symbol: symbol,
            locale: AppLocalization.currentAppLocale
        )
    }

    static func signedMoney(_ value: Decimal, currency: String, isHidden: Bool = false) -> String {
        guard !isHidden else { return money(value, currency: currency, isHidden: true) }
        return (value > 0 ? "+" : "") + money(value, currency: currency)
    }

    static func percent(_ value: Decimal) -> String {
        String(format: "%.2f%%", NSDecimalNumber(decimal: value).doubleValue)
    }

    static func signedPercent(_ value: Decimal) -> String {
        (value > 0 ? "+" : "") + percent(value)
    }
}
