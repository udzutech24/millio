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
    static let compactBarsHeight: CGFloat = 164
    static let compactBarsAreaHeight: CGFloat = 104
    static let minimumCompactLabelsAreaHeight: CGFloat = 44

    static var compactLabelsAreaHeight: CGFloat {
        compactBarsHeight - compactBarsAreaHeight
    }

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
            // Увеличиваем тач-таргет переключателя (Год/Месяц/Week) в compact режиме:
            // визуально "толще" и проще попасть пальцем, но без чрезмерного роста UI.
            itemVerticalPadding: 6,
            containerPadding: 2,
            outerPadding: 0
        )
    }
}
