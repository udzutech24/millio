//
//  CashflowInsightsChartStyle.swift
//  millio
//
//  Визуальные метрики и подписи графика cashflow:
//  выносим расчеты размеров и форматирование label отдельно,
//  чтобы full-screen график не расползался по вертикали
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
        let spacing: CGFloat = compactMode ? 6 : 10
        // Keep more usable width in full-screen mode so bars fill the viewport.
        let availableWidth = max(containerWidth - 2, 0)
        let rawGroupWidth = max(
            (availableWidth - spacing * CGFloat(count - 1)) / CGFloat(count),
            1
        )
        let shouldFitViewport = !compactMode && visiblePeriods <= 4 && count <= visiblePeriods
        let groupWidth: CGFloat = shouldFitViewport
            ? rawGroupWidth
            : min(rawGroupWidth, compactMode ? 64 : 78)

        return CashflowInsightsChartMetrics(
            spacing: spacing,
            groupWidth: groupWidth,
            barWidth: min(max(compactMode ? 12 : 16, groupWidth * (compactMode ? 0.30 : 0.34)), compactMode ? 24 : 28),
            labelFontSize: max(10, min(compactMode ? 12 : 13, groupWidth * (compactMode ? 0.18 : 0.20))),
            maxBarHeight: compactMode ? 180 : 168,
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

    static func barLabel(
        for date: Date,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch granularity {
        case .year:
            return String(calendar.component(.year, from: date))
        case .month:
            let monthFormatter = DateFormatter()
            monthFormatter.locale = locale
            let monthIndex = calendar.component(.month, from: date) - 1
            let monthSymbols = monthFormatter.shortStandaloneMonthSymbols ?? monthFormatter.shortMonthSymbols ?? []
            let fallbackSymbols = monthFormatter.shortMonthSymbols ?? []
            let month: String
            if monthSymbols.indices.contains(monthIndex) {
                month = monthSymbols[monthIndex]
            } else if fallbackSymbols.indices.contains(monthIndex) {
                month = fallbackSymbols[monthIndex]
            } else {
                month = monthFormatter.string(from: date)
            }

            let yearFormatter = DateFormatter()
            yearFormatter.locale = locale
            yearFormatter.dateFormat = "yy"
            return "\(month.capitalized(with: locale)) \(yearFormatter.string(from: date))"
        case .week:
            return "W\(calendar.component(.weekOfYear, from: date))"
        }
    }
}
