//
//  BudgetHeroCard.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import SwiftUI

struct BudgetHeroCard: View {
    let snapshot: BudgetProgressSnapshot?
    let currencyCode: String
    let onTap: () -> Void

    private let primaryText = AppColors.textPrimary
    private let secondaryText = Color.white.opacity(0.72)

    var body: some View {
        Button(action: onTap) {
            Group {
                if let snapshot {
                    populatedCard(snapshot: snapshot)
                } else {
                    emptyCard
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func populatedCard(snapshot: BudgetProgressSnapshot) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(max(snapshot.progress, 0), 1))
                    .stroke(
                        statusColor(snapshot.status),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: statusColor(snapshot.status).opacity(0.28), radius: 8)
                VStack(spacing: 4) {
                    Text("\(Int(min(snapshot.progress, 1) * 100))%")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(primaryText)
                    Text(budgetLocalized(ru: "лимита", en: "used"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondaryText)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(budgetLocalized(ru: "Лимит периода", en: "Period limit"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primaryText)
                    Spacer()
                    budgetStatusBadge(snapshot.status)
                }

                Text("\(cashflowAmountText(snapshot.spent)) / \(cashflowAmountText(snapshot.limit)) \(currencyCode)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())

                Text(remainingTitle(snapshot))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(statusColor(snapshot.status))
                    .contentTransition(.numericText())

                if snapshot.categoriesLimitOverflow > 0.0000001 {
                    Text(
                        budgetLocalized(
                            ru: "Лимиты категорий превышают общий на \(cashflowAmountText(snapshot.categoriesLimitOverflow)) \(currencyCode)",
                            en: "Category limits exceed total by \(cashflowAmountText(snapshot.categoriesLimitOverflow)) \(currencyCode)"
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.92))
                    .lineLimit(2)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(statusColor(snapshot.status).opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var emptyCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(budgetLocalized(ru: "Лимит периода", en: "Period limit"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryText)
                Text(
                    budgetLocalized(
                        ru: "Добавь общий лимит на текущий период, чтобы видеть остаток и риск перерасхода.",
                        en: "Set a total limit for the current period to track remaining budget and overspending risk."
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func remainingTitle(_ snapshot: BudgetProgressSnapshot) -> String {
        if snapshot.remaining >= 0 {
            return budgetLocalized(
                ru: "Осталось \(cashflowAmountText(snapshot.remaining)) \(currencyCode)",
                en: "\(cashflowAmountText(snapshot.remaining)) \(currencyCode) remaining"
            )
        }
        return budgetLocalized(
            ru: "Перерасход \(cashflowAmountText(abs(snapshot.remaining))) \(currencyCode)",
            en: "Over by \(cashflowAmountText(abs(snapshot.remaining))) \(currencyCode)"
        )
    }

    private func budgetStatusBadge(_ status: BudgetStatus) -> some View {
        Text(statusText(status))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor(status).opacity(0.12))
            )
    }

    private func statusText(_ status: BudgetStatus) -> String {
        switch status {
        case .normal:
            return budgetLocalized(ru: "Норма", en: "Normal")
        case .warning:
            return budgetLocalized(ru: "Внимание", en: "Watch")
        case .critical:
            return budgetLocalized(ru: "Предел", en: "Critical")
        case .exceeded:
            return budgetLocalized(ru: "Перерасход", en: "Exceeded")
        }
    }

    private func statusColor(_ status: BudgetStatus) -> Color {
        switch status {
        case .normal:
            return Color(hex: "6DFFC7")
        case .warning:
            return Color(hex: "FFD66D")
        case .critical:
            return Color(hex: "FF9B6A")
        case .exceeded:
            return Color(hex: "FF6666")
        }
    }
}

func budgetLocalized(ru: String, en: String, locale: Locale = .autoupdatingCurrent) -> String {
    if locale.language.languageCode?.identifier == "ru" {
        return ru
    }
    return en
}
