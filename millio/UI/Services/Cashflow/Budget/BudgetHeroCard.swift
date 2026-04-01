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
        let style = budgetMonthlySummaryStyle(kind: .expense, snapshot: snapshot)
        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(max(snapshot.progress, 0), 1))
                    .stroke(
                        style.progressFill.color,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: style.progressFill.color.opacity(0.28), radius: 8)
                VStack(spacing: 4) {
                    Text("\(Int(min(snapshot.progress, 1) * 100))%")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(primaryText)
                    Text(CashflowBudgetLocalization.used)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondaryText)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(CashflowBudgetLocalization.periodLimit)
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
                    .foregroundStyle(style.statusText.color)
                    .contentTransition(.numericText())

                if snapshot.categoriesLimitOverflow > 0.0000001 {
                    Text(CashflowBudgetLocalization.heroOverflow(
                        kind: .expense,
                        amount: cashflowAmountText(snapshot.categoriesLimitOverflow),
                        currencyCode: currencyCode
                    ))
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
                        .stroke(style.progressFill.color.opacity(0.5), lineWidth: 1)
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
                Text(CashflowBudgetLocalization.periodLimit)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryText)
                Text(CashflowBudgetLocalization.emptyHint)
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
            return CashflowBudgetLocalization.heroRemaining(
                cashflowAmountText(snapshot.remaining),
                currencyCode: currencyCode
            )
        }
        return CashflowBudgetLocalization.heroExceeded(
            cashflowAmountText(abs(snapshot.remaining)),
            currencyCode: currencyCode
        )
    }

    private func budgetStatusBadge(_ status: BudgetStatus) -> some View {
        Text(statusText(status))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(budgetStatusTintToken(status).color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(budgetStatusTintToken(status).color.opacity(0.12))
            )
    }

    private func statusText(_ status: BudgetStatus) -> String {
        CashflowBudgetLocalization.status(status)
    }
}
