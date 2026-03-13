//
//  CashflowViewModelPeriodRangeTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import Foundation
import Testing
@testable import millio

struct CashflowViewModelPeriodRangeTests {
    @Test("Default period: current month to reference day")
    func defaultPeriodIsCurrentMonthToReferenceDay() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = Self.date(2026, 3, 9)

        let range = CashflowViewModel.defaultPeriodRange(
            referenceDate: reference,
            calendar: calendar
        )

        #expect(range.start == Self.date(2026, 3, 1))
        #expect(range.end == Self.date(2026, 3, 9))
    }

    @Test("Clamp custom period: end date is capped by reference day")
    func clampCustomPeriodCapsFutureEnd() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = Self.date(2026, 3, 9)

        let range = CashflowViewModel.clampCustomPeriodRange(
            start: Self.date(2026, 3, 1),
            end: Self.date(2026, 4, 1),
            referenceDate: reference,
            calendar: calendar
        )

        #expect(range.start == Self.date(2026, 3, 1))
        #expect(range.end == Self.date(2026, 3, 9))
    }

    @Test("Clamp custom period: start is never after end")
    func clampCustomPeriodEnsuresStartNotAfterEnd() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = Self.date(2026, 3, 9)

        let range = CashflowViewModel.clampCustomPeriodRange(
            start: Self.date(2026, 3, 12),
            end: Self.date(2026, 3, 10),
            referenceDate: reference,
            calendar: calendar
        )

        #expect(range.start == Self.date(2026, 3, 9))
        #expect(range.end == Self.date(2026, 3, 9))
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}
