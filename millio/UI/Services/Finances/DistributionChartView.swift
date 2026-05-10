//
//  DistributionChartView.swift
//  millio
//

import SwiftUI
import Charts

// MARK: - Palette

private let distributionPalette: [Color] = [
    Color(red: 0.47, green: 0.69, blue: 1.00),  // голубой (как линия графика)
    Color(red: 1.00, green: 0.62, blue: 0.18),  // оранжевый
    Color(red: 0.38, green: 0.82, blue: 0.73),  // бирюзовый
    Color(red: 0.75, green: 0.47, blue: 1.00),  // фиолетовый
    Color(red: 0.25, green: 0.80, blue: 0.55),  // зелёный
    Color(red: 1.00, green: 0.85, blue: 0.25),  // жёлтый
    Color(red: 0.55, green: 0.75, blue: 1.00),  // светло-голубой
    Color(red: 1.00, green: 0.55, blue: 0.70),  // розовый
]

private let negativeColor = Color(red: 1.0, green: 0.37, blue: 0.37)

// MARK: - Slice Model

struct DistributionSlice: Identifiable {
    let id: String
    let name: String
    let endValue: Double
    let absValue: Double
    let percentage: Double
    let color: Color
}

// MARK: - DistributionChartView

struct DistributionChartView: View {
    let items: [DynamicsBreakdownItem]
    let currency: String
    let isAmountHidden: Bool

    private var slices: [DistributionSlice] {
        let positiveItems = items.filter { $0.endValue > 0 && !$0.isArchived }
        let negativeItems = items.filter { $0.endValue < 0 && !$0.isArchived }

        let totalPositive = positiveItems.reduce(0) { $0 + $1.endValue }
        let totalNegative = negativeItems.reduce(0) { $0 + abs($1.endValue) }
        let grandTotal = totalPositive + totalNegative

        guard grandTotal > 0 else { return [] }

        var result: [DistributionSlice] = []
        var colorIndex = 0

        for item in positiveItems.sorted(by: { $0.endValue > $1.endValue }) {
            let pct = item.endValue / grandTotal * 100
            result.append(DistributionSlice(
                id: item.id,
                name: item.name,
                endValue: item.endValue,
                absValue: item.endValue,
                percentage: pct,
                color: distributionPalette[colorIndex % distributionPalette.count]
            ))
            colorIndex += 1
        }

        for item in negativeItems.sorted(by: { abs($0.endValue) > abs($1.endValue) }) {
            let pct = abs(item.endValue) / grandTotal * 100
            result.append(DistributionSlice(
                id: item.id,
                name: item.name,
                endValue: item.endValue,
                absValue: abs(item.endValue),
                percentage: -pct,
                color: negativeColor
            ))
        }

        return result
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

    // MARK: - Donut

    private var donutChart: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Сумма", slice.absValue),
                innerRadius: .ratio(0.58),
                angularInset: 1.5
            )
            .foregroundStyle(slice.color)
            .cornerRadius(3)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 7, height: 7)

                    Text(slice.name)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(percentageText(slice.percentage))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(slice.percentage < 0 ? negativeColor : AppColors.textPrimary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textSecondary)
            Text("Нет данных для отображения")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func percentageText(_ pct: Double) -> String {
        let sign = pct < 0 ? "-" : ""
        return "\(sign)\(String(format: "%.1f", abs(pct)))%"
    }
}
