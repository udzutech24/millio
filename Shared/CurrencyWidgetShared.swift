//
//  CurrencyWidgetShared.swift
//  millio
//
//  Created by Codex on 24.02.2026.
//

import Foundation

enum CurrencyWidgetShared {
    static let appGroupID = "group.com.millio.app"
    static let deepLinkScheme = "millio"
    static let deepLinkHost = "widget"

    enum Keys {
        static let selectedCodes = "conv_selected_codes"
        static let activeCode = "conv_active_code"
        static let inputText = "conv_input_text"
        static let rateSource = "conv_rate_source"
        static let primaryCurrencyCode = "primaryCurrencyCode"

        static func cachedRates(for sourceRaw: String) -> String {
            "conv_cached_rates_\(sourceRaw)"
        }

        static func lastRatesTimestamp(for sourceRaw: String) -> String {
            "conv_last_rates_ts_\(sourceRaw)"
        }
    }

    struct ConverterSnapshot: Equatable {
        let selectedCodes: [String]
        let activeCode: String
        let primaryCode: String
        let inputText: String
        let rateSourceRaw: String
        let rates: [String: Double]
        let lastUpdatedAt: Date?

        static func load(from defaults: UserDefaults) -> Self {
            let selectedCodes = CurrencyWidgetShared.normalizedCodes(
                from: defaults.string(forKey: Keys.selectedCodes)
                    ?? "RUB,USD,EUR,TRY,GBP,KZT"
            )

            let rateSourceRaw = defaults.string(forKey: Keys.rateSource) ?? "millio"
            let ratesKey = Keys.cachedRates(for: rateSourceRaw)
            let lastRatesKey = Keys.lastRatesTimestamp(for: rateSourceRaw)

            let rates = CurrencyWidgetShared.decodeRates(from: defaults.object(forKey: ratesKey))
            let inputText = defaults.string(forKey: Keys.inputText) ?? "1200"

            let configuredActive = defaults.string(forKey: Keys.activeCode)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let fallbackActive = selectedCodes.first ?? "USD"
            let activeCode = configuredActive.flatMap { code in
                selectedCodes.contains(code) ? code : nil
            } ?? fallbackActive
            let primaryCode = defaults.string(forKey: Keys.primaryCurrencyCode)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .nonEmpty ?? activeCode

            let lastUpdatedAt: Date?
            let timestamp = defaults.double(forKey: lastRatesKey)
            if timestamp > 0 {
                lastUpdatedAt = Date(timeIntervalSince1970: timestamp)
            } else {
                lastUpdatedAt = nil
            }

            return ConverterSnapshot(
                selectedCodes: selectedCodes,
                activeCode: activeCode,
                primaryCode: primaryCode,
                inputText: inputText,
                rateSourceRaw: rateSourceRaw,
                rates: rates,
                lastUpdatedAt: lastUpdatedAt
            )
        }
    }

    enum DeepLinkAction: String, CaseIterable {
        case openConverter = "open_converter"
        case addExpense = "add_expense"
        case addIncome = "add_income"
    }

    static func deepLinkURL(for action: DeepLinkAction) -> URL? {
        var components = URLComponents()
        components.scheme = deepLinkScheme
        components.host = deepLinkHost
        components.path = "/action"
        components.queryItems = [URLQueryItem(name: "type", value: action.rawValue)]
        return components.url
    }

    static func deepLinkAction(from url: URL) -> DeepLinkAction? {
        guard url.scheme?.lowercased() == deepLinkScheme else { return nil }
        guard url.host?.lowercased() == deepLinkHost else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let type = components.queryItems?.first(where: { $0.name == "type" })?.value,
           let action = DeepLinkAction(rawValue: type.lowercased()) {
            return action
        }

        let lastPath = url.pathComponents.last?.lowercased() ?? ""
        switch lastPath {
        case "open_converter":
            return .openConverter
        case "add_expense":
            return .addExpense
        case "add_income":
            return .addIncome
        default:
            return nil
        }
    }

    static func normalizedCodes(from rawValue: String?) -> [String] {
        let raw = rawValue ?? ""
        var seen = Set<String>()
        var result: [String] = []

        for code in raw.split(separator: ",") {
            let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        if result.isEmpty {
            return ["USD"]
        }

        return result
    }

    static func decodeRates(from rawValue: Any?) -> [String: Double] {
        guard let rawValue else {
            return ["USD": 1.0]
        }

        var result: [String: Double] = [:]

        if let rates = rawValue as? [String: Double] {
            for (code, value) in rates where value > 0 {
                result[code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] = value
            }
        } else if let rates = rawValue as? [String: NSNumber] {
            for (code, value) in rates where value.doubleValue > 0 {
                result[code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] = value.doubleValue
            }
        } else if let rates = rawValue as? [String: Any] {
            for (code, value) in rates {
                let resolved: Double?
                if let doubleValue = value as? Double {
                    resolved = doubleValue
                } else if let numberValue = value as? NSNumber {
                    resolved = numberValue.doubleValue
                } else {
                    resolved = nil
                }

                if let resolved, resolved > 0 {
                    result[code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] = resolved
                }
            }
        }

        result["USD"] = 1.0

        return result
    }

    static func parseAmount(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    static func convert(amount: Double, from sourceCode: String, to targetCode: String, rates: [String: Double]) -> Double? {
        let fromCode = sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let toCode = targetCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if fromCode == toCode {
            return amount
        }

        let normalizedRates = rates.isEmpty ? ["USD": 1.0] : rates

        let fromRate: Double?
        if fromCode == "USD" {
            fromRate = 1.0
        } else {
            fromRate = normalizedRates[fromCode]
        }

        let toRate: Double?
        if toCode == "USD" {
            toRate = 1.0
        } else {
            toRate = normalizedRates[toCode]
        }

        guard let fromRate, fromRate > 0, let toRate, toRate > 0 else {
            return nil
        }

        let inUSD = fromCode == "USD" ? amount : amount / fromRate
        return toCode == "USD" ? inUSD : inUSD * toRate
    }

    static func formatValue(_ value: Double, maxFractionDigits: Int = 4, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = max(0, min(maxFractionDigits, 8))
        formatter.locale = locale

        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
