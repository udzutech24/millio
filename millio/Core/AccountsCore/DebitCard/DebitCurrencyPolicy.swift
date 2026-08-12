import Foundation

/// Decimal-only normalization at the debit-card trust boundary.
enum DebitCurrencyPolicy {
    private static let zeroMinorUnits: Set<String> = ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]
    private static let threeMinorUnits: Set<String> = ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"]

    static func fractionDigits(for currency: String) -> Int {
        let code = currency.uppercased()
        if zeroMinorUnits.contains(code) { return 0 }
        if threeMinorUnits.contains(code) { return 3 }
        return 2
    }

    static func round(_ value: Decimal, currency: String) -> Decimal {
        var source = value
        var result = Decimal.zero
        NSDecimalRound(&result, &source, fractionDigits(for: currency), .bankers)
        return result
    }
}
