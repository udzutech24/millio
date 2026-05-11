//
//  QuickActionsWidget.swift
//  millio
//

import SwiftUI

struct QuickActionsWidget: View {
    let onAddIncome: () -> Void
    let onAddExpense: () -> Void
    let onAddTransfer: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(
                title: L("main.quick_action.income"),
                icon: QuickActionIcons.income,
                gradientColors: AppColors.incomeActionGradient,
                action: onAddIncome
            )
            actionButton(
                title: L("main.quick_action.expense"),
                icon: QuickActionIcons.expense,
                gradientColors: AppColors.expenseActionGradient,
                action: onAddExpense
            )
            actionButton(
                title: L("cashflow.quick_action.transfer"),
                icon: QuickActionIcons.transfer,
                gradientColors: AppColors.transferActionGradient,
                action: onAddTransfer
            )
        }
        .frame(height: 64)
    }

    private func actionButton(
        title: String,
        icon: String,
        gradientColors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        let accent = LinearGradient(
            colors: gradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
        return Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 38, height: 38)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
