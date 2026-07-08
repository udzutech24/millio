//
//  CashflowInsightsChartStyleTests.swift
//  millioTests
//
//  Created by Codex on 08.03.2026.
//

import Foundation
import CoreGraphics
import Foundation
import Testing
@testable import millio

struct CashflowInsightsChartStyleTests {
    @Test("12-period chart uses denser Apple-style spacing")
    func fullScreenMetricsBecomeDenserForTwelvePeriods() {
        let compact = CashflowInsightsChartStyle.fullScreenMetrics(
            containerWidth: 360,
            barCount: 12,
            visiblePeriods: 12
        )
        let relaxed = CashflowInsightsChartStyle.fullScreenMetrics(
            containerWidth: 360,
            barCount: 4,
            visiblePeriods: 4
        )

        #expect(compact.spacing < relaxed.spacing)
        #expect(compact.barWidth < relaxed.barWidth)
        #expect(compact.maxBarHeight > relaxed.maxBarHeight)
    }

    @Test("Compact group width never shrinks below the configured minimum")
    func compactGroupWidthHonorsMinimum() {
        let width = CashflowInsightsChartStyle.compactGroupWidth(
            containerWidth: 200,
            barCount: 8,
            minimumGroupWidth: 28
        )

        #expect(width == 28)
    }

    @Test("4-period full screen chart stretches groups to fit viewport width")
    func fullScreenMetricsFitViewportForShortRanges() {
        let metrics = CashflowInsightsChartStyle.fullScreenMetrics(
            containerWidth: 420,
            barCount: 4,
            visiblePeriods: 4
        )
        let expectedRawWidth: CGFloat = (420 - 2 - 10 * 3) / 4

        #expect(abs(metrics.groupWidth - expectedRawWidth) < 0.0001)
        #expect(metrics.barWidth <= 28)
        #expect(metrics.labelFontSize <= 13)
    }

    @Test("Month bar label uses abbreviated localized format")
    func monthBarLabelUsesShortMonthFormat() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()

        let english = CashflowInsightsChartStyle.barLabel(
            for: date,
            granularity: .month,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let russian = CashflowInsightsChartStyle.barLabel(
            for: date,
            granularity: .month,
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        )

        #expect(english == "Mar 26")
        #expect(russian.contains("26"))
        #expect(russian != "Март'26")
    }
}
