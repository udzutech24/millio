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

enum CashflowHistorySummaryLayout {
    static let collapseDistance: CGFloat = 180
    static let collapsedHeight: CGFloat = 120
    static let narrowExpandedHeaderHeight: CGFloat = 196
    static let wideExpandedHeaderHeight: CGFloat = 182
    static let outerPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let chipSpacing: CGFloat = 10
    static let chipHeight: CGFloat = 68

    static func collapseProgress(minY: CGFloat) -> CGFloat {
        let progress = -minY / collapseDistance
        return min(max(progress, 0), 1)
    }

    static func columnCount(containerWidth: CGFloat) -> Int {
        switch containerWidth {
        case ..<360:
            return 2
        case ..<560:
            return 3
        default:
            return 4
        }
    }

    static func expandedHeight(containerWidth: CGFloat, entryCount: Int) -> CGFloat {
        let headerHeight = containerWidth < 380 ? narrowExpandedHeaderHeight : wideExpandedHeaderHeight
        guard entryCount > 0 else {
            return max(collapsedHeight, headerHeight + (outerPadding * 2))
        }

        let columns = max(columnCount(containerWidth: containerWidth), 1)
        let rowCount = CGFloat((entryCount + columns - 1) / columns)
        let chipsHeight = (rowCount * chipHeight) + (max(rowCount - 1, 0) * chipSpacing)
        return headerHeight + chipsHeight + sectionSpacing + (outerPadding * 2)
    }

    static func containerHeight(
        containerWidth: CGFloat,
        entryCount: Int,
        collapseProgress: CGFloat
    ) -> CGFloat {
        let expanded = expandedHeight(containerWidth: containerWidth, entryCount: entryCount)
        return expanded - ((expanded - collapsedHeight) * min(max(collapseProgress, 0), 1))
    }
}

enum CashflowHistorySummaryBuilder {
    private static let expensePalette = [
        "47D7FF",
        "FF9F5A",
        "F68BA7",
        "6FD2A8",
        "AFC8FF",
        "C5B6FF",
        "E7C66C",
        "9EA7BC"
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
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.035),
                                Color.black.opacity(0.34)
                            ],
                            center: .center,
                            startRadius: 6,
                            endRadius: size * 0.24
                        )
                    )
                    .frame(width: size * 0.48, height: size * 0.48)
            }
            .scaleEffect(compactScale, anchor: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

}

