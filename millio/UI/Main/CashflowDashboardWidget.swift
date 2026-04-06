//
//  CashflowDashboardWidget.swift
//  millio
//
//  Created by Codex on 04.04.2026.
//

import SwiftUI

struct CashflowDashboardWidget: View {
    @ObservedObject var viewModel: CashflowViewModel
    let onOpenCashflow: () -> Void

    private var accent: Color {
        AppColors.cashflowGradient.first ?? AppColors.brandPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if presentation.bars.allSatisfy(\.isPlaceholder) {
                Text(
                    String(
                        localized: "main.dashboard.widget.cashflow.empty",
                        defaultValue: "Add a few transactions and the monthly cashflow pulse will appear here.",
                        comment: "Empty state for the dashboard cashflow widget"
                    )
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                summary
                bars
            }
        }
        .padding(20)
        .mainSectionSurface(tint: accent, cornerRadius: 30)
        .task(id: reloadToken) {
            viewModel.handle(.loadTransactions)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(MainLocalization.dashboardWidgetTitle(for: .cashflow))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(MainLocalization.dashboardWidgetSubtitle(for: .cashflow))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button(action: onOpenCashflow) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            summaryChip(
                title: String(localized: "Income"),
                amount: presentation.incomeCard.amount,
                accent: positiveTone
            )
            summaryChip(
                title: String(localized: "Expense"),
                amount: presentation.expenseCard.amount,
                accent: negativeTone
            )
            summaryChip(
                title: String(
                    localized: "main.dashboard.widget.cashflow.net",
                    defaultValue: "Net",
                    comment: "Net summary label for the dashboard cashflow widget"
                ),
                amount: netAmount,
                accent: netAmount >= 0 ? positiveTone : negativeTone
            )
        }
    }

    private func summaryChip(title: String, amount: Double, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)

            Text(amountText(amount))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .mainInnerSurface(tint: accent, cornerRadius: 20)
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(presentation.bars) { bar in
                VStack(spacing: 10) {
                    HStack(alignment: .bottom, spacing: 5) {
                        barColumn(
                            value: bar.expense,
                            maxValue: maxBarValue,
                            tint: negativeTone
                        )
                        barColumn(
                            value: bar.income,
                            maxValue: maxBarValue,
                            tint: positiveTone
                        )
                    }
                    .frame(height: 110, alignment: .bottom)

                    Text(bar.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 6)
    }

    private func barColumn(value: Double, maxValue: Double, tint: Color) -> some View {
        let height = max(10, CGFloat(value / max(maxValue, 1)) * 100)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 18, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 0.8)
            )
    }

    private var presentation: CashflowInsightsPresentation {
        CashflowInsightsChartBuilder.makeFullScreenPresentation(
            entries: viewModel.state.convertedTransactions,
            granularity: .month,
            selectedPeriodStart: nil,
            referenceDate: Date(),
            maxVisiblePeriods: 4,
            monthLabelStyle: .abbreviatedWithYear,
            calendar: .current,
            locale: AppLocalization.currentAppLocale
        )
    }

    private var netAmount: Double {
        presentation.incomeCard.amount - presentation.expenseCard.amount
    }

    private var maxBarValue: Double {
        max(
            presentation.bars.flatMap { [abs($0.income), abs($0.expense)] }.max() ?? 0,
            1
        )
    }

    private var positiveTone: Color {
        AppColors.incomeGradient.first ?? Color.green
    }

    private var negativeTone: Color {
        AppColors.expenseGradient.first ?? Color.red
    }

    private var reloadToken: String {
        "\(viewModel.state.displayCurrency)|\(viewModel.state.transactions.count)"
    }

    private func amountText(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = AppLocalization.currentAppLocale
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        let numberText = formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
        return "\(numberText) \(viewModel.state.displayCurrency)"
    }
}
