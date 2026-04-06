//
//  MainConverterDashboardSupport.swift
//  millio
//
//  Created by Codex on 04.04.2026.
//

import Foundation

struct MainConverterDashboardQuote: Equatable {
    let targetCode: String
    let baseSummary: String
    let rateSummary: String
}

enum MainConverterDashboardSupport {
    private static let fallbackTargetCodes = ["USD", "EUR", "CNY", "KZT"]

    static func quoteTargets(
        primaryCode: String,
        favoriteCodes: [String],
        limit: Int = 3
    ) -> [String] {
        let primary = primaryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let favorites = favoriteCodes.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        let defaults = fallbackTargetCodes.filter { $0 != primary }

        var seen = Set<String>()
        let merged = (favorites + defaults).filter { code in
            guard !code.isEmpty, code != primary, !seen.contains(code) else { return false }
            seen.insert(code)
            return true
        }

        return Array(merged.prefix(max(0, limit)))
    }

    static func quotes(
        primaryCode: String,
        favoriteCodes: [String],
        rates: [String: Double],
        locale: Locale,
        limit: Int = 3
    ) -> [MainConverterDashboardQuote] {
        let primary = primaryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        return quoteTargets(primaryCode: primary, favoriteCodes: favoriteCodes, limit: limit).map { target in
            MainConverterDashboardQuote(
                targetCode: target,
                baseSummary: "1 \(primary)",
                rateSummary: rateSummary(
                    primaryCode: primary,
                    targetCode: target,
                    rates: rates,
                    locale: locale
                )
            )
        }
    }

    static func rateSummary(
        primaryCode: String,
        targetCode: String,
        rates: [String: Double],
        locale: Locale
    ) -> String {
        guard let converted = CurrencyWidgetShared.convert(
            amount: 1,
            from: primaryCode,
            to: targetCode,
            rates: rates
        ) else {
            return "— \(targetCode)"
        }

        return "\(CurrencyWidgetShared.formatValue(converted, maxFractionDigits: 4, locale: locale)) \(targetCode)"
    }
}
