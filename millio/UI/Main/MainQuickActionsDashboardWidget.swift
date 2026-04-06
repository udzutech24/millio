//
//  MainQuickActionsDashboardWidget.swift
//  millio
//
//  Created by Codex on 04.04.2026.
//

import SwiftUI

struct MainQuickActionsDashboardWidget: View {
    let compactMode: Bool
    let incomeTitle: String
    let expenseTitle: String
    let historyTitle: String
    let historySubtitle: String
    let onIncomeTap: () -> Void
    let onExpenseTap: () -> Void
    let onHistoryTap: () -> Void

    private let accent = AppColors.brandPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: compactMode ? 14 : 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MainLocalization.dashboardWidgetTitle(for: .quickActions))
                        .font(.system(size: compactMode ? 17 : 21, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    if !compactMode {
                        Text(MainLocalization.dashboardWidgetSubtitle(for: .quickActions))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)
            }

            HStack(spacing: 10) {
                quickActionTile(
                    title: incomeTitle,
                    systemName: QuickActionIcons.income,
                    gradient: AppColors.incomeGradient,
                    action: onIncomeTap
                )

                quickActionTile(
                    title: expenseTitle,
                    systemName: QuickActionIcons.expense,
                    gradient: AppColors.expenseGradient,
                    action: onExpenseTap
                )
            }

            Button(action: onHistoryTap) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .frame(width: compactMode ? 34 : 38, height: compactMode ? 34 : 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(historyTitle)
                            .font(.system(size: compactMode ? 14 : 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        if !compactMode {
                            Text(historySubtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .mainInnerSurface(tint: accent, cornerRadius: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(compactMode ? 16 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mainSectionSurface(tint: accent, cornerRadius: 30)
    }

    private func quickActionTile(
        title: String,
        systemName: String,
        gradient: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill((gradient.first ?? accent).opacity(0.16))
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .frame(width: compactMode ? 38 : 42, height: compactMode ? 38 : 42)

                Text(title)
                    .font(.system(size: compactMode ? 14 : 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if !compactMode {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle((gradient.first ?? accent).opacity(0.92))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, compactMode ? 10 : 12)
            .frame(maxWidth: .infinity, minHeight: compactMode ? 58 : 64, alignment: .leading)
            .mainInnerSurface(tint: gradient.first ?? accent, cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }
}
