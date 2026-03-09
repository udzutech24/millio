//
//  CashflowLocalizationRegressionTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import Foundation
import Testing
@testable import millio

struct CashflowLocalizationRegressionTests {
    @Test("Russian locale contains localized Cashflow labels")
    func russianLocaleHasCashflowTranslations() {
        let locale = Locale(identifier: "ru_RU")

        #expect(AppLocalization.string("cashflow.stats.assets_start", locale: locale) == "Активы на начало периода")
        #expect(AppLocalization.string("cashflow.stats.assets_end", locale: locale) == "Активы на конец периода")
        #expect(AppLocalization.string("cashflow.stats.expenses", locale: locale) == "Расходы")
        #expect(AppLocalization.string("cashflow.quick_action.transfer", locale: locale) == "Перевод")
        #expect(AppLocalization.string("cashflow.chart.expand", locale: locale) == "Развернуть график")

        #expect(AppLocalization.string("Income", locale: locale) == "Доход")
        #expect(AppLocalization.string("Expense", locale: locale) == "Расход")
        #expect(AppLocalization.string("Result", locale: locale) == "Результат")
        #expect(AppLocalization.string("Week", locale: locale) == "Неделя")
        #expect(AppLocalization.string("Visible range", locale: locale) == "Окно")
    }

    @Test("Period title uses localized quarter format")
    func quarterTitleUsesLocalizedFormat() async {
        let locale = Locale(identifier: "ru_RU")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let date = DateComponents(calendar: calendar, year: 2026, month: 3, day: 9).date!
        let title = await MainActor.run {
            CashflowViewModel.makePeriodHeaderTitle(
                chartPeriod: .specificQuarter,
                selectedMonth: date,
                selectedQuarter: date,
                selectedYear: date,
                customStartDate: date,
                customEndDate: date,
                calendar: calendar,
                locale: locale
            )
        }

        #expect(title == "1 кв. 2026")
    }

    @Test("Custom period title normalizes start and end dates")
    func customTitleNormalizesStartAndEnd() async {
        let locale = Locale(identifier: "ru_RU")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let later = DateComponents(calendar: calendar, year: 2026, month: 3, day: 9).date!
        let earlier = DateComponents(calendar: calendar, year: 2026, month: 2, day: 7).date!

        let title = await MainActor.run {
            CashflowViewModel.makePeriodHeaderTitle(
                chartPeriod: .custom,
                selectedMonth: later,
                selectedQuarter: later,
                selectedYear: later,
                customStartDate: later,
                customEndDate: earlier,
                calendar: calendar,
                locale: locale
            )
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMM y")
        let expected = "\(formatter.string(from: earlier)) — \(formatter.string(from: later))"

        #expect(title == expected)
    }
}
