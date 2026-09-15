//
//  DateLocaleFormattingTests.swift
//  millioTests
//
//  Регрессия на релиз-фикс 2.0: месяцы/дни недели должны идти по языку приложения
//  (LanguageManager), а не по региону устройства. Баг: DateFormatter/Date.FormatStyle
//  без явной .locale() всегда брали Locale.current (регион устройства), поэтому при
//  English UI на RU-устройстве месяцы оставались русскими ("сен" вместо "Sep").
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct DateLocaleFormattingTests {
    /// Дата в сентябре — месяц, где английское и русское написание визуально различимы.
    private static let sampleDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test("Date.FormatStyle с AppLocalization.currentAppLocale даёт английский месяц при English UI")
    @MainActor
    func dateTimeFormatFollowsAppLanguageNotDeviceRegion() {
        AppLanguageTestSupport.withLockedAppLanguage {
            let previousLanguage = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(previousLanguage) }

            LanguageManager.shared.setLanguage(.english)
            let englishMonth = Self.sampleDate.formatted(
                .dateTime.month(.abbreviated).locale(AppLocalization.currentAppLocale)
            )
            #expect(englishMonth == "Sep")

            LanguageManager.shared.setLanguage(.russian)
            let russianMonth = Self.sampleDate.formatted(
                .dateTime.month(.abbreviated).locale(AppLocalization.currentAppLocale)
            )
            #expect(russianMonth != englishMonth)
            #expect(russianMonth.lowercased().contains("сен"))
        }
    }

    @Test("DateFormatter с AppLocalization.currentAppLocale даёт английский месяц при English UI")
    @MainActor
    func dateFormatterFollowsAppLanguageNotDeviceRegion() {
        AppLanguageTestSupport.withLockedAppLanguage {
            let previousLanguage = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(previousLanguage) }

            LanguageManager.shared.setLanguage(.english)
            let formatter = DateFormatter()
            formatter.locale = AppLocalization.currentAppLocale
            formatter.dateFormat = "MMM"
            #expect(formatter.string(from: Self.sampleDate) == "Sep")

            LanguageManager.shared.setLanguage(.russian)
            formatter.locale = AppLocalization.currentAppLocale
            let russianMonth = formatter.string(from: Self.sampleDate)
            #expect(russianMonth != "Sep")
        }
    }
}
