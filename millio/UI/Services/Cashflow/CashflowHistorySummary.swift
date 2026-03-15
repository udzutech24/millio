//
//  CashflowHistorySummary.swift
//  millio
//
//  Created by Assistant on 15.03.2026.
//

import SwiftUI
import Charts

enum CashflowHistorySummaryMode: String, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense:
            return String(
                localized: "cashflow.history.summary.expense",
                defaultValue: "Траты",
                comment: "History summary mode title for expenses"
            )
        case .income:
            return String(
                localized: "cashflow.history.summary.income",
                defaultValue: "Доходы",
                comment: "History summary mode title for income"
            )
        }
    }

    var kind: CashflowCategoryKind {
        switch self {
        case .expense: return .expense
        case .income: return .income
        }
    }
}

struct CashflowHistorySummaryResolvedCategory: Equatable {
    let rawValue: String
    let title: String
    let icon: String
}

struct CashflowHistorySummaryEntry: Identifiable, Equatable {
    let id: String
    let rawValue: String
    let title: String
    let icon: String
    let amount: Double
    let share: Double
    let tintHex: String

    init(
        rawValue: String,
        title: String,
        icon: String,
        amount: Double,
        share: Double,
        tintHex: String
    ) {
        self.id = rawValue
        self.rawValue = rawValue
        self.title = title
        self.icon = icon
        self.amount = amount
        self.share = share
        self.tintHex = tintHex
    }
}

struct CashflowHistorySummaryModel: Equatable {
    let mode: CashflowHistorySummaryMode
    let totalAmount: Double
    let currencyCode: String
    let entries: [CashflowHistorySummaryEntry]

    static func empty(
        mode: CashflowHistorySummaryMode,
        currencyCode: String
    ) -> CashflowHistorySummaryModel {
        CashflowHistorySummaryModel(mode: mode, totalAmount: 0, currencyCode: currencyCode, entries: [])
    }
}

func cashflowHistoryPercentText(share: Double) -> String {
    guard share.isFinite, !share.isNaN else { return "0%" }
    let percent = (share * 100).rounded()
    guard percent.isFinite, !percent.isNaN else { return "0%" }
    return "\(Int(percent))%"
}

enum CashflowHistorySummaryBuilder {
    private static let expensePalette = [
        "47D7FF",
        "FF8C42",
        "FF9B9B",
        "6BDB95",
        "BCD8F2",
        "B8A6FF",
        "FFD166",
        "A1A7B8"
    ]

    private static let incomePalette = [
        "63E6BE",
        "47D7FF",
        "7AB6FF",
        "FFD166",
        "FF9B9B",
        "D0BFFF",
        "95E0A3",
        "A1A7B8"
    ]

    static func build(
        totalsByRawValue: [String: Double],
        mode: CashflowHistorySummaryMode,
        resolver: (String) -> CashflowHistorySummaryResolvedCategory
    ) -> [CashflowHistorySummaryEntry] {
        let palette = mode == .expense ? expensePalette : incomePalette
        let sanitizedTotals = totalsByRawValue
            .filter { $0.value.isFinite && $0.value > 0.0000001 }
        let total = sanitizedTotals.values.reduce(0, +)
        guard total.isFinite, total > 0 else { return [] }

        return sanitizedTotals
            .sorted {
                if abs($0.value - $1.value) > 0.0000001 {
                    return $0.value > $1.value
                }
                return $0.key < $1.key
            }
            .enumerated()
            .map { index, item in
                let category = resolver(item.key)
                let share = sanitizedShare(amount: item.value, total: total)
                return CashflowHistorySummaryEntry(
                    rawValue: item.key,
                    title: category.title,
                    icon: category.icon,
                    amount: item.value,
                    share: share,
                    tintHex: palette[index % palette.count]
                )
            }
    }

    private static func sanitizedShare(amount: Double, total: Double) -> Double {
        guard amount.isFinite, total.isFinite, total > 0 else { return 0 }
        let share = amount / total
        guard share.isFinite, !share.isNaN else { return 0 }
        return min(max(share, 0), 1)
    }
}

private struct CashflowHistoryRingChart: View {
    let entries: [CashflowHistorySummaryEntry]
    let selectedRawValue: String?
    let progress: CGFloat
    let onSelect: (String?) -> Void

