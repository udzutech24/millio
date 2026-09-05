import Foundation

/// Форматирование величин на экранах кредита: символ валюты, целые рубли, процент с одним знаком.
///
/// Отдельный тип, а не приватный метод витрины: деталка и график печатают одни и те же числа, и
/// вторая копия правил разъехалась бы с первой. Здесь же единственная точка округления —
/// ядро считает без округлений (спека §4.3).
enum LoanMoneyFormat {
    static func symbol(for currency: String) -> String {
        MonetaCurrency(rawValue: currency)?.symbol ?? currency
    }

    /// «31 063 ₽» — как в hero и в строке списка счетов.
    static func money(_ value: Decimal, currency: String) -> String {
        let text = AccountRowAmountFormatter.text(
            NSDecimalNumber(decimal: value).doubleValue,
            isHidden: false,
            maximumFractionDigits: 0
        )
        return "\(text) \(symbol(for: currency))"
    }

    /// Доля 0...1 в проценты с одним знаком после запятой: «5,2%», «55,3%».
    static func percent(_ share: Decimal) -> String {
        let value = NSDecimalNumber(decimal: share * 100).doubleValue
        let number = value.formatted(
            .number.locale(AppLocalization.currentAppLocale).precision(.fractionLength(1))
        )
        return "\(number)%"
    }
}
