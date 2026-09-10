//
//  AIPortfolioDigestEntryRow.swift
//  millio
//

import SwiftUI

/// Вход в обзор портфеля с экрана рыночной позиции — только навигация, без действий со сделками.
struct AIPortfolioDigestEntryRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.m) {
                AIChatOrb(diameter: 28, isActive: false)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(L("ai.portfolio.title"))
                        .font(Font.millioCalloutSemibold)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(L("ai.portfolio.entry.subtitle"))
                        .font(Font.millioCaption2Regular)
                        .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(Font.millioCaption2)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FinanceChromeCardBackground())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("accountDetail.portfolioDigest")
    }
}
