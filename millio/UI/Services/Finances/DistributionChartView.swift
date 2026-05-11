//
//  DistributionChartView.swift
//  millio
//

import SwiftUI
import Charts

// MARK: - Palette

private let distributionPalette: [Color] = [
    Color(red: 0.47, green: 0.69, blue: 1.00),  // голубой
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

    // Активы — показываются в доnutе, проценты от totalPositive (сумма = 100%)
    private var assetSlices: [DistributionSlice] {
        let positiveItems = items.filter { $0.endValue > 0 && !$0.isArchived }
        let totalPositive = positiveItems.reduce(0) { $0 + $1.endValue }
        guard totalPositive > 0 else { return [] }

        return positiveItems
            .sorted(by: { $0.endValue > $1.endValue })
            .enumerated()
            .map { index, item in
                DistributionSlice(
                    id: item.id,
                    name: item.name,
                    endValue: item.endValue,
                    absValue: item.endValue,
                    percentage: item.endValue / totalPositive * 100,
                    color: distributionPalette[index % distributionPalette.count]
                )
            }
    }

    // Обязательства — только для строки под легендой
    private var liabilitySlices: [DistributionSlice] {
        let negativeItems = items.filter { $0.endValue < 0 && !$0.isArchived }
        let totalPositive = items.filter { $0.endValue > 0 && !$0.isArchived }
            .reduce(0) { $0 + $1.endValue }
        guard totalPositive > 0 else { return [] }

        return negativeItems
            .sorted(by: { abs($0.endValue) > abs($1.endValue) })
            .map { item in
                DistributionSlice(
                    id: item.id,
                    name: item.name,
                    endValue: item.endValue,
                    absValue: abs(item.endValue),
                    percentage: abs(item.endValue) / totalPositive * 100,
                    color: negativeColor
                )
            }
    }

    var body: some View {
        if assetSlices.isEmpty {
            emptyView
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 20) {
                    donutChart
                        .frame(width: 150, height: 150)
                    legend
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !liabilitySlices.isEmpty {
                    liabilitiesSection
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Donut (только активы)

    private var donutChart: some View {
        Chart(assetSlices) { slice in
            SectorMark(
                angle: .value(L("finances.chart.amount_label"), slice.absValue),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(slice.color)
            .cornerRadius(3)
        }
    }

    // MARK: - Legend (только активы, сумма = 100%)

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(assetSlices) { slice in
                HStack(spacing: 7) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 8, height: 8)

                    Text(slice.name)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(String(format: "%.1f%%", slice.percentage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Обязательства (долги, под основной легендой)

    private var liabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .background(AppColors.textSecondary.opacity(0.2))

            ForEach(liabilitySlices) { slice in
                HStack(spacing: 7) {
                    Circle()
                        .fill(negativeColor)
                        .frame(width: 8, height: 8)

                    Text(slice.name)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text("−\(String(format: "%.1f%%", slice.percentage))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(negativeColor)
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
            Text(L("Нет данных для отображения"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
