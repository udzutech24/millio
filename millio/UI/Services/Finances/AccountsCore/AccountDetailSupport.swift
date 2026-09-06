import SwiftUI
import SwiftData

/// Общие для нескольких секций форматтеры сумм карточки счёта.
extension AccountDetailView {
    static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let signedAmountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter
    }()

    func formattedAmount(_ amount: Decimal) -> String {
        let formatter = Self.amountFormatter
        formatter.locale = AppLocalization.currentAppLocale
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }

    func signedAmountText(_ amount: Decimal, type: AccountEventType) -> String {
        let formatter = Self.signedAmountFormatter
        formatter.locale = AppLocalization.currentAppLocale
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }
}
