//
//  CurrencyDistributionChartView.swift
//  millio
//

import SwiftUI
import Charts

struct CurrencyDistributionChartView: View {
    let items: [CurrencyBreakdownItem]
    let displayCurrency: String
    let isAmountHidden: Bool

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let value: Double
        let percentage: Double
        let color: Color
    }

    private let palette: [Color] = [
        Color(red: 0.47, green: 0.69, blue: 1.00),
        Color(red: 1.00, green: 0.62, blue: 0.18),
        Color(red: 0.38, green: 0.82, blue: 0.73),
        Color(red: 0.75, green: 0.47, blue: 1.00),
        Color(red: 0.25, green: 0.80, blue: 0.55),
        Color(red: 1.00, green: 0.85, blue: 0.25),
        Color(red: 0.55, green: 0.75, blue: 1.00),
        Color(red: 1.00, green: 0.55, blue: 0.70),
    ]

    private var slices: [Slice] {
        items.enumerated().map { index, item in
            Slice(
                id: item.currency,
                label: item.currency,
                value: item.convertedValue,
                percentage: item.percentage,
                color: palette[index % palette.count]
            )
        }
    }

    var body: some View {
        if slices.isEmpty {
            emptyView
        } else {
            HStack(alignment: .center, spacing: 16) {
                donutChart
                    .frame(width: 120, height: 120)
                legend
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
        }
    }

    private var donutChart: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value(L("finances.chart.amount_label"), slice.value),
                innerRadius: .ratio(0.58),
                angularInset: 1.5
            )
            .foregroundStyle(slice.color)
            .cornerRadius(3)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 7, height: 7)

                    Text(slice.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer(minLength: 4)

                    Text(String(format: "%.1f%%", slice.percentage))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textSecondary)
            Text(L("finances.dynamics.currency_chart.empty"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
