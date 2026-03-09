import Foundation
import Testing
@testable import millio

struct CashbackMonthTitleFormatterTests {
    @Test("Заголовок месяца в Cashback учитывает locale (en_US)")
    func monthTitleUsesProvidedLocaleForEnglish() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()

        let month = CashbackMonthTitleFormatter.monthText(for: date, locale: Locale(identifier: "en_US"))
        let year = CashbackMonthTitleFormatter.yearText(for: date, locale: Locale(identifier: "en_US"))

        #expect(month == "March")
        #expect(year == "2026")
    }

    @Test("Заголовок месяца в Cashback держит русский месяц в нижнем регистре (ru_RU)")
    func monthTitleLowercasesRussianMonth() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()

        let locale = Locale(identifier: "ru_RU")
        let month = CashbackMonthTitleFormatter.monthText(for: date, locale: locale)
        let year = CashbackMonthTitleFormatter.yearText(for: date, locale: locale)

        #expect(month == "март")
        #expect(year == "2026")
    }
}

