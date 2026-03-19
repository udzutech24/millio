//
//  InvestmentMarketInputParser.swift
//  millio
//

import Foundation

/// Normalizes market position inputs so symbol selection does not depend on quantity entry.
enum InvestmentMarketInputParser {
    static func quantity(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }

        return AmountInputFormatter.parse(
            trimmed,
            maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits
        )
    }
}
