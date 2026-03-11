//
//  FinanceChartAxisDateFormatterTests.swift
//  millioTests
//
//  Проверяет фиксированный формат подписей оси X в графике финансов.
//

import Foundation
import Testing
@testable import millio

@Suite("Finance chart axis date formatter")
struct FinanceChartAxisDateFormatterTests {

    @Test("XAxis label uses dd.MM format")
    func testXAxisLabelUsesDayMonthDigits() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!

        let label = FinanceChartAxisDateFormatter.xAxisLabel(for: date)

        #expect(label == "05.03")
    }
}
