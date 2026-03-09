//
//  CashflowInsightsChartStyleTests.swift
//  millioTests
//
//  Created by Codex on 08.03.2026.
//

import CoreGraphics
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
        #expect(compact.maxBarHeight < relaxed.maxBarHeight)
    }

    @Test("Bar height keeps tiny values visible without breaking zero state")
    func visibleBarHeightUsesMinimumOnlyForNonZeroValues() {
        let selected = CashflowInsightsChartStyle.visibleBarHeight(
            value: 1,
            maxValue: 100,
            maxBarHeight: 220,
            isSelected: true
        )
        let unselected = CashflowInsightsChartStyle.visibleBarHeight(
            value: 1,
            maxValue: 100,
            maxBarHeight: 220,
            isSelected: false
        )
        let zero = CashflowInsightsChartStyle.visibleBarHeight(
            value: 0,
            maxValue: 100,
            maxBarHeight: 220,
            isSelected: false
        )

        #expect(selected == 20)
        #expect(unselected == 16)
        #expect(zero == 0)
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
}
