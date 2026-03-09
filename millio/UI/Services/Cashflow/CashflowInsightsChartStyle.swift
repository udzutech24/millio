//
//  CashflowInsightsChartStyle.swift
//  millio
//
//  Визуальные метрики графика cashflow:
//  выносим расчеты размеров отдельно, чтобы стиль оставался предсказуемым
//  и его можно было покрыть unit-тестами.
//

import CoreGraphics
import Foundation

struct CashflowInsightsChartMetrics: Equatable {
    let spacing: CGFloat
    let groupWidth: CGFloat
    let barWidth: CGFloat
    let labelFontSize: CGFloat
    let maxBarHeight: CGFloat
    let columnPadding: CGFloat
    let barSpacing: CGFloat
}

enum CashflowInsightsChartStyle {
    private static let epsilon = 0.0000001

    static func fullScreenMetrics(
        containerWidth: CGFloat,
        barCount: Int,
        visiblePeriods: Int
    ) -> CashflowInsightsChartMetrics {
        let count = max(barCount, 1)
        let compactMode = visiblePeriods > 4
        let spacing: CGFloat = compactMode ? 6 : 12
        let availableWidth = max(containerWidth - 12, 0)
        let groupWidth = max(
            (availableWidth - spacing * CGFloat(count - 1)) / CGFloat(count),
            1
        )

        return CashflowInsightsChartMetrics(
            spacing: spacing,
            groupWidth: groupWidth,
            barWidth: min(max(compactMode ? 8 : 10, groupWidth * (compactMode ? 0.22 : 0.26)), compactMode ? 18 : 24),
            labelFontSize: max(10, min(16, groupWidth * (compactMode ? 0.22 : 0.25))),
            maxBarHeight: compactMode ? 188 : 228,
            columnPadding: compactMode ? 8 : 12,
            barSpacing: compactMode ? 6 : 8
        )
    }

    static func compactGroupWidth(
        containerWidth: CGFloat,
        barCount: Int,
        minimumGroupWidth: CGFloat
    ) -> CGFloat {
        max((containerWidth - 24) / CGFloat(max(barCount, 1)), minimumGroupWidth)
    }

    static func visibleBarHeight(
        value: Double,
        maxValue: Double,
        maxBarHeight: CGFloat,
        isSelected: Bool
    ) -> CGFloat {
        guard value > epsilon else { return 0 }
        let normalizedHeight = maxValue > epsilon ? CGFloat(value / maxValue) : 0
        let minimumHeight: CGFloat = isSelected ? 20 : 16
        return max(minimumHeight, normalizedHeight * maxBarHeight)
    }
}
