//
//  FinanceDashboardWidget.swift
//  millio
//
//  Created by Codex on 03.04.2026.
//

import SwiftUI

enum FinanceDashboardChartXAxisStride: String, Equatable {
    case day
    case month

    var calendarComponent: Calendar.Component {
        switch self {
        case .day:
            return .day
        case .month:
            return .month
        }
    }
}

enum FinanceDashboardPeriodOption: String, CaseIterable, Identifiable {
    case all = "All"
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case year = "1Y"

    static let defaultOption: Self = .week

    var id: String { rawValue }

    var dynamicsPeriod: DynamicsPeriod {
        switch self {
        case .all:
            return .all
        case .day:
            return .day
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
        }
    }
}

enum FinanceDashboardChartBuilder {
    struct Output: Equatable {
        let points: [ChartDataPoint]
        let xAxisStride: FinanceDashboardChartXAxisStride
        let xAxisCount: Int
    }

    static let defaultPeriod: DynamicsPeriod = FinanceDashboardPeriodOption.defaultOption.dynamicsPeriod

    static func makeOutput(
        points: [ChartDataPoint],
        period: DynamicsPeriod
    ) -> Output {
        Output(
            points: points.sorted { $0.date < $1.date },
            xAxisStride: xAxisStride(for: period),
            xAxisCount: xAxisCount(for: period)
        )
    }

    private static func xAxisStride(for period: DynamicsPeriod) -> FinanceDashboardChartXAxisStride {
        switch period {
        case .day, .week, .month, .custom:
            return .day
        case .year, .all:
            return .month
        }
    }

    private static func xAxisCount(for period: DynamicsPeriod) -> Int {
        switch period {
        case .day:
            return 6
        case .week:
            return 7
        case .month:
            return 6
        case .year:
            return 6
        case .all:
            return 5
        case .custom:
            return 6
        }
    }
}

struct FinanceDashboardWidget: View {
    @ObservedObject var financeViewModel: FinanceViewModel
    @ObservedObject var dynamicsViewModel: FinanceDynamicsViewModel
    let onOpenFinances: () -> Void
    let onAddProduct: () -> Void

    @State private var selectedPoint: (date: Date, value: Double)?
    @State private var isCustomPeriodSheetPresented = false
    @State private var didApplyDefaultPeriod = false

    private var accent: Color {
        AppColors.brandPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if isLoading {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if productCount == 0 || chartOutput.points.isEmpty {
                Text(MainLocalization.text(MainLocalization.dashboardWidgetFinancesEmpty))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            } else {
                metrics
                chartSection
                periodControls
            }

            HStack(spacing: 12) {
                dashboardButton(
                    title: MainLocalization.text(MainLocalization.dashboardWidgetFinancesAddProduct),
                    icon: "plus",
                    action: onAddProduct
                )

                dashboardButton(
                    title: MainLocalization.text(MainLocalization.dashboardWidgetFinancesOpen),
                    icon: "chart.line.uptrend.xyaxis",
                    action: onOpenFinances
                )
            }
        }
        .padding(18)
        .mainSectionSurface(tint: accent, cornerRadius: 30)
        .sheet(isPresented: $isCustomPeriodSheetPresented) {
            FinanceDynamicsPeriodSelectorView(viewModel: dynamicsViewModel)
        }
        .task(id: reloadToken) {
            dynamicsViewModel.handle(.loadData)
        }
        .onAppear {
            financeViewModel.handle(.loadGroups)
            financeViewModel.handle(.loadAccounts)
            if !didApplyDefaultPeriod,
               dynamicsViewModel.state.period != .custom,
               dynamicsViewModel.state.period != FinanceDashboardChartBuilder.defaultPeriod {
                dynamicsViewModel.handle(.setPeriod(FinanceDashboardChartBuilder.defaultPeriod))
                didApplyDefaultPeriod = true
            } else {
                didApplyDefaultPeriod = true
                dynamicsViewModel.handle(.loadData)
            }
        }
        .onChange(of: dynamicsViewModel.state.period) { _, _ in
            selectedPoint = nil
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(MainLocalization.text(MainLocalization.dashboardWidgetFinancesTitle))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(MainLocalization.text(MainLocalization.dashboardWidgetFinancesSubtitle))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 12)

            Button(action: onOpenFinances) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(balanceText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                if let deltaBadgeText {
                    Text(deltaBadgeText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(deltaToneColor)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(deltaToneColor.opacity(0.18))
                        )
                }
            }

            HStack(spacing: 8) {
                Text(dateRangeText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                Text(
                    MainLocalization.format(
                        MainLocalization.dashboardWidgetFinancesProductsCount,
                        productCount
                    )
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary.opacity(0.92))
                .lineLimit(1)
            }
        }
    }

