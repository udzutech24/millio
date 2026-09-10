//
//  AIPeriodSummaryFormatting.swift
//  millio
//

import Foundation

/// Форматирование сводки: заголовок периода и денежные строки.
/// Суммы идут через общий `AmountInputFormatter` — своего форматтера у экрана нет.
enum AIPeriodSummaryFormatting {
    static func periodTitle(
        for period: AIPeriodSummaryPeriod,
        calendar: Calendar = .current,
        locale: Locale = AppLocalization.currentAppLocale
    ) -> String {
        let start = period.start(calendar: calendar)
        switch period.kind {
        case .month:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.setLocalizedDateFormatFromTemplate("LLLL y")
            return formatter.string(from: start).capitalized(with: locale)
        case .quarter:
            let month = calendar.component(.month, from: start)
            let quarter = (month - 1) / 3 + 1
            let year = calendar.component(.year, from: start)
            return String(format: L("ai.summary.period.quarter_format"), "\(quarter)", "\(year)")
        }
    }

    static func money(_ value: Double, currencyCode: String, isHidden: Bool = false) -> String {
        let symbol = MonetaCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
        guard !isHidden else { return "••• \(symbol)" }
        return "\(grouped(abs(value))) \(symbol)"
    }

    static func signedMoney(_ value: Double, currencyCode: String, isHidden: Bool = false) -> String {
        let symbol = MonetaCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
        guard !isHidden else { return "••• \(symbol)" }
        let sign = value.rounded() < 0 ? "-" : "+"
        return "\(sign)\(grouped(abs(value))) \(symbol)"
    }

    /// Доля полосы: длиннее из двух сумм занимает всю ширину, вторая — пропорционально.
    static func barShare(_ value: Double, peak: Double) -> Double {
        guard peak > 0, value > 0 else { return 0 }
        return min(1, value / peak)
    }

    /// `AmountInputFormatter.plainString` отдаёт пустую строку для нуля — подставляем явный «0»,
    /// иначе в карточке вместо суммы был бы голый символ валюты.
    private static func grouped(_ value: Double) -> String {
        let plain = AmountInputFormatter.plainString(from: value.rounded(), maxFractionDigits: 0)
        return AmountInputFormatter.display(plain.isEmpty ? "0" : plain, maxFractionDigits: 0)
    }
}
