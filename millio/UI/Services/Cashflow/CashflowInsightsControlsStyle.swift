//
//  CashflowInsightsControlsStyle.swift
//  millio
//
//  UI-метрики для контролов графика cashflow (периоды/переключалки).
//  Отдельно от `CashflowInsightsChartStyle`, чтобы:
//  - не смешивать расчеты баров и layout контролов,
//  - иметь стабильные, тестируемые значения,
//  - быстро чинить проблемы пересечений/клиппинга в разных режимах (compact vs full screen).
//

import CoreGraphics

struct CashflowInsightsGranularityPickerMetrics: Equatable {
    let fontSize: CGFloat
    let itemVerticalPadding: CGFloat
    let containerPadding: CGFloat
    let outerPadding: CGFloat
}

enum CashflowInsightsControlsStyle {
    /// Высота блока баров на основном экране cashflow.
    /// Должна включать и бар-треки, и подписи (лейблы) под ними, иначе подписи рисуются за пределами frame
    /// и пересекаются с переключателем гранулярности.
    static let compactBarsHeight: CGFloat = 200

    static func granularityPickerMetrics(isFullScreen: Bool) -> CashflowInsightsGranularityPickerMetrics {
        if isFullScreen {
            return CashflowInsightsGranularityPickerMetrics(
                fontSize: 12,
                itemVerticalPadding: 7,
                containerPadding: 3,
                outerPadding: 0
            )
        }

        return CashflowInsightsGranularityPickerMetrics(
            fontSize: 10,
            itemVerticalPadding: 2,
            containerPadding: 1,
            outerPadding: 0
        )
    }
}

