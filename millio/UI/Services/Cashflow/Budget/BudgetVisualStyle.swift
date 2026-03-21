//
//  BudgetVisualStyle.swift
//  millio
//
//  Created by Codex on 21.03.2026.
//

import SwiftUI

/// Семантические токены для budget UI.
/// Суммы остаются нейтральными, а цвет используется только для статуса и прогресса.
enum BudgetColorToken: String, Equatable {
    case primaryText = "FFFFFF"
    case secondaryText = "B8B8BE"
    case calmAccent = "6AA8FF"
    case successAccent = "6DFFC7"
    case warningAccent = "FFD66D"
    case criticalAccent = "FF9B6A"
    case dangerAccent = "FF6666"

    var color: Color {
        switch self {
        case .primaryText:
            return AppColors.textPrimary
        case .secondaryText:
            return Color(hex: rawValue)
        case .calmAccent, .successAccent, .warningAccent, .criticalAccent, .dangerAccent:
            return Color(hex: rawValue)
        }
    }
}

struct BudgetMonthlySummaryStyle: Equatable {
    let valueText: BudgetColorToken
    let usageText: BudgetColorToken
    let progressFill: BudgetColorToken
    let statusText: BudgetColorToken
}

func budgetStatusTintToken(_ status: BudgetStatus) -> BudgetColorToken {
    switch status {
    case .normal:
        return .calmAccent
    case .warning:
        return .warningAccent
    case .critical:
        return .criticalAccent
    case .exceeded:
        return .dangerAccent
    }
}

func budgetMonthlySummaryStyle(
    kind: CashflowCategoryTransactionSheetKind,
    snapshot: BudgetProgressSnapshot
) -> BudgetMonthlySummaryStyle {
    switch kind {
    case .expense:
        let emphasis = budgetStatusTintToken(snapshot.status)
        return BudgetMonthlySummaryStyle(
            valueText: .primaryText,
            usageText: .secondaryText,
            progressFill: emphasis,
            statusText: snapshot.status == .normal ? .secondaryText : emphasis
        )
    case .income:
        let completed = snapshot.remaining <= 0.0000001
        return BudgetMonthlySummaryStyle(
            valueText: .primaryText,
            usageText: .secondaryText,
            progressFill: completed ? .successAccent : .calmAccent,
            statusText: completed ? .successAccent : .secondaryText
        )
    }
}
