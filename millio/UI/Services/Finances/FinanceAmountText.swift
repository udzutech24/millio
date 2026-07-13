//
//  FinanceAmountText.swift
//  millio
//
//  Единая точка для форматирования и маскировки денежных сумм в Finances.
//  Важно: маскировка здесь ориентирована на UI, а не на крипто-приватность.
//

import Foundation

enum FinanceAmountText {
    static func withCurrency(
        value: Double,
        currencySymbol: String,
        isHidden: Bool,
        minimumMaskDigits: Int = 3
    ) -> String {
        let amountText = isHidden
            ? maskedDigits(for: value, minimumDigits: minimumMaskDigits)
            : decimal(value: value)
        return "\(amountText) \(currencySymbol)"
    }

    static func decimal(value: Double, maximumFractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func maskedDigits(for value: Double, minimumDigits: Int = 3) -> String {
        let rounded = Int(value.rounded())
        let digitCount = String(rounded).count
        return String(repeating: "•", count: max(minimumDigits, digitCount))
    }

    static func percent(value: Double, isHidden: Bool, minimumMaskDigits: Int = 3) -> String {
        if isHidden {
            return "\(maskedDigits(for: value, minimumDigits: minimumMaskDigits))%"
        }

        if abs(value) >= 999999 {
            return value > 0 ? "+∞" : "-∞"
        }

        return String(format: "%+.1f%%", value)
    }

    /// Процент не определён (near-zero база: `calculateDeltaPercent` вернул sentinel ±999999).
    /// Решение владельца (2026-07-13): в этом случае процентный лейбл НЕ рендерится вообще —
    /// ни «н/д», ни «—», ни «+∞». Не путать с приватным маскированием (`isHidden`): при
    /// `isHidden` показываем маскированные точки, поэтому «не определён» — только для видимого случая.
    static func isPercentUndefined(value: Double, isHidden: Bool) -> Bool {
        !isHidden && abs(value) >= 999999
    }
}
