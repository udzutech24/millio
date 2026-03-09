//
//  CashflowView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData
import UIKit

enum CashflowValueTone {
    case positive
    case negative
    case neutral
}

func cashflowValueTone(for value: Double, epsilon: Double = 0.0000001) -> CashflowValueTone {
    if value > epsilon {
        return .positive
    }
    if value < -epsilon {
        return .negative
    }
    return .neutral
}

/// Единый форматтер чисел для экрана Cashflow: без суффикса валюты в строках статистики.
func cashflowAmountText(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: amount)) ?? "0"
}

func cashflowSignedAmountText(_ amount: Double) -> String {
    let absolute = cashflowAmountText(abs(amount))
    if amount > 0.0000001 {
        return "+\(absolute)"
    }
    if amount < -0.0000001 {
        return "-\(absolute)"
    }
    return absolute
}

func cashflowCurrencyCodeLabel(_ code: String) -> String {
    code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}

func cashflowShouldShowNoCardsHint(hasEntries: Bool, hasAvailableCards: Bool) -> Bool {
    !hasEntries && !hasAvailableCards
}

struct CashflowActionButtonsLayout {
    static let buttonCount: CGFloat = 3
    static let buttonSpacing: CGFloat = 10
    static let compactButtonWidthThreshold: CGFloat = 112

    static func shouldUseCompactMetrics(containerWidth: CGFloat) -> Bool {
        guard containerWidth > 0 else { return false }
        let totalSpacing = buttonSpacing * (buttonCount - 1)
        let buttonWidth = (containerWidth - totalSpacing) / buttonCount
        return buttonWidth < compactButtonWidthThreshold
    }
}

struct CashflowEmptyStateIntroPrefs {
    static let hiddenKey = "cashflow_main_empty_intro_hidden"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isHidden() -> Bool {
        defaults.bool(forKey: Self.hiddenKey)
    }

    func setHidden(_ hidden: Bool) {
        defaults.set(hidden, forKey: Self.hiddenKey)
    }
}

struct CashflowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: CashflowViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                CashflowContentView(
                    viewModel: viewModel
                )
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CashflowViewModel(modelContext: modelContext)
            }
            // Перезагружаем данные при каждом появлении экрана
            viewModel?.handle(.loadCards)
            viewModel?.handle(.loadTransactions)
        }
        .onChange(of: appState.primaryCurrencyCode) { oldValue, newValue in
            viewModel?.handle(.syncPrimaryCurrencyChange(old: oldValue, new: newValue))
        }
        .onDisappear {
            viewModel?.handle(.setDisplayCurrency(appState.primaryCurrencyCode))
        }
    }
}

// MARK: - Cashflow Content View

