//
//  BudgetHeroCard.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import SwiftUI

/// Компактная карточка бюджета на главном экране Cashflow (Фаза 1 редизайна add-flow):
/// показывает расходы И доходы одновременно (решение владельца §7.1.2), тап по строке —
/// открытие `BudgetSetupSheet` для соответствующего kind.
struct BudgetHeroCard: View {
    let expenseSnapshot: BudgetProgressSnapshot?
    let incomeSnapshot: BudgetProgressSnapshot?
    let currencyCode: String
    let onTap: (CashflowCategoryKind) -> Void

    private let primaryText = AppColors.textPrimary
    private let secondaryText = Color.white.opacity(0.72)

    var body: some View {
        if expenseSnapshot == nil && incomeSnapshot == nil {
            Button(action: { onTap(.expense) }) {
                emptyCard
            }
            .buttonStyle(.plain)
        } else {
            populatedCard
        }
    }

    private var populatedCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            if let expenseSnapshot {
                budgetRowButton(kind: .expense, snapshot: expenseSnapshot)
            }
            if expenseSnapshot != nil, incomeSnapshot != nil {
                Divider().overlay(Color.white.opacity(0.08))
            }
            if let incomeSnapshot {
                budgetRowButton(kind: .income, snapshot: incomeSnapshot)
            }
        }
        .padding(AppSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func budgetRowButton(kind: CashflowCategoryKind, snapshot: BudgetProgressSnapshot) -> some View {
        Button(action: { onTap(kind) }) {
            budgetRow(kind: kind, snapshot: snapshot)
        }
        .buttonStyle(.plain)
    }

    private func budgetRow(kind: CashflowCategoryKind, snapshot: BudgetProgressSnapshot) -> some View {
        let sheetKind: CashflowCategoryTransactionSheetKind = kind == .expense ? .expense : .income
        let style = budgetMonthlySummaryStyle(kind: sheetKind, snapshot: snapshot)
        let progress = min(max(snapshot.progress, 0), 1)

        return HStack(spacing: AppSpacing.m) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style.progressFill.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress * 100))%")
                    .font(.millioCaption2)
                    .fontWeight(.bold)
                    .foregroundStyle(primaryText)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Text(kindTitle(kind))
                        .font(.millioSubheadline)
                        .foregroundStyle(primaryText)
                    Spacer()
                    budgetStatusBadge(snapshot.status)
                }

                Text("\(cashflowAmountText(snapshot.spent)) / \(cashflowAmountText(snapshot.limit)) \(currencyCode)")
                    .font(.millioBodySemibold)
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())

                Text(remainingTitle(snapshot))
                    .font(.millioCallout)
                    .foregroundStyle(style.statusText.color)
                    .contentTransition(.numericText())

                if snapshot.categoriesLimitOverflow > 0.0000001 {
                    Text(CashflowBudgetLocalization.heroOverflow(
                        kind: kind,
                        amount: cashflowAmountText(snapshot.categoriesLimitOverflow),
                        currencyCode: currencyCode
                    ))
                    .font(.millioCaption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.orange.opacity(0.92))
                    .lineLimit(2)
                }
            }
        }
    }

    private func kindTitle(_ kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense: return L("cashflow.tab.expenses")
        case .income: return L("cashflow.tab.incomes")
        }
    }

    private var emptyCard: some View {
        HStack(spacing: AppSpacing.ml) {
            Image(systemName: "target")
                .font(.millioTitle2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(CashflowBudgetLocalization.periodLimit)
                    .font(.millioSubheadline)
                    .foregroundStyle(primaryText)
                Text(CashflowBudgetLocalization.emptyHint)
                    .font(.millioCallout)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "plus.circle.fill")
                .font(.millioTitle2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .padding(AppSpacing.l)
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
        Text(CashflowBudgetLocalization.status(status))
            .font(.millioCaption2)
            .fontWeight(.bold)
            .foregroundStyle(budgetStatusTintToken(status).color)
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, AppSpacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(budgetStatusTintToken(status).color.opacity(0.12))
            )
    }
}
