import Foundation

/// Formats month/year titles in the cashback toolbar.
///
/// Important:
/// - Use an explicit `locale` derived from the app language (not a hardcoded one).
/// - Keep Russian month names lowercase to match the existing UI style.
enum CashbackMonthTitleFormatter {
    static func monthText(for date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "LLLL"

        let month = formatter.string(from: date)
        if isRussian(locale) {
            return month.lowercased(with: locale)
        }
        return month
    }

    static func yearText(for date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private static func isRussian(_ locale: Locale) -> Bool {
        if #available(iOS 16.0, *),
           let code = locale.language.languageCode?.identifier.lowercased() {
            return code == "ru"
        }
        return locale.identifier.lowercased().hasPrefix("ru")
    }
}

