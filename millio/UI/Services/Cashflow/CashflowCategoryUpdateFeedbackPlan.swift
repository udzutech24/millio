//
//  CashflowCategoryUpdateFeedbackPlan.swift
//  millio
//
//  Created by Codex on 16.03.2026.
//

import Foundation

/// Описывает визуальный feedback для категории после изменения суммы.
/// Логику держим отдельно от SwiftUI, чтобы её можно было покрыть unit-тестами.
struct CashflowCategoryUpdateFeedbackPlan: Equatable {
    let categoryRawValue: String
    let previousTotal: Double
    let updatedTotal: Double

    var delta: Double {
        updatedTotal - previousTotal
    }

    static func make(
        for categoryRawValue: String?,
        previousTotals: [String: Double],
        updatedTotals: [String: Double],
        epsilon: Double = 0.0000001
    ) -> CashflowCategoryUpdateFeedbackPlan? {
        guard let categoryRawValue else { return nil }

        let previousTotal = previousTotals[categoryRawValue] ?? 0
        let updatedTotal = updatedTotals[categoryRawValue] ?? 0
        guard abs(updatedTotal - previousTotal) > epsilon else { return nil }

        return CashflowCategoryUpdateFeedbackPlan(
            categoryRawValue: categoryRawValue,
            previousTotal: previousTotal,
            updatedTotal: updatedTotal
        )
    }
}
