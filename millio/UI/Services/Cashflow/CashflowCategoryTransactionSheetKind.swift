//
//  CashflowCategoryTransactionSheetKind.swift
//  millio
//

import SwiftUI

enum CashflowCategoryTransactionSheetKind {
    case income
    case expense

    var transactionType: CashflowTransactionType {
        switch self {
        case .income: return .income
        case .expense: return .expense
        }
    }

    var categoryKind: CashflowCategoryKind {
        switch self {
        case .income: return .income
        case .expense: return .expense
        }
    }

    var navigationTitle: String {
        switch self {
        case .income: return String(localized: "cashflow.operation.new_income")
        case .expense: return String(localized: "cashflow.operation.new_expense")
        }
    }

    var monthlyTotalTitle: String {
        switch self {
        case .income: return String(localized: "cashflow.operation.total_income_for_month")
        case .expense: return String(localized: "cashflow.operation.total_expense_for_month")
        }
    }

    /// Фильтр истории, соответствующий текущему типу листа.
    var historyFilter: CashflowHistoryTypeFilter {
        switch self {
        case .income: return .income
        case .expense: return .expense
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .income: return AppColors.incomeGradient
        case .expense: return AppColors.expenseGradient
        }
    }

    var accentColor: Color {
        gradientColors.first ?? AppColors.brandPrimary
    }

    var strokeGradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    func amountColor(for value: Double) -> Color {
        switch cashflowValueTone(for: value) {
        case .neutral:
            return Color.white.opacity(0.78)
        case .positive:
            return self == .income ? Color(hex: "6DFFC7") : Color(hex: "FF6666")
        case .negative:
            return self == .income ? Color(hex: "FF6666") : Color(hex: "6DFFC7")
        }
    }
}