    private var visibleEntries: [CashflowHistorySummaryEntry] {
        entries.filter { $0.amount > 0.0000001 }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let chartScale = 1 - (0.18 * progress)
            let compactScale = 1 - (0.28 * progress)

            ZStack {
                Chart(visibleEntries) { entry in
                    SectorMark(
                        angle: .value("Amount", entry.amount),
                        innerRadius: .ratio(0.67),
                        angularInset: 2
                    )
                    .cornerRadius(12)
                    .foregroundStyle(Color(hex: entry.tintHex))
                    .opacity(selectedRawValue == nil || selectedRawValue == entry.rawValue ? 1 : 0.28)
                }
                .chartLegend(.hidden)
                .chartBackground { _ in
                    EmptyView()
                }
                .scaleEffect(chartScale)
                .frame(width: size, height: size)
                .allowsHitTesting(false)

                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: size * 0.48, height: size * 0.48)
            }
            .scaleEffect(compactScale, anchor: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

}

struct CashflowHistorySummaryCard: View {
    let summary: CashflowHistorySummaryModel
    @Binding var selectedCategoryRawValue: String?
    let collapseProgress: CGFloat

    private var selectedEntry: CashflowHistorySummaryEntry? {
        guard let selectedCategoryRawValue else { return nil }
        return summary.entries.first(where: { $0.rawValue == selectedCategoryRawValue })
    }

    private var amountLabel: String {
        let amount = cashflowHistoryWholeAmountText(selectedEntry?.amount ?? summary.totalAmount)
        let symbol = MonetaCurrency(rawValue: summary.currencyCode)?.symbol ?? summary.currencyCode
        return "\(amount) \(symbol)"
    }

    private var subtitleLabel: String {
        selectedEntry?.title ?? summary.mode.title
    }

    private var compactProgress: CGFloat {
        min(max(collapseProgress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let isNarrow = proxy.size.width < 380
            let expandedMinHeight: CGFloat = isNarrow ? 392 : 372
            let collapsedMinHeight: CGFloat = 126
            let headerHeight = expandedMinHeight - ((expandedMinHeight - collapsedMinHeight) * compactProgress)
            let chartSize: CGFloat = compactProgress > 0.75 ? 110 : (isNarrow ? 176 : 204)
            let textWidth = max(138, proxy.size.width - chartSize - (isNarrow ? 22 : 30))
            let chipsColumns = isNarrow ? [GridItem(.flexible(), spacing: 12)] : [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: isNarrow ? 10 : 16) {
                    summaryTextBlock
                        .frame(width: textWidth, alignment: .leading)
                        .padding(.top, compactProgress < 0.75 ? 6 : 0)

                    summaryChart(size: chartSize)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if compactProgress < 0.9 {
                    LazyVGrid(columns: chipsColumns, spacing: 12) {
                        ForEach(summary.entries.prefix(6)) { entry in
                            summaryChip(entry)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .frame(height: compactProgress < 0.72 ? 392 : 126)
    }

    private var summaryTextBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(amountLabel)
                    .font(.system(size: compactProgress > 0.7 ? 24 : 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleLabel)
                    .font(.system(size: compactProgress > 0.7 ? 18 : 20, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            if let selectedEntry, compactProgress < 0.75 {
                Text(cashflowHistoryPercentText(share: selectedEntry.share))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: selectedEntry.tintHex))
            }
        }
    }

    private func summaryChart(size: CGFloat) -> some View {
        CashflowHistoryRingChart(
            entries: summary.entries,
            selectedRawValue: selectedCategoryRawValue,
            progress: compactProgress,
            onSelect: { rawValue in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    selectedCategoryRawValue = rawValue
                }
            }
        )
        .frame(width: size, height: size)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.085),
                        Color.white.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
    }

    private func summaryChip(_ entry: CashflowHistorySummaryEntry) -> some View {
        let isSelected = selectedCategoryRawValue == entry.rawValue
        let tint = Color(hex: entry.tintHex)

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedCategoryRawValue = isSelected ? nil : entry.rawValue
            }
        } label: {
            HStack(spacing: 10) {
                Text(entry.icon)
                    .font(.system(size: 17))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(tint.opacity(isSelected ? 0.95 : 0.78))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text("\(cashflowHistoryWholeAmountText(entry.amount)) \(MonetaCurrency(rawValue: summary.currencyCode)?.symbol ?? summary.currencyCode)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint.opacity(isSelected ? 0.22 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(isSelected ? 0.55 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CashflowHistorySummaryContainer: View {
    let summary: CashflowHistorySummaryModel
    @Binding var selectedCategoryRawValue: String?

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .global).minY
            let collapseProgress = min(max(-minY / 220, 0), 1)

            CashflowHistorySummaryCard(
                summary: summary,
                selectedCategoryRawValue: $selectedCategoryRawValue,
                collapseProgress: collapseProgress
            )
        }
        .frame(height: 392)
    }
}
