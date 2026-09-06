//
//  CashflowUnifiedEntryHeader.swift
//  millio
//
//  Шапка экрана быстрого ввода: крестик, переключатель месяца, кнопка «…»
//  и hero-блок суммы с полоской плана. Вынесено из CashflowUnifiedEntryView
//  без изменения поведения (Ф5 плана entry-screen-simplify).
//

import SwiftUI

extension CashflowCategoryTransactionSheet {
    var headerSection: some View {
        HStack(spacing: 12) {
            circleToolbarButton(systemName: "xmark", accessibilityLabel: L("cashflow.common.close")) {
                dismiss()
            }

            HStack(spacing: 10) {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                        .frame(width: 24, height: 24)
                        .background(monthChevronBackground)
                }
                .buttonStyle(.plain)

                Text(monthTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                .frame(maxWidth: .infinity)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canMoveForward ? AppColors.textPrimary.opacity(0.9) : AppColors.textSecondary.opacity(0.45))
                        .frame(width: 24, height: 24)
                        .background(monthChevronBackground)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveForward)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(monthHeaderBackground)

            Button {
                showMoreSheet = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(innerPanelBackground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("cashflow.category.manage", defaultValue: "Manage categories"))
        }
        .padding(.top, 6)
    }

    /// Hero-блок месяца: сумма + полоска плана. Тап по всему блоку открывает историю
    /// операций — отдельной пилюли «История» в шапке больше нет.
    var monthlyTotalSection: some View {
        Button {
            pendingActionCategory = nil
            showTransactionsHistory = true
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(kind.monthlyTotalTitle)
                    .font(.millioCallout)
                    .foregroundStyle(AppColors.textSecondary)

                if isLoadingMonthlyTotal {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                        .frame(height: AppSpacing.xxl)
                } else {
                    Text(formattedMonthlyTotal(monthlyTotal))
                        .font(.millioAmountHero)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }

                planProgressBar
                planSummaryLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cashflow.unified.history")
    }

    @ViewBuilder
    var planProgressBar: some View {
        if let snapshot = budgetSnapshot, snapshot.limit > 0 {
            GeometryReader { proxy in
                let progress = min(max(snapshot.progress, 0), 1)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(kind.strokeGradient)
                            .frame(width: proxy.size.width * progress)
                    }
            }
            .frame(height: 6)
            .padding(.top, AppSpacing.xs)
        }
    }

    var planSummaryLine: some View {
        Text(planSummaryText)
            .font(.millioCallout)
            .foregroundStyle(AppColors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    var planSummaryText: String {
        guard let snapshot = budgetSnapshot, snapshot.limit > 0 else {
            return L("cashflow.entry.plan.none", defaultValue: "No plan")
        }
        let percent = Int((min(max(snapshot.progress, 0), 1) * 100).rounded())
        return String(
            format: L("cashflow.entry.plan.summary", defaultValue: "%1$lld%% of plan %2$@ · %3$@"),
            locale: AppLocalization.currentAppLocale,
            percent,
            formattedMonthlyTotal(snapshot.limit),
            monthlyBudgetStatusText(snapshot)
        )
    }

    var toolbarCircleBackground: some View {
        Circle()
            .fill(Color.black.opacity(0.92))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.78), lineWidth: 1.6)
            )
    }

    var monthChevronBackground: some View {
        Circle()
            .fill(Color.white.opacity(0.04))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    var monthHeaderBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.black.opacity(0.24))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    func circleToolbarButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    func shiftMonth(by value: Int) {
        let calendar = Calendar.current
        guard let newValue = calendar.date(byAdding: .month, value: value, to: selectedMonth) else {
            return
        }

        let normalized = calendar.startOfMonth(for: newValue)
        if normalized > currentMonthStart {
            selectedMonth = currentMonthStart
        } else {
            selectedMonth = normalized
        }
    }

    func formattedMonthlyTotal(_ value: Double) -> String {
        let amount = formattedAmount(value)
        let code = viewModel.state.displayCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return amount }
        let symbol = MonetaCurrency(rawValue: code)?.symbol ?? code
        return "\(amount) \(symbol)"
    }

    func monthlyBudgetStatusText(_ snapshot: BudgetProgressSnapshot) -> String {
        let currency = cashflowCurrencyCodeLabel(viewModel.state.displayCurrency)
        return CashflowBudgetLocalization.monthlyStatus(
            for: kind,
            remaining: snapshot.remaining,
            currency: currency
        )
    }
    var currentMonthStart: Date {
        Calendar.current.startOfMonth(for: Date())
    }

    var canMoveForward: Bool {
        selectedMonth < currentMonthStart
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: selectedMonth).localizedCapitalized
    }

    var planButtonTitle: String {
        CashflowBudgetLocalization.planButtonTitle(for: kind, hasBudget: budgetSnapshot != nil)
    }

    var historyRange: (start: Date, end: Date) {
        CashflowViewModel.monthHistoryRange(for: selectedMonth, calendar: .current)
    }

    func monthRangeText(for month: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfMonth(for: month)
        guard
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)
        else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "dd.MM"
        return "\(formatter.string(from: start)) — \(formatter.string(from: end))"
    }
}
