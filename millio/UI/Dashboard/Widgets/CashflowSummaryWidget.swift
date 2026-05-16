//
//  CashflowSummaryWidget.swift
//  millio

import SwiftUI

struct CashflowSummaryWidget: View {
    let cashflowTotal: Double
    let totalIncome: Double
    let totalExpense: Double      // абсолютное значение
    let assetValueChange: Double
    let displayCurrency: String
    let periodLabel: String
    var isAmountHidden: Bool = false
    var onTap: (() -> Void)? = nil

    private var currencySymbol: String {
        MonetaCurrency(rawValue: displayCurrency)?.symbol ?? displayCurrency
    }

    private var totalIsPositive: Bool { cashflowTotal >= 0 }

    private var totalColor: Color {
        totalIsPositive ? AppColors.positiveColor : AppColors.negativeColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            metricRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(cardBackground)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Кэшфлоу за период"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedSigned(cashflowTotal))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(totalColor)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)

                    Text(currencySymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(totalColor.opacity(0.75))
                }
            }

            Spacer(minLength: 8)

            trendIcon
        }
    }

    private var trendIcon: some View {
        Button(action: { onTap?() }) {
            ZStack {
                Circle()
                    .fill(AppColors.brandPrimary.opacity(0.18))
                    .overlay(Circle().stroke(AppColors.brandPrimary.opacity(0.30), lineWidth: 0.8))
                    .frame(width: 28, height: 28)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    // MARK: - Metric Chips

    private var metricRow: some View {
        HStack(spacing: 8) {
            metricChip(
                label: L("cashflow.income"),
                value: totalIncome,
                showSign: true,
                valueColor: AppColors.positiveColor
            )
            metricChip(
                label: L("cashflow.expense"),
                value: -totalExpense,
                showSign: true,
                valueColor: totalExpense > 0.01
                    ? AppColors.negativeColor
                    : Color.white.opacity(0.5)
            )
            metricChip(
                label: L("cashflow.asset_change"),
                value: assetValueChange,
                showSign: true,
                valueColor: assetValueChange >= 0
                    ? AppColors.positiveColor
                    : AppColors.negativeColor
            )
        }
    }

    private func metricChip(
        label: String,
        value: Double,
        showSign: Bool,
        valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(showSign ? formattedSigned(value) + " \(currencySymbol)" : formatted(abs(value)) + " \(currencySymbol)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Formatters

    private func formatted(_ value: Double) -> String {
        if isAmountHidden {
            let digits = Int(abs(value).rounded())
            return String(repeating: "•", count: max(3, String(digits).count))
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: value)) ?? "—"
    }

    private func formattedSigned(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(formatted(abs(value)))"
    }

    // MARK: - Card background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            )
    }
}
