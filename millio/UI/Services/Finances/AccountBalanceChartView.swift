//
//  AccountBalanceChartView.swift
//  millio
//
//  История баланса счёта: sparkline-строка + full-screen chart sheet.
//  Данные берёт из AccountBalanceHistoryStore.
//

import SwiftUI
import Charts

// MARK: - Период

enum AccountBalancePeriod: String, CaseIterable {
    case week = "7Д"
    case month = "1М"
    case threeMonths = "3М"
    case year = "1Г"

    var days: Int {
        switch self {
        case .week:        return 7
        case .month:       return 30
        case .threeMonths: return 90
        case .year:        return 365
        }
    }
}

// MARK: - Точка графика

private struct BalancePoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
}

// MARK: - Sparkline (встраивается в FinanceAccountRow)

struct AccountBalanceSparklineView: View {
    let accountID: String
    let currency: String
    let color: Color

    private var points: [Double] {
        AccountBalanceHistoryStore.dailyAmounts(
            accountID: accountID,
            currency: currency,
            daysCount: 14
        ).compactMap { $0 }
    }

    var body: some View {
        if points.count >= 2 {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { i, value in
                    LineMark(
                        x: .value("", i),
                        y: .value("", value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 24)
        }
    }
}

// MARK: - Full-screen chart sheet

struct AccountBalanceChartView: View {
    let accountID: String
    let accountName: String
    let currency: String
    let accentColor: Color
    /// Вызывается, когда пользователь хочет перейти в полноценную деталку счёта
    /// (FinanceDynamicsView) — там есть Edit/Delete, которых нет в этом read-only sheet.
    /// nil, если переход недоступен (например, вызов из виджета/превью).
    var onOpenAccountDetail: (() -> Void)? = nil

    @State private var selectedPeriod: AccountBalancePeriod = .month
    @State private var selectedPoint: BalancePoint? = nil
    @Environment(\.dismiss) private var dismiss

    private var allPoints: [BalancePoint] {
        let rawAmounts = AccountBalanceHistoryStore.dailyAmounts(
            accountID: accountID,
            currency: currency,
            daysCount: selectedPeriod.days
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Заполняем пропуски: forward-fill от первого известного значения
        var lastKnown: Double? = nil
        var result: [BalancePoint] = []
        for (i, raw) in rawAmounts.enumerated() {
            let daysBack = rawAmounts.count - 1 - i
            let date = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
            if let v = raw {
                lastKnown = v
            }
            if let v = lastKnown {
                result.append(BalancePoint(id: i, date: date, value: v))
            }
        }
        return result
    }

    private var hasEnoughData: Bool { allPoints.count >= 2 }

    private var isAvailable: Bool {
        let count = AccountBalanceHistoryStore.recordCount(
            accountID: accountID,
            currency: currency
        )
        return count >= Int(Double(selectedPeriod.days) * 0.1)
    }

    private var minValue: Double { allPoints.map(\.value).min() ?? 0 }
    private var maxValue: Double { allPoints.map(\.value).max() ?? 1 }

    private var displayPoint: BalancePoint? { selectedPoint ?? allPoints.last }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppSpacing.xxl) {
                        headerSection
                        periodPicker
                        if hasEnoughData {
                            chartSection
                        } else {
                            emptyState
                        }
                        statsSection
                    }
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.top, AppSpacing.m)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(AppColors.textSecondary)
                            .font(.millioBody)
                    }
                }
                // Read-only sheet без единого действия был багом для легаси-счетов
                // (нет доступа к Edit/Delete) — кнопка ведёт в FinanceDynamicsView.
                if let onOpenAccountDetail {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            onOpenAccountDetail()
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(AppColors.textSecondary)
                                .font(.millioBody)
                        }
                        .accessibilityLabel(L("finances.balance_chart.open_account_accessibility"))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(accountName)
                .font(.millioHeadline)
                .foregroundColor(AppColors.textSecondary)
            if let point = displayPoint {
                Text(formattedAmount(point.value))
                    .font(.millioDisplayLarge)
                    .foregroundColor(AppColors.textPrimary)
                Text(formatDate(point.date))
                    .font(.millioCalloutRegular)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(AccountBalancePeriod.allCases, id: \.self) { period in
                let enoughData = AccountBalanceHistoryStore.recordCount(
                    accountID: accountID, currency: currency
                ) >= Int(Double(period.days) * 0.1)

                Button {
                    if enoughData { selectedPeriod = period }
                } label: {
                    Text(period.rawValue)
                        .font(.millioCalloutSemibold)
                        .foregroundColor(selectedPeriod == period ? .black : (enoughData ? AppColors.textPrimary : AppColors.textSecondary))
                        .padding(.horizontal, AppSpacing.m)
                        .padding(.vertical, AppSpacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPeriod == period ? accentColor : Color.white.opacity(enoughData ? 0.08 : 0.03))
                        )
                }
                .disabled(!enoughData)
            }
            Spacer()
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        Chart {
            ForEach(allPoints) { point in
                AreaMark(
                    x: .value("Дата", point.date),
                    yStart: .value("Min", minValue),
                    yEnd: .value("Баланс", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor.opacity(0.3), accentColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Дата", point.date),
                    y: .value("Баланс", point.value)
                )
                .foregroundStyle(accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            if let sel = selectedPoint {
                RuleMark(x: .value("", sel.date))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                PointMark(
                    x: .value("", sel.date),
                    y: .value("", sel.value)
                )
                .foregroundStyle(accentColor)
                .symbolSize(60)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(compactAmount(v))
                            .font(.millioMicro)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.08))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.millioMicro)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // plotAreaFrame устарел с iOS 17 — используем plotFrame (Optional).
                                guard let plotAnchor = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plotAnchor].origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                selectedPoint = allPoints.min(by: {
                                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                })
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedPoint = nil
                                }
                            }
                    )
            }
        }
        .frame(height: 240)
        .animation(.easeInOut(duration: 0.3), value: selectedPeriod)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textSecondary)
            Text("Накапливаем историю")
                .font(.millioHeadline)
                .foregroundColor(AppColors.textPrimary)
            Text("График появится через несколько дней\nпосле использования приложения")
                .font(.millioCalloutRegular)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, AppSpacing.xxxl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats

    private var statsSection: some View {
        let values = allPoints.map(\.value)
        guard values.count >= 2,
              let minV = values.min(),
              let maxV = values.max()
        else { return AnyView(EmptyView()) }

        let first = values.first!
        let last = values.last!
        let change = last - first
        let changePct = first != 0 ? (change / abs(first)) * 100 : 0
        let isPositive = change >= 0

        return AnyView(
            HStack(spacing: AppSpacing.m) {
                statCell(title: "Минимум", value: formattedAmount(minV))
                Divider().frame(height: 36).background(Color.white.opacity(0.1))
                statCell(title: "Максимум", value: formattedAmount(maxV))
                Divider().frame(height: 36).background(Color.white.opacity(0.1))
                statCell(
                    title: "Изменение",
                    value: "\(isPositive ? "+" : "")\(String(format: "%.1f", changePct))%",
                    valueColor: isPositive ? Color(hex: "4ADE80") : Color(hex: "FF6B6B")
                )
            }
            .padding(AppSpacing.l)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        )
    }

    private func statCell(title: String, value: String, valueColor: Color = AppColors.textPrimary) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(title)
                .font(.millioMicro)
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(.millioCalloutSemibold)
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formattedAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = " "
        let formatted = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        let prefix = value < 0 ? "−" : ""
        return "\(prefix)\(formatted) \(currency)"
    }

    private func compactAmount(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return String(format: "%.1fМ", value / 1_000_000)
        } else if abs(value) >= 1_000 {
            return String(format: "%.0fК", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