private struct CashflowContentView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @State private var draftStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var draftEndDate: Date = Date()
    @State private var showAssetChangeInfoSheet: Bool = false
    @State private var showIncomeBreakdown: Bool = false
    @State private var showExpenseBreakdown: Bool = false
    @State private var isEmptyIntroHidden: Bool = CashflowEmptyStateIntroPrefs().isHidden()
    @State private var selectedTopAction: TopToolbarAction = .currency
    @State private var showExpandedChart: Bool = false
    @State private var fullScreenChartVisiblePeriods: Int = 4
    @State private var historyInitialFilter: CashflowHistoryTypeFilter = .all
    @State private var historyInitialStartDate: Date? = nil
    @State private var historyInitialEndDate: Date? = nil
    private let currentRoute: AppRoute = .cashflow
    
    private let neonCyan = Color(hex: "47D7FF")
    private let neonViolet = Color(hex: "8A6BFF")
    private let neonPositive = Color(hex: "6DFFC7")
    private let neonNegative = Color(hex: "FF6666")
    private let primarySecondaryText = Color.white.opacity(0.78)
    private let panelFill = Color.white.opacity(0.035)
    private let innerGlassFill = Color.white.opacity(0.018)
    private let innerSeparator = Color.white.opacity(0.16)
    private let panelCornerRadius: CGFloat = 22
    private let rowCornerRadius: CGFloat = 16

    private enum TopToolbarAction: CaseIterable {
        case currency
        case history
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    cashflowChartSection

                    if viewModel.state.transactions.isEmpty {
                        emptyTransactionsOnboardingState
                    }

                    // Сводка активов за период
                    assetBreakdownSection

                    if let warning = viewModel.state.currencyConversionWarning {
                        currencyWarningView(text: warning)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Cashflow")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { topToolbar }
        .safeAreaInset(edge: .bottom) {
            actionButtonsSection
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color.black.opacity(0.92))
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionEditor },
            set: { if !$0 { viewModel.handle(.hideTransactionEditor) } }
        )) {
            if let editingTransaction = viewModel.state.editingTransaction {
                CashflowTransactionEditorView(
                    viewModel: viewModel,
                    transaction: editingTransaction
                )
            } else if let creatingType = viewModel.state.creatingTransactionType {
                switch creatingType {
                case .income:
                    CashflowIncomeTransactionSheet(viewModel: viewModel)
                case .expense:
                    CashflowExpenseTransactionSheet(viewModel: viewModel)
                case .transfer:
                    CashflowTransferTransactionSheet(viewModel: viewModel)
                case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
                    CashflowTransactionEditorView(
                        viewModel: viewModel,
                        transactionType: creatingType
                    )
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showPeriodSelector },
            set: { if !$0 { viewModel.handle(.hidePeriodSelector) } }
        )) {
            customPeriodSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionsHistory },
            set: { if !$0 { viewModel.handle(.hideTransactionsHistory) } }
        )) {
            CashflowTransactionsHistoryView(
                viewModel: viewModel,
                initialFilter: historyInitialFilter,
                initialStartDate: historyInitialStartDate,
                initialEndDate: historyInitialEndDate
            )
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCurrencySelector },
            set: { if !$0 { viewModel.handle(.hideCurrencySelector) } }
        )) {
            CashflowCurrencySelectorView(viewModel: viewModel)
        }
        .sheet(isPresented: $showAssetChangeInfoSheet) {
            assetChangeInfoSheet
        }
        .fullScreenCover(isPresented: $showExpandedChart) {
            cashflowExpandedChartSheet
        }
        .onAppear {
            hideEmptyIntroIfNeeded()
        }
        .onChange(of: viewModel.state.transactions.map(\.transactionTypeRaw)) { _, _ in
            hideEmptyIntroIfNeeded()
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        GeometryReader { proxy in
            let useCompactMetrics = CashflowActionButtonsLayout.shouldUseCompactMetrics(
                containerWidth: proxy.size.width
            )
            let incomeTitle = String(localized: "main.quick_action.income")
            let expenseTitle = String(localized: "main.quick_action.expense")
            let transferTitle = String(localized: "cashflow.quick_action.transfer")

            HStack(spacing: CashflowActionButtonsLayout.buttonSpacing) {
                CashflowActionButton(
                    accessibilityLabel: incomeTitle,
                    title: incomeTitle,
                    icon: QuickActionIcons.income,
                    gradientColors: AppColors.incomeGradient,
                    style: .primary,
                    compactMetrics: useCompactMetrics
                ) {
                    fireLightImpact()
                    viewModel.handle(.addTransaction(.income))
                }

                CashflowActionButton(
                    accessibilityLabel: expenseTitle,
                    title: expenseTitle,
                    icon: QuickActionIcons.expense,
                    gradientColors: AppColors.expenseGradient,
                    style: .secondary,
                    compactMetrics: useCompactMetrics
                ) {
                    fireLightImpact()
                    viewModel.handle(.addTransaction(.expense))
                }

                CashflowActionButton(
                    accessibilityLabel: transferTitle,
                    title: transferTitle,
                    icon: QuickActionIcons.transfer,
                    gradientColors: AppColors.cashflowGradient,
                    style: .secondary,
                    compactMetrics: useCompactMetrics
                ) {
                    fireLightImpact()
                    viewModel.handle(.addTransaction(.transfer))
                }
            }
        }
        .frame(height: 64)
    }
    
    // MARK: - Period Stats Section
    
    private var assetBreakdownSection: some View {
        VStack(spacing: 14) {
            statRow(
                title: String(localized: "cashflow.stats.assets_start"),
                value: formatMoney(viewModel.state.assetsAtPeriodStart),
                valueColor: AppColors.textPrimary
            )
            rowDivider

            expandableStatRow(
                title: String(localized: "Income"),
                value: formatSignedMoney(viewModel.state.totalIncome),
                valueColor: positiveColor(for: viewModel.state.totalIncome),
                isExpanded: $showIncomeBreakdown
            )
            
            if showIncomeBreakdown {
                breakdownList(
                    entries: viewModel.state.incomeBreakdown,
                    showNoCardsHint: cashflowShouldShowNoCardsHint(
                        hasEntries: !viewModel.state.incomeBreakdown.isEmpty,
                        hasAvailableCards: !viewModel.state.availableCards.isEmpty
                    ),
                    signedAmount: { $0 },
                    valueColor: { positiveColor(for: $0) }
                )
            }
            rowDivider

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text("Asset value change")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(primarySecondaryText)
                        Button {
                            showAssetChangeInfoSheet = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(primarySecondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(formatSignedMoney(viewModel.state.assetValueChange))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(positiveColor(for: viewModel.state.assetValueChange))
                        .contentTransition(.numericText())
                }

            }
            .padding(.horizontal, 4)
            rowDivider

            expandableStatRow(
                title: String(localized: "cashflow.stats.expenses"),
                value: formatSignedMoney(-viewModel.state.contributedExpense),
                valueColor: negativeColor(for: -viewModel.state.contributedExpense),
                isExpanded: $showExpenseBreakdown
            )
            
            if showExpenseBreakdown {
                breakdownList(
                    entries: viewModel.state.expenseBreakdown,
                    showNoCardsHint: cashflowShouldShowNoCardsHint(
                        hasEntries: !viewModel.state.expenseBreakdown.isEmpty,
                        hasAvailableCards: !viewModel.state.availableCards.isEmpty
                    ),
                    signedAmount: { -$0 },
                    valueColor: { negativeColor(for: -$0) }
                )
            }
            rowDivider

            VStack(spacing: 8) {
                statRow(
                    title: String(localized: "cashflow.stats.assets_end"),
                    value: formatMoney(viewModel.state.assetsAtPeriodEnd),
                    valueColor: AppColors.textPrimary
                )

                Divider()
                    .overlay(innerSeparator)

                HStack {
                    Text("Result")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(formatSignedMoney(viewModel.state.periodTotalChange))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(positiveColor(for: viewModel.state.periodTotalChange))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(financeCardBackground(cornerRadius: panelCornerRadius))
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: viewModel.state.periodTotalChange)
    }

    private func statRow(title: String, value: String, valueColor: Color) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(primarySecondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func expandableStatRow(
        title: String,
        value: String,
        valueColor: Color,
        isExpanded: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(primarySecondaryText)
            Spacer()
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        isExpanded.wrappedValue.toggle()
                    }
                    fireLightImpact()
                } label: {
                    Image(systemName: isExpanded.wrappedValue ? "minus.circle" : "plus.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(primarySecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isExpanded.wrappedValue ? "Hide details" : "Show details"))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func breakdownList(
        entries: [CashflowCategoryBreakdownEntry],
        showNoCardsHint: Bool,
        signedAmount: @escaping (Double) -> Double,
        valueColor: @escaping (Double) -> Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                if showNoCardsHint {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("cashflow.breakdown.empty.no_cards.title")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primarySecondaryText)

                        Text("cashflow.breakdown.empty.no_cards.subtitle")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(primarySecondaryText)

                        Button {
                            appState.pendingOpenFinanceAddCard = true
                            MiniAppNavigation.navigate(to: .finances, from: currentRoute, router: router)
                            fireLightImpact()
                        } label: {
                            Text("cashflow.breakdown.empty.no_cards.cta")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("No transactions")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(primarySecondaryText)
                }
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.title)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(primarySecondaryText)
                            .lineLimit(2)
                        Spacer()
                        let value = signedAmount(entry.convertedAmount)
                        Text(formatSignedMoney(value))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(valueColor(entry.convertedAmount))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func currencyWarningView(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.warning)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(primarySecondaryText)
                .lineLimit(3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .fill(AppColors.warning.opacity(0.10))
        )
        .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .stroke(AppColors.warning.opacity(0.45), lineWidth: 1)
        }
        .accessibilityLabel(Text(text))
    }
    
    // MARK: - Period Selection Section

    private var periodSelectionHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.handle(.movePeriodBackward)
                    }
                    fireLightImpact()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: 38, height: 38)
                        .background(periodControlBackground)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    draftStartDate = viewModel.state.customStartDate
                    draftEndDate = viewModel.state.customEndDate
                    viewModel.handle(.showPeriodSelector)
                    fireLightImpact()
                } label: {
                    Image("calendar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .padding(8)
                        .background(periodControlBackground)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.handle(.movePeriodForward)
                    }
                    fireLightImpact()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(viewModel.canMovePeriodForward() ? Color.white.opacity(0.95) : Color.white.opacity(0.35))
                        .frame(width: 38, height: 38)
                        .background(periodControlBackground)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canMovePeriodForward())
            }

            let range = viewModel.currentDateRange()
            Text(String(format: String(localized: "cashflow.period.range_format"), formatPeriod(range.0), formatPeriod(range.1)))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(primarySecondaryText)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.state.customStartDate)
    }
    
    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        let itemSize: CGFloat = 28
        let iconSize: CGFloat = 18

        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))

                Menu {
                    ForEach(MiniAppNavigation.destinations(excluding: currentRoute)) { destination in
                        Button {
                            MiniAppNavigation.navigate(to: destination.route, from: currentRoute, router: router)
                        } label: {
                            Label(destination.title, systemImage: destination.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: iconSize - 2, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.90))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Quick navigation for mini apps"))
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                selectedTopAction = .history
                openHistory(filter: .all)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(selectedTopAction == .history ? Color.white.opacity(0.96) : primarySecondaryText)
                    .frame(width: 42, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Transaction history"))
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                selectedTopAction = .currency
                viewModel.handle(.showCurrencySelector)
                fireLightImpact()
            } label: {
                Text(toolbarCurrencyLabel())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                .foregroundStyle(selectedTopAction == .currency ? Color.white.opacity(0.96) : primarySecondaryText)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Display currency selector"))
        }
    }
    
    private func formatPeriod(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func formatMoney(_ amount: Double) -> String {
        cashflowAmountText(amount)
    }

    private func formatSignedMoney(_ amount: Double) -> String {
        cashflowSignedAmountText(amount)
    }

    private func displayCurrencyLabel() -> String {
        let code = viewModel.state.displayCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return "" }
        return MonetaCurrency(rawValue: code)?.symbol ?? code
    }

    private func toolbarCurrencyLabel() -> String {
        let code = cashflowCurrencyCodeLabel(viewModel.state.displayCurrency)
        if !code.isEmpty {
            return code
        }
        return displayCurrencyLabel()
    }

    private func openHistory(filter: CashflowHistoryTypeFilter, dateRange: ClosedRange<Date>? = nil) {
        historyInitialFilter = filter
        let calendar = Calendar.current
        let range: ClosedRange<Date> = dateRange ?? cashflowInsightsSelectedDateRange
        historyInitialStartDate = calendar.startOfDay(for: range.lowerBound)
        historyInitialEndDate = calendar.startOfDay(for: range.upperBound)
        viewModel.handle(.showTransactionsHistory)
        fireLightImpact()
    }

    private func financeCardBackground(cornerRadius: CGFloat) -> some View {
        let borderGradient = LinearGradient(
            colors: [neonCyan.opacity(0.72), neonViolet.opacity(0.62)],
            startPoint: .leading,
            endPoint: .trailing
        )

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(panelFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderGradient, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
            )
            .shadow(color: neonCyan.opacity(0.08), radius: 8, x: 0, y: 0)
    }

    private func financeInnerBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(innerGlassFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
            )
    }

    private var periodControlBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
    }

    private func positiveColor(for value: Double) -> Color {
        switch cashflowValueTone(for: value) {
        case .positive:
            return neonPositive
        case .negative:
            return neonNegative
        case .neutral:
            return primarySecondaryText
        }
    }

    private func negativeColor(for value: Double) -> Color {
        switch cashflowValueTone(for: value) {
        case .negative:
            return neonNegative
        case .positive:
            return neonPositive
        case .neutral:
            return primarySecondaryText
        }
    }

    private var rowDivider: some View {
        Divider()
            .overlay(innerSeparator)
            .padding(.horizontal, 4)
    }

    private var cashflowChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            periodSelectionHeader

            if EntitlementPolicy.canUseCashflowChart(isPro: appState.isPro) {
                if hasChartData {
                    cashflowChartContent
                } else {
                    cashflowChartEmptyState
                }
            } else {
                cashflowChartProLocked
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(financeCardBackground(cornerRadius: panelCornerRadius))
    }

    private var cashflowChartContent: some View {
        let presentation = cashflowInsightsPresentation
        let granularity = cashflowInsightsGranularity

        return VStack(spacing: 18) {
            HStack {
                Text("cashflow.chart.title")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(primarySecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer()

                Button {
                    showExpandedChart = true
                    fireLightImpact()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(periodControlBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("cashflow.chart.expand"))
            }

            cashflowInsightsBars(
                presentation: presentation,
                granularity: granularity,
                chartHeight: CashflowInsightsControlsStyle.compactBarsHeight,
                maxBarHeight: 110,
                minimumGroupWidth: 56,
                barWidth: 26,
                labelFontSize: 14
            )

            
        }
    }

    private var cashflowExpandedChartSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HStack(spacing: 12) {
                            cashflowInsightCard(
                                model: cashflowFullScreenPresentation.expenseCard,
                                accent: neonNegative,
                                onTap: {
                                    openHistory(filter: .expense)
                                }
                            )
                            cashflowInsightCard(
                                model: cashflowFullScreenPresentation.incomeCard,
                                accent: neonPositive,
                                onTap: {
                                    openHistory(filter: .income)
                                }
                            )
                        }

                        cashflowFullScreenChart
                    }
                    .padding(16)
                }
                .safeAreaInset(edge: .bottom, alignment: .center, spacing: 0) {
                    VStack(spacing: 12) {
                        fullScreenVisiblePeriodsControl
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                            )
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("cashflow.chart.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showExpandedChart = false
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }

    private var cashflowChartEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 26))
                .foregroundStyle(primarySecondaryText)
            Text("cashflow.chart.empty")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(primarySecondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(financeInnerBackground(cornerRadius: rowCornerRadius))
    }

    private var cashflowChartProLocked: some View {
        ProChartUpsellView(
            titleKey: "cashflow.chart.pro.title",
            subtitleKey: "cashflow.chart.pro.subtitle",
            ctaKey: "finances.dynamics.pro.cta",
            size: .compact,
            onTapCTA: { router.push(.subscription) }
        )
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(financeInnerBackground(cornerRadius: rowCornerRadius))
    }

    private var hasChartData: Bool {
        abs(viewModel.state.totalIncome) > 0.000001 || abs(viewModel.state.totalExpense) > 0.000001
    }

    private var cashflowInsightsSelectedDateRange: ClosedRange<Date> {
        let current = viewModel.currentDateRange()
        let start = min(current.0, current.1)
        let end = max(current.0, current.1)
        return start...end
    }

    private var cashflowInsightsGranularity: CashflowInsightsGranularity {
        .month
    }

    private var cashflowInsightsPresentation: CashflowInsightsPresentation {
        return CashflowInsightsChartBuilder.makePresentation(
            entries: viewModel.state.convertedTransactions,
            dateRange: cashflowInsightsSelectedDateRange,
            granularity: cashflowInsightsGranularity,
            calendar: .current,
            locale: .autoupdatingCurrent
        )
    }

    private var cashflowFullScreenPresentation: CashflowInsightsPresentation {
        CashflowInsightsChartBuilder.makePresentation(
            entries: viewModel.state.convertedTransactions,
            dateRange: cashflowInsightsSelectedDateRange,
            granularity: cashflowInsightsGranularity,
            calendar: .current,
            locale: .autoupdatingCurrent
        )
    }

    private var fullScreenVisiblePeriodsControl: some View {
        HStack(spacing: 10) {
            Text("Visible range")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(primarySecondaryText)

            Spacer()

            HStack(spacing: 6) {
                visibleRangeChip(4)
                visibleRangeChip(12)
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func cashflowInsightCard(
        model: CashflowInsightsCardModel,
        accent: Color,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 12, height: 12)

                Text(model.title)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(primarySecondaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primarySecondaryText.opacity(0.65))
            }

            Text(chartAmountText(model.amount))
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, 26)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())

            Spacer(minLength: 24)

            Text(model.comparisonText)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(primarySecondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(chartSignedAmountText(model.delta))
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(chartDeltaColor(for: model.deltaTone))
                .padding(.top, 10)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(financeInnerBackground(cornerRadius: 28))
        if let onTap {
            Button {
                onTap()
                fireLightImpact()
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func cashflowInsightsBars(
        presentation: CashflowInsightsPresentation,
        granularity: CashflowInsightsGranularity,
        chartHeight: CGFloat,
        maxBarHeight: CGFloat,
        minimumGroupWidth: CGFloat,
        barWidth: CGFloat,
        labelFontSize: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            let maxValue = max(
                presentation.bars.flatMap { [abs($0.expense), abs($0.income)] }.max() ?? 0,
                1
            )
            let groupWidth = CashflowInsightsChartStyle.compactGroupWidth(
                containerWidth: proxy.size.width,
                barCount: presentation.bars.count,
                minimumGroupWidth: minimumGroupWidth
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(presentation.bars) { bar in
                        cashflowInsightsBarGroup(
                            bar: bar,
                            granularity: granularity,
                            selectedPeriodStart: presentation.selectedPeriodStart,
                            maxValue: maxValue,
                            groupWidth: groupWidth,
                            maxBarHeight: maxBarHeight,
                            barWidth: barWidth,
                            labelFontSize: labelFontSize
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 2)
            }
        }
        .frame(height: chartHeight)
    }

    private var cashflowFullScreenChart: some View {
        let presentation = cashflowFullScreenPresentation
        let granularity = cashflowInsightsGranularity

        return GeometryReader { proxy in
            let metrics = CashflowInsightsChartStyle.fullScreenMetrics(
                containerWidth: proxy.size.width,
                barCount: presentation.bars.count,
                visiblePeriods: fullScreenChartVisiblePeriods
            )
            let maxValue = max(
                presentation.bars.flatMap { [abs($0.expense), abs($0.income)] }.max() ?? 0,
                1
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: metrics.spacing) {
                    ForEach(presentation.bars) { bar in
                        cashflowInsightsBarGroup(
                            bar: bar,
                            granularity: granularity,
                            selectedPeriodStart: presentation.selectedPeriodStart,
                            maxValue: maxValue,
                            groupWidth: metrics.groupWidth,
                            maxBarHeight: metrics.maxBarHeight,
                            barWidth: metrics.barWidth,
                            labelFontSize: metrics.labelFontSize
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
        .frame(height: 332)
    }

    private func cashflowInsightsBarGroup(
        bar: CashflowInsightsBar,
        granularity: CashflowInsightsGranularity,
        selectedPeriodStart: Date,
        maxValue: Double,
        groupWidth: CGFloat,
        maxBarHeight: CGFloat,
        barWidth: CGFloat,
        labelFontSize: CGFloat
    ) -> some View {
        let comparisonGranularity: Calendar.Component = {
            switch granularity {
            case .year:
                return .year
            case .month:
                return .month
            case .week:
                return .weekOfYear
            }
        }()
        let isSelected = Calendar.current.isDate(
            bar.periodStart,
            equalTo: selectedPeriodStart,
            toGranularity: comparisonGranularity
        )

        return VStack(spacing: 12) {
            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 8) {
                chartColumn(
                    value: bar.expense,
                    maxValue: maxValue,
                    maxBarHeight: maxBarHeight,
                    barWidth: barWidth,
                    isSelected: isSelected,
                    trackTint: neonNegative,
                    glowColor: neonNegative,
                    fill: LinearGradient(
                        colors: [
                            Color(hex: "FF7A7A"),
                            Color(hex: "FF6666"),
                            Color(hex: "4A1414")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                chartColumn(
                    value: bar.income,
                    maxValue: maxValue,
                    maxBarHeight: maxBarHeight,
                    barWidth: barWidth,
                    isSelected: isSelected,
                    trackTint: neonPositive,
                    glowColor: neonPositive,
                    fill: LinearGradient(
                        colors: [
                            Color(hex: "7BFFD0"),
                            Color(hex: "30D6A8"),
                            Color(hex: "0B3A2A")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 8)

                Text(
                    CashflowInsightsChartStyle.barLabel(
                        for: bar.periodStart,
                        granularity: granularity
                    )
                )
                    .font(.system(size: labelFontSize, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary.opacity(bar.isPlaceholder ? 0.78 : 0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isSelected ? 0.14 : 0.0))
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            }
            .frame(width: groupWidth)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.13 : (bar.isPlaceholder ? 0.07 : 0.03)),
                                Color.white.opacity(isSelected ? 0.06 : (bar.isPlaceholder ? 0.03 : 0.0))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isSelected ? 0.08 : 0.03),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(68, maxBarHeight * 0.3))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.12 : 0.04), lineWidth: 1)
                    )
            )
            .shadow(
                color: Color.white.opacity(isSelected ? 0.06 : 0.0),
                radius: isSelected ? 18 : 0,
                x: 0,
                y: 10
            )
            .offset(y: isSelected ? -2 : 0)
    }

    private func chartColumn(
        value: Double,
        maxValue: Double,
        maxBarHeight: CGFloat,
        barWidth: CGFloat,
        isSelected: Bool,
        trackTint: Color,
        glowColor: Color,
        fill: LinearGradient
    ) -> some View {
        ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            trackTint.opacity(isSelected ? 0.18 : 0.10),
                            Color.white.opacity(isSelected ? 0.04 : 0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.10 : 0.04), lineWidth: 0.8)
                )

            chartBar(
                value: value,
                maxValue: maxValue,
                maxBarHeight: maxBarHeight,
                barWidth: barWidth,
                fill: fill,
                glowColor: glowColor,
                isSelected: isSelected
            )
        }
        .frame(width: barWidth, height: maxBarHeight)
    }

    private func chartBar(
        value: Double,
        maxValue: Double,
        maxBarHeight: CGFloat,
        barWidth: CGFloat,
        fill: LinearGradient,
        glowColor: Color,
        isSelected: Bool
    ) -> some View {
        let visibleHeight = CashflowInsightsChartStyle.visibleBarHeight(
            value: value,
            maxValue: maxValue,
            maxBarHeight: maxBarHeight,
            isSelected: isSelected
        )
        let cornerRadius = min(16, barWidth / 2)

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                .clear,
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.28 : 0.20))
                    .frame(width: barWidth * 0.72, height: 6)
                    .blur(radius: 3)
                    .padding(.top, 6)
            }
            .frame(width: barWidth, height: visibleHeight)
            .shadow(
                color: glowColor.opacity(isSelected ? 0.30 : 0.18),
                radius: isSelected ? 16 : 9,
                x: 0,
                y: 6
            )
            .opacity(visibleHeight > 0 ? 1 : 0)
    }

    private func visibleRangeChip(_ value: Int) -> some View {
        let isSelected = fullScreenChartVisiblePeriods == value

        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                fullScreenChartVisiblePeriods = value
            }
            fireLightImpact()
        } label: {
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isSelected ? 0.16 : 0.0))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(isSelected ? 0.10 : 0.0), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func chartAmountText(_ amount: Double) -> String {
        let currency = displayCurrencyLabel()
        if currency.count <= 1 {
            return "\(cashflowAmountText(amount))\(currency)"
        }
        return "\(cashflowAmountText(amount)) \(currency)"
    }

    private func chartSignedAmountText(_ amount: Double) -> String {
        let currency = displayCurrencyLabel()
        if currency.count <= 1 {
            return "\(cashflowSignedAmountText(amount))\(currency)"
        }
        return "\(cashflowSignedAmountText(amount)) \(currency)"
    }

    private func chartDeltaColor(for tone: CashflowValueTone) -> Color {
        switch tone {
        case .positive:
            return neonPositive
        case .negative:
            return neonNegative
        case .neutral:
            return primarySecondaryText
        }
    }

    private var hasIncomeOrExpenseTransactions: Bool {
        viewModel.state.transactions.contains { transaction in
            transaction.transactionType == .income || transaction.transactionType == .expense
        }
    }

    private var emptyTransactionsOnboardingState: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()

                if !isEmptyIntroHidden {
                    Button {
                        isEmptyIntroHidden = true
                        CashflowEmptyStateIntroPrefs().setHidden(true)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primarySecondaryText)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "cashflow.main.empty_intro.dismiss"))
                }
            }

            Image(systemName: "chart.bar.doc.horizontal.fill")
                .font(.system(size: 40))
                .foregroundStyle(primarySecondaryText)

            Text("cashflow.main.empty_intro.title")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            if !isEmptyIntroHidden {
                Text("cashflow.main.empty_intro.description")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(primarySecondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                viewModel.handle(.addTransaction(.expense))
                fireLightImpact()
            } label: {
                Text("cashflow.main.empty_intro.add_expense")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: AppColors.expenseGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)

            if !isEmptyIntroHidden {
                Button {
                    MiniAppNavigation.navigate(to: .finances, from: currentRoute, router: router)
                    fireLightImpact()
                } label: {
                    Text("cashflow.main.empty_intro.open_finances")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(financeCardBackground(cornerRadius: panelCornerRadius))
    }

    private func fireLightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.9)
    }

    private func hideEmptyIntroIfNeeded() {
        guard hasIncomeOrExpenseTransactions, !isEmptyIntroHidden else { return }
        isEmptyIntroHidden = true
        CashflowEmptyStateIntroPrefs().setHidden(true)
    }

    private var assetChangeInfoSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How is asset value change calculated?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(String(localized: "cashflow.asset_change.formula"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)

                        Text("Substitution:")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        Group {
                            Text(String(format: String(localized: "cashflow.asset_change.start_total_format"), formatMoney(viewModel.state.assetsAtPeriodStart)))
                            Text(String(format: String(localized: "cashflow.asset_change.end_total_format"), formatMoney(viewModel.state.assetsAtPeriodEnd)))
                            Text(String(format: String(localized: "cashflow.asset_change.income_format"), formatSignedMoney(viewModel.state.totalIncome)))
                            Text(String(format: String(localized: "cashflow.asset_change.expenses_format"), formatSignedMoney(-viewModel.state.contributedExpense)))
                            Text(String(format: String(localized: "cashflow.asset_change.change_format"), formatSignedMoney(viewModel.state.assetValueChange)))
                        }
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary)

                        Text("Balance check:")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        let checkValue = abs(
                            (viewModel.state.assetsAtPeriodEnd - viewModel.state.assetsAtPeriodStart) -
                            (viewModel.state.totalIncome + viewModel.state.assetValueChange - viewModel.state.contributedExpense)
                        )
                        Text(checkValue < 0.01 ? "Matches" : "Mismatch")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(checkValue < 0.01 ? Color.green : Color.red)

                        Text("Explanation: this is asset revaluation/movement for the period after explicit inflows (income) and recorded expenses are accounted for.")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAssetChangeInfoSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    private var customPeriodSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        let sameYear = Calendar.current.component(.year, from: draftStartDate) == Calendar.current.component(.year, from: draftEndDate)
                        let startFormat: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
                        let endFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
                        Text(
                            String(
                                format: String(localized: "cashflow.history.date_range_format"),
                                min(draftStartDate, draftEndDate).formatted(startFormat),
                                max(draftStartDate, draftEndDate).formatted(endFormat)
                            )
                        )
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Select start and end dates on the calendar")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 4)

                    CalendarRangeMonthView(startDate: $draftStartDate, endDate: $draftEndDate)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.handle(.hidePeriodSelector)
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                let gradient = LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.02, blue: 0.12),
                        Color(red: 0.02, green: 0.12, blue: 0.10)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 12) {
                    Button {
                        viewModel.handle(.resetToLastMonth)
                        viewModel.handle(.hidePeriodSelector)
                    } label: {
                        Text("Reset")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                            )
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        let start = min(draftStartDate, draftEndDate)
                        let end = max(draftStartDate, draftEndDate)
                        let clampedEnd = min(end, Calendar.current.startOfDay(for: Date()))
                        let clampedStart = min(start, clampedEnd)
                        viewModel.handle(.setCustomPeriod(start: clampedStart, end: clampedEnd))
                        viewModel.handle(.hidePeriodSelector)
                    } label: {
                        Text("Show")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(gradient)
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                LinearGradient(
                                                    colors: AppColors.cashflowGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Cashflow Action Button

private struct CashflowActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    let accessibilityLabel: String
    let title: String
    let icon: String
    let gradientColors: [Color]
    let style: Style
    let compactMetrics: Bool
    let action: () -> Void
    
    private let cornerRadius: CGFloat = 28
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.95))
                    Circle()
                        .stroke(gradientStroke.opacity(0.65), lineWidth: 1.1)
                    Image(systemName: icon)
                        .font(.system(size: compactMetrics ? 15 : 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
                .frame(width: compactMetrics ? 34 : 38, height: compactMetrics ? 34 : 38)

                Text(title)
                    .font(.system(size: compactMetrics ? 12 : 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(compactMetrics ? 0.78 : 0.9)
                    .allowsTightening(true)
                    .layoutPriority(1)
            }
            .padding(.horizontal, compactMetrics ? 8 : 10)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var buttonBackground: some View {
        let fillColor: Color = Color.black.opacity(style == .primary ? 0.24 : 0.20)
        let strokeOpacity: Double = style == .primary ? 0.95 : 0.72
        let strokeWidth: CGFloat = style == .primary ? 1.6 : 1.2
        let materialOpacity: Double = style == .primary ? 0.26 : 0.22
        let shadowOpacity: Double = style == .primary ? 0.10 : 0.08
        let shadowRadius: CGFloat = style == .primary ? 10 : 6

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillColor)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(gradientStroke.opacity(strokeOpacity), lineWidth: strokeWidth)
            }
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(materialOpacity))
            )
            .shadow(color: gradientAccent.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 0)
    }

    private var gradientAccent: Color {
        gradientColors.first ?? AppColors.brandPrimary
    }

    private var gradientStroke: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
