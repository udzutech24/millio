//
//  CashflowChartVariantALayout.swift
//  millio
//
//  Редизайн графика Cashflow — вариант A (зеркальная столбчатая, §7.6 плана).
//  Чистые вычисления геометрии: высоты баров и точки net-линии на ЕДИНОЙ шкале
//  для всех видимых месяцев — вынесены из View, чтобы покрыть unit-тестами
//  (без масштаба каждый месяц выглядел «плиткой» своего размера — старый баг).
//

import CoreGraphics
import Foundation

/// Геометрия одного бара графика "вариант A" — уже готовые высоты в системе координат View.
struct CashflowChartVariantABar: Equatable {
    let periodStart: Date
    /// Высота столбца дохода (0...halfHeight), строго пропорциональна общей шкале.
    let incomeHeight: CGFloat
    /// Высота столбца расхода (0...halfHeight), строго пропорциональна общей шкале.
    let expenseHeight: CGFloat
    /// Смещение точки net-линии от нулевой оси: положительное — вверх, отрицательное — вниз.
    /// Уже clamp'нуто в диапазон [-halfHeight, halfHeight].
    let netOffset: CGFloat
    let isPositiveNet: Bool
}

/// Чистая политика геометрии для графика Cashflow "вариант A".
/// Единая шкала (max из доходов/расходов всех видимых баров) — иначе месяцы нельзя сравнить.
enum CashflowChartVariantALayout {
    private static let epsilon = 0.0000001
    /// Минимальная видимая высота ненулевого бара — иначе крошечная сумма пропадает совсем.
    static let minimumVisibleHeight: CGFloat = 2

    /// Максимум по модулю среди всех income/expense видимых баров — общий масштаб полотна.
    /// Пустой список или все нули → 1 (защита от деления на ноль, бар останется нулевой высоты).
    static func scale(bars: [CashflowInsightsBar]) -> Double {
        let values = bars.flatMap { [abs($0.income), abs($0.expense)] }
        let maxValue = values.max() ?? 0
        return maxValue > epsilon ? maxValue : 1
    }

    static func barLayouts(
        bars: [CashflowInsightsBar],
        halfHeight: CGFloat
    ) -> [CashflowChartVariantABar] {
        guard halfHeight > 0 else {
            return bars.map {
                CashflowChartVariantABar(
                    periodStart: $0.periodStart,
                    incomeHeight: 0,
                    expenseHeight: 0,
                    netOffset: 0,
                    isPositiveNet: $0.income >= $0.expense
                )
            }
        }
        let maxValue = scale(bars: bars)
        return bars.map { bar in
            let income = proportionalHeight(bar.income, maxValue: maxValue, halfHeight: halfHeight)
            let expense = proportionalHeight(bar.expense, maxValue: maxValue, halfHeight: halfHeight)
            let net = bar.income - bar.expense
            let rawNetOffset = maxValue > epsilon ? CGFloat(net / maxValue) * halfHeight : 0
            let netOffset = max(min(rawNetOffset, halfHeight), -halfHeight)
            return CashflowChartVariantABar(
                periodStart: bar.periodStart,
                incomeHeight: income,
                expenseHeight: expense,
                netOffset: netOffset,
                isPositiveNet: net >= 0
            )
        }
    }

    /// Высота столбца строго пропорциональна значению относительно общей шкалы.
    /// Нулевые/пустые месяцы дают 0 (совсем без бара) — не путать с "неразличимо маленьким".
    private static func proportionalHeight(
        _ value: Double,
        maxValue: Double,
        halfHeight: CGFloat
    ) -> CGFloat {
        let magnitude = abs(value)
        guard magnitude > epsilon, maxValue > epsilon else { return 0 }
        let normalized = CGFloat(magnitude / maxValue) * halfHeight
        return max(normalized, minimumVisibleHeight)
    }
}