struct CashflowHistorySummaryMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

    private var primaryTextOpacity: CGFloat {
        1 - (compactProgress * 0.22)
    }

    private var secondaryTextOpacity: CGFloat {
        1 - (compactProgress * 0.36)
    }

    private var accentTextOpacity: CGFloat {
        1 - (compactProgress * 0.48)
    }

    private var headerOffset: CGFloat {
        -compactProgress * 10
    }

    private var chipsOffset: CGFloat {
        -compactProgress * 28
    }

    private func chipAmountText(_ amount: Double) -> String {
        cashflowHistoryWholeAmountText(amount)
    }

    var body: some View {
        GeometryReader { proxy in
            let isNarrow = proxy.size.width < 380
            let totalHeight = CashflowHistorySummaryLayout.containerHeight(
                containerWidth: proxy.size.width,
                entryCount: summary.entries.count,
                collapseProgress: compactProgress
            )
            let chartExpandedSize: CGFloat = isNarrow ? 172 : 196
            let chartCollapsedSize: CGFloat = 88
            let chartSize = chartExpandedSize - ((chartExpandedSize - chartCollapsedSize) * compactProgress)
            let textWidth = max(134, proxy.size.width - chartSize - (isNarrow ? 18 : 28))
            let chipColumns = Array(
                repeating: GridItem(.flexible(), spacing: CashflowHistorySummaryLayout.chipSpacing),
                count: CashflowHistorySummaryLayout.columnCount(containerWidth: proxy.size.width)
            )
            let chipsVisibility = max(0, 1 - (compactProgress * 1.35))
            let chipsExpandedHeight = max(
                totalHeight
                - (isNarrow
                   ? CashflowHistorySummaryLayout.narrowExpandedHeaderHeight
                   : CashflowHistorySummaryLayout.wideExpandedHeaderHeight)
                - (CashflowHistorySummaryLayout.outerPadding * 2)
                - CashflowHistorySummaryLayout.sectionSpacing,
                0
            )

            VStack(alignment: .leading, spacing: CashflowHistorySummaryLayout.sectionSpacing) {
                HStack(alignment: .top, spacing: isNarrow ? 10 : 16) {
                    summaryTextBlock
                        .frame(width: textWidth, alignment: .leading)
                        .padding(.top, compactProgress < 0.75 ? 6 : 0)

                    summaryChart(size: chartSize)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .offset(y: headerOffset)

                if chipsVisibility > 0.01 {
                    LazyVGrid(columns: chipColumns, spacing: CashflowHistorySummaryLayout.chipSpacing) {
                        ForEach(summary.entries) { entry in
                            summaryChip(entry)
                        }
                    }
                    .frame(maxHeight: chipsExpandedHeight * chipsVisibility, alignment: .top)
                    .opacity(chipsVisibility)
                    .scaleEffect(0.96 + (chipsVisibility * 0.04), anchor: .top)
                    .offset(y: chipsOffset)
                    .clipped()
                }
            }
            .padding(.horizontal, CashflowHistorySummaryLayout.outerPadding)
            .padding(.vertical, CashflowHistorySummaryLayout.outerPadding)
            .frame(maxWidth: .infinity, minHeight: totalHeight, maxHeight: totalHeight, alignment: .topLeading)
            .background(cardBackground)
            .overlay(collapseShadowOverlay, alignment: .bottom)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: CashflowHistoryChrome.summaryCornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(0.16 + (compactProgress * 0.08)),
                radius: 18,
                x: 0,
                y: 10
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryTextBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(amountLabel)
                    .font(.system(size: compactProgress > 0.7 ? 23 : 29, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary.opacity(primaryTextOpacity))
                    .contentTransition(.numericText())
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleLabel)
                    .font(.system(size: compactProgress > 0.7 ? 15 : 18, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary.opacity(secondaryTextOpacity))
                    .lineLimit(2)
            }

            if let selectedEntry, compactProgress < 0.75 {
                Text(cashflowHistoryPercentText(share: selectedEntry.share))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: selectedEntry.tintHex).opacity(accentTextOpacity))
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
        CashflowHistorySurfaceBackground(
            cornerRadius: CashflowHistoryChrome.summaryCornerRadius,
            isElevated: true
        )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: CashflowHistoryChrome.summaryCornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
    }

    private var collapseShadowOverlay: some View {
        let overlayOpacity = min(max((compactProgress - 0.28) / 0.72, 0), 1)

        return LinearGradient(
            colors: [
                Color.clear,
                Color.black.opacity(0.04 * overlayOpacity),
                Color.black.opacity(0.14 * overlayOpacity)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 92)
        .allowsHitTesting(false)
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
                ZStack {
                    Circle()
                        .fill(isSelected ? tint.opacity(0.22) : Color.white.opacity(0.06))
                    Circle()
                        .stroke(isSelected ? tint.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 0.8)

                    Text(entry.icon)
                        .font(.system(size: 15))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)

                    Text(chipAmountText(entry.amount))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: CashflowHistoryChrome.chipCornerRadius, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.16) : Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CashflowHistoryChrome.chipCornerRadius, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.30) : Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CashflowHistorySummaryContainer: View {
    let summary: CashflowHistorySummaryModel
    @Binding var selectedCategoryRawValue: String?
    let collapseProgress: CGFloat
    let containerWidth: CGFloat

    var body: some View {
        let resolvedWidth = max(containerWidth, 0)
        let height = CashflowHistorySummaryLayout.containerHeight(
            containerWidth: resolvedWidth,
            entryCount: summary.entries.count,
            collapseProgress: collapseProgress
        )

        CashflowHistorySummaryCard(
            summary: summary,
            selectedCategoryRawValue: $selectedCategoryRawValue,
            collapseProgress: collapseProgress
        )
        .frame(width: resolvedWidth, height: height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: height)
    }
}

struct CashflowHistorySummaryResponsiveContainer: View {
    let summary: CashflowHistorySummaryModel
    @Binding var selectedCategoryRawValue: String?
    let collapseProgress: CGFloat

    @State private var measuredWidth: CGFloat = max(UIScreen.main.bounds.width - 48, 0)

    var body: some View {
        CashflowHistorySummaryContainer(
            summary: summary,
            selectedCategoryRawValue: $selectedCategoryRawValue,
            collapseProgress: collapseProgress,
            containerWidth: measuredWidth
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        measuredWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newValue in
                        measuredWidth = newValue
                    }
            }
        }
    }
}