    private var chartSection: some View {
        let values = chartOutput.points.map(\.value)
        let niceY = NiceYScale.make(values: values, preferZeroBaseline: true)
        let xDomain = (chartOutput.points.first?.date ?? Date())...(chartOutput.points.last?.date ?? Date())

        return FinanceChartContainerView(
            points: chartOutput.points,
            selectedPoint: selectedPoint,
            seriesColor: AppColors.brandPrimary,
            niceY: niceY,
            xDomain: xDomain,
            xAxisStride: chartOutput.xAxisStride.calendarComponent,
            xAxisCount: chartOutput.xAxisCount,
            currencyCode: displayCurrency,
            isAmountHidden: financeViewModel.state.isAmountHidden,
            onSelectPoint: { selectedPoint = $0 }
        )
        .frame(height: 212)
    }

    private var periodControls: some View {
        HStack(spacing: 10) {
            ForEach(FinanceDashboardPeriodOption.allCases) { option in
                Button {
                    dynamicsViewModel.handle(.setPeriod(option.dynamicsPeriod))
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPeriodSelected(option.dynamicsPeriod) ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(minWidth: 54)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 2)
                        .background(periodButtonBackground(isSelected: isPeriodSelected(option.dynamicsPeriod)))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Button {
                isCustomPeriodSheetPresented = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(dynamicsViewModel.state.period == .custom ? AppColors.textPrimary : AppColors.textSecondary)
                    .frame(width: 56, height: 48)
                    .background(periodButtonBackground(isSelected: dynamicsViewModel.state.period == .custom))
            }
            .buttonStyle(.plain)
        }
    }

    private func dashboardButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .mainInnerSurface(tint: accent, cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    private func isPeriodSelected(_ period: DynamicsPeriod) -> Bool {
        dynamicsViewModel.state.period == period
    }

    private func periodButtonBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? accent.opacity(0.18) : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var reloadToken: String {
        [
            financeViewModel.state.displayCurrency,
            financeViewModel.state.availableCards.map {
                "\($0.cardUniqueID)_\($0.balance)_\($0.currency)_\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: "|"),
            financeViewModel.state.availableCredits.map {
                "\($0.creditUniqueID)_\($0.remainingAmount)_\($0.currency)_\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: "|"),
            financeViewModel.state.availableInvestments.map {
                "\($0.investmentUniqueID)_\($0.amount)_\($0.currency)_\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: "|"),
            dynamicsViewModel.state.displayCurrency
        ].joined(separator: "~")
    }

    private var isLoading: Bool {
        dynamicsViewModel.state.isLoading
    }

    private var productCount: Int {
        financeViewModel.state.availableCards.count
        + financeViewModel.state.availableCredits.count
        + financeViewModel.state.availableInvestments.count
    }

    private var chartOutput: FinanceDashboardChartBuilder.Output {
        FinanceDashboardChartBuilder.makeOutput(
            points: dynamicsViewModel.state.chartData,
            period: dynamicsViewModel.state.period
        )
    }

    private var displayedBalance: Double {
        selectedPoint?.value ?? dynamicsViewModel.state.currentBalance
    }

    private var displayCurrency: String {
        normalizeCurrency(dynamicsViewModel.state.displayCurrency.isEmpty
            ? financeViewModel.state.displayCurrency
            : dynamicsViewModel.state.displayCurrency)
    }

    private var balanceText: String {
        FinanceAmountText.withCurrency(
            value: displayedBalance,
            currencySymbol: displayCurrency,
            isHidden: financeViewModel.state.isAmountHidden
        )
    }

    private var deltaBadgeText: String? {
        let delta = dynamicsViewModel.state.periodDelta
        guard abs(delta.absolute) > 0.0001 || abs(delta.percent) > 0.0001 else { return nil }

        return "\(signedAmountText(delta.absolute))  \(FinanceAmountText.percent(value: delta.percent, isHidden: financeViewModel.state.isAmountHidden))"
    }

    private var deltaToneColor: Color {
        let delta = dynamicsViewModel.state.periodDelta.absolute
        if delta > 0.0001 {
            return AppColors.quickSetupAccentMint
        }
        if delta < -0.0001 {
            return AppColors.profileIconOrange
        }
        return AppColors.textSecondary
    }

    private var dateRangeText: String {
        if let selectedPoint {
            return selectedPoint.date.formatted(date: .abbreviated, time: .omitted)
        }

        return formatDateRange(
            start: dynamicsViewModel.state.periodStartDate,
            end: dynamicsViewModel.state.periodEndDate
        )
    }

    private func signedAmountText(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        let amount = financeViewModel.state.isAmountHidden
            ? FinanceAmountText.maskedDigits(for: abs(value))
            : FinanceAmountText.decimal(value: abs(value))
        return "\(sign)\(amount) \(displayCurrency)"
    }

    private func formatDateRange(start: Date, end: Date) -> String {
        let locale = AppLocalization.currentAppLocale
        let calendar = Calendar.current

        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(
                Date.FormatStyle(date: .abbreviated, time: .omitted)
                    .locale(locale)
            )
        }

        let startStyle = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        let endStyle = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        return "\(start.formatted(startStyle)) - \(end.formatted(endStyle))"
    }

    private func normalizeCurrency(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
