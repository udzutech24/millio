import Foundation

/// Перевод баланса ленты счёта-обязательства в остаток долга кредита (спека Р6).
enum LoanOutstanding {

    /// Долг ниже копейки — не долг.
    ///
    /// SwiftData хранит `Decimal` через double: сумма события полного погашения возвращается из
    /// стора с пылью ~1e-9 от миллиона, и без клампа закрытый кредит остался бы «непогашенным» —
    /// кнопка «Досрочно» активной, а график строил бы период на девять десятимиллиардных рубля.
    static func fromLedger(balance: Decimal) -> Decimal {
        let outstanding = max(-balance, .zero)
        return outstanding < Decimal(1) / 100 ? .zero : outstanding
    }
}
