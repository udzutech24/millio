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

func cashflowExpandedHintText(visiblePeriods: Int, locale: Locale = AppLocalization.currentAppLocale) -> String {
    String(
        format: AppLocalization.string("cashflow.chart.hint_format", locale: locale),
        locale: locale,
        visiblePeriods
    )
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

enum CashflowExpandedChartLayoutPolicy {
    static let controlsOverlayBottomPadding: CGFloat = 10
    static let controlsOnlyOverlayHeight: CGFloat = 86
    static let controlsWithHintOverlayHeight: CGFloat = 150

    static func scrollContentBottomPadding(isHintHidden: Bool) -> CGFloat {
        BottomPinnedLayoutPolicy.scrollContentBottomPaddingForOverlay(
            overlayHeight: isHintHidden ? controlsOnlyOverlayHeight : controlsWithHintOverlayHeight,
            overlayBottomPadding: controlsOverlayBottomPadding
        )
    }
}

struct CashflowView: View {
    var isTabMode: Bool = false
    /// Внешний VM от RootTabView — используется, чтобы FAB-шиты и вкладка
    /// работали с одним экземпляром. Если nil, View создаёт собственный.
    var sharedViewModel: CashflowViewModel? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var localViewModel: CashflowViewModel?

    private var activeViewModel: CashflowViewModel? { sharedViewModel ?? localViewModel }

    var body: some View {
        Group {
            if let vm = activeViewModel {
                CashflowContentView(
                    viewModel: vm,
                    isTabMode: isTabMode
                )
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if sharedViewModel == nil, localViewModel == nil {
                localViewModel = CashflowViewModel(modelContext: modelContext)
            }
            activeViewModel?.handle(.syncDisplayCurrencyWithPrimary(appState.primaryCurrencyCode))
            // Перезагружаем данные при каждом появлении экрана
            activeViewModel?.handle(.loadCards)
            activeViewModel?.handle(.loadTransactions)
            consumePendingQuickActions()
        }
        // Когда RootTabView передаёт свой VM — освобождаем локальный
        .onChange(of: sharedViewModel != nil) { _, isShared in
            if isShared { localViewModel = nil }
        }
        .onChange(of: appState.primaryCurrencyCode) { oldValue, newValue in
            activeViewModel?.handle(.syncPrimaryCurrencyChange(old: oldValue, new: newValue))
        }
        .onChange(of: appState.pendingOpenCashflowExpense) { _, newValue in
            guard newValue else { return }
            consumePendingQuickActions()
        }
        .onChange(of: appState.pendingOpenCashflowIncome) { _, newValue in
            guard newValue else { return }
            consumePendingQuickActions()
        }
        .onChange(of: appState.pendingOpenCashflowHistory) { _, newValue in
            guard newValue else { return }
            consumePendingQuickActions()
        }
        .onDisappear {
            activeViewModel?.handle(.syncDisplayCurrencyWithPrimary(appState.primaryCurrencyCode))
        }
    }

    private func consumePendingQuickActions() {
        guard let vm = activeViewModel else { return }

        if appState.pendingOpenCashflowExpense {
            appState.pendingOpenCashflowExpense = false
            vm.handle(.addTransaction(.expense))
        }

        if appState.pendingOpenCashflowIncome {
            appState.pendingOpenCashflowIncome = false
            vm.handle(.addTransaction(.income))
        }

        if appState.pendingOpenCashflowHistory {
            appState.pendingOpenCashflowHistory = false
            vm.handle(.showTransactionsHistory)
        }
    }
}

// MARK: - Cashflow Content View

private struct CashflowContentView: View {
    @Query(sort: \CashflowMonthClosureEvent.occurredAt, order: .reverse) private var closureEvents: [CashflowMonthClosureEvent]
    @ObservedObject var viewModel: CashflowViewModel
    var isTabMode: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.diContainer) private var diContainer
    @State private var draftStartDate: Date = CashflowViewModel.defaultPeriodRange(referenceDate: Date()).start
    @State private var draftEndDate: Date = CashflowViewModel.defaultPeriodRange(referenceDate: Date()).end
    @State private var showAssetChangeInfoSheet: Bool = false
    @State private var showBudgetSetupSheet: Bool = false
    @State private var budgetSetupKind: CashflowCategoryKind = .expense
    @State private var budgetSetupExistingAmount: Double? = nil
    @State private var budgetSetupExistingCategoryLimits: [String: Double] = [:]
    @State private var budgetSetupCategorySnapshots: [BudgetCategoryProgressSnapshot] = []
    @State private var showUpcomingPlanner: Bool = false
    @State private var upcomingPlannerKind: CashflowCategoryKind = .expense
    @State private var showIncomeBreakdown: Bool = false
    @State private var showExpenseBreakdown: Bool = false
    @State private var showExpandedChart: Bool = false
    @State private var showExpandedPeriodSelector: Bool = false
    @State private var fullScreenChartVisiblePeriods: Int = 4
    @State private var showQuickNavigationPopover: Bool = false
    @State private var chartReferenceAnchorDate: Date = Date()
    @State private var selectedChartPeriodStart: Date? = nil
    @State private var isExpandedHintHidden: Bool = HintsVisibilityPrefs(key: "cashflow.expanded_chart.bottom_hint").isHidden
    @State private var historyInitialFilter: CashflowHistoryTypeFilter = .all
    @State private var historyInitialStartDate: Date? = nil
    @State private var historyInitialEndDate: Date? = nil
    @State private var showMonthWorkspace = false
    @State private var showImportHub = false
    @State private var showScopedMonthPicker = false
    @State private var scopedMonth = CashflowMonthSelectionPolicy.canonicalMonth(.now)
    @State private var pendingMonthAction: CashflowMonthScopedAction?
    @State private var showClosedMonthExplanation = false
    @State private var presentedEditorMonth: Date?
    private let currentRoute: AppRoute = .cashflow

    private let neonCyan = Color(hex: "35B8DC")
    private let neonViolet = Color(hex: "7460E0")
    private let neonPositive = Color(hex: "4ECFA0")
    private let neonNegative = Color(hex: "D45050")
    /// Полоса сверху/снизу графика "вариант A", зарезервированная под подпись суммы выбранного
    /// месяца — бар туда не дорастает, иначе подпись сливается с баром того же цвета.
    private static let variantALabelMargin: CGFloat = 20
    private let primarySecondaryText = Color.white.opacity(0.78)
    private let panelFill = Color.white.opacity(0.035)
    private let innerGlassFill = Color.white.opacity(0.018)
    private let innerSeparator = Color.white.opacity(0.16)
    private let panelCornerRadius: CGFloat = 22
    private let rowCornerRadius: CGFloat = 16
    private let compactChartHistoricalPeriods = 6

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    cashflowChartSection

                    monthContextActions

                    operationsEntryPoint

                    // Сводка активов за период
                    assetBreakdownSection

                    // Бюджет-карточка (Фаза 1 редизайна add-flow) — только для конкретного месяца,
                    // бюджет считается помесячно и не применим к кварталу/году/произвольному периоду.
                    if viewModel.state.chartPeriod == .specificMonth {
                        budgetHeroSection
                    }

                    // Секция «Предстоящие» (Фаза 0, Шаг 6) — не привязана к выбранному периоду
                    // графика (речь о ближайшем будущем от «сейчас»), поэтому видна всегда, когда
                    // есть что показать. Пустой список — карточка не рендерится вовсе (AC3).
                    if !upcomingItems.isEmpty {
                        upcomingSection
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, isTabMode ? 6 : 18)
                .padding(.bottom, 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveBackSwipe()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(isTabMode ? .hidden : .visible, for: .navigationBar)
        .toolbar { topToolbar }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionEditor },
            set: {
                if !$0 {
                    viewModel.handle(.hideTransactionEditor)
                    presentedEditorMonth = nil
                }
            }
        )) {
            if let editingTransaction = viewModel.state.editingTransaction {
                CashflowTransactionEditorView(
                    viewModel: viewModel,
                    transaction: editingTransaction
                )
            } else if let creatingType = viewModel.state.creatingTransactionType {
                switch creatingType {
                case .income:
                    CashflowUnifiedEntryContainer(
                        viewModel: viewModel,
                        initialTab: .incomes,
                        initialMonth: presentedEditorMonth
                    )
                case .expense:
                    CashflowUnifiedEntryContainer(
                        viewModel: viewModel,
                        initialTab: .expenses,
                        initialMonth: presentedEditorMonth
                    )
                case .transfer:
                    CashflowUnifiedEntryContainer(
                        viewModel: viewModel,
                        initialTab: .transfer,
                        initialMonth: presentedEditorMonth
                    )
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
        .sheet(isPresented: $showMonthWorkspace) {
            NavigationStack {
                CashflowMonthWorkspaceView(
                    viewModel: viewModel,
                    month: scopedMonth,
                    statementClient: statementImportClient
                )
            }
        }
        .sheet(isPresented: $showImportHub) {
            CashflowImportHubView(
                viewModel: viewModel,
                month: scopedMonth,
                statementClient: statementImportClient
            )
        }
        .sheet(isPresented: $showScopedMonthPicker) {
            CashflowMonthPickerSheet(selection: $scopedMonth) { month in
                guard let action = pendingMonthAction else { return }
                pendingMonthAction = nil
                performMonthAction(action, month: month)
            }
        }
        .alert(
            CashflowMonthWorkspaceLocalization.closed,
            isPresented: $showClosedMonthExplanation
        ) {
            Button(CashflowMonthWorkspaceLocalization.done, role: .cancel) {}
        } message: {
            Text(CashflowMonthWorkspaceLocalization.closedExplanation)
        }
        .sheet(isPresented: $showAssetChangeInfoSheet) {
            assetChangeInfoSheet
        }
        .sheet(isPresented: $showBudgetSetupSheet) {
            budgetSetupSheetContent
        }
        .sheet(isPresented: $showUpcomingPlanner) {
            upcomingPlannerSheet
        }
        .fullScreenCover(isPresented: $showExpandedChart) {
            cashflowExpandedChartSheet
        }
        .onAppear {
            if viewModel.state.chartPeriod == .custom {
                chartReferenceAnchorDate = viewModel.state.customEndDate
            } else {
                chartReferenceAnchorDate = Date()
            }
        }
        .onChange(of: viewModel.state.chartPeriod) { _, newPeriod in
            if newPeriod == .custom {
                chartReferenceAnchorDate = viewModel.state.customEndDate
                return
            }
            if Calendar.current.isDate(viewModel.state.selectedMonth, equalTo: Date(), toGranularity: .month) {
                chartReferenceAnchorDate = Date()
            }
        }
        .onChange(of: viewModel.state.customEndDate) { _, newDate in
            if viewModel.state.chartPeriod == .custom {
                chartReferenceAnchorDate = newDate
            }
        }
    }

    // MARK: - Month context actions

    private var monthContextActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                monthActionButton(
                    title: CashflowMonthWorkspaceLocalization.add,
                    systemImage: "plus",
                    action: .addOperation,
                    prominent: true
                )
                monthActionButton(
                    title: CashflowMonthWorkspaceLocalization.importData,
                    systemImage: "square.and.arrow.down",
                    action: .importData,
                    prominent: false
                )
            }

            if isSelectedSpecificMonthClosed {
                Label(CashflowMonthWorkspaceLocalization.closedExplanation, systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(primarySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(financeCardBackground(cornerRadius: panelCornerRadius))
    }

    private func monthActionButton(
        title: String,
        systemImage: String,
        action: CashflowMonthScopedAction,
        prominent: Bool
    ) -> some View {
        Button { requestMonthAction(action) } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? neonCyan : primarySecondaryText)
        .disabled(isSelectedSpecificMonthClosed)
        .accessibilityHint(
            isSelectedSpecificMonthClosed
                ? CashflowMonthWorkspaceLocalization.closedExplanation
                : monthActionAccessibilityHint
        )
    }

    private var operationsEntryPoint: some View {
        Button { requestMonthAction(.operations) } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(CashflowMonthWorkspaceLocalization.title)
                        .font(.headline)
                    Text(CashflowMonthWorkspaceLocalization.history)
                        .font(.subheadline)
                        .foregroundStyle(primarySecondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(primarySecondaryText)
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(financeCardBackground(cornerRadius: panelCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityHint(CashflowMonthWorkspaceLocalization.chooseMonth)
    }

    private var monthActionAccessibilityHint: String {
        viewModel.state.chartPeriod == .specificMonth
            ? monthTitle(for: viewModel.state.selectedMonth)
            : CashflowMonthWorkspaceLocalization.chooseMonth
    }

    private var isSelectedSpecificMonthClosed: Bool {
        guard viewModel.state.chartPeriod == .specificMonth else { return false }
        return isClosed(month: viewModel.state.selectedMonth)
    }

    private func requestMonthAction(_ action: CashflowMonthScopedAction) {
        switch CashflowMonthScopePolicy.resolve(
            chartPeriod: viewModel.state.chartPeriod,
            selectedMonth: viewModel.state.selectedMonth
        ) {
        case .ready(let month):
            performMonthAction(action, month: month)
        case .requiresExplicitMonth:
            scopedMonth = CashflowMonthSelectionPolicy.canonicalMonth(.now)
            pendingMonthAction = action
            showScopedMonthPicker = true
        }
    }

    private func performMonthAction(_ action: CashflowMonthScopedAction, month: Date) {
        let canonical = CashflowMonthSelectionPolicy.canonicalMonth(month)
        scopedMonth = canonical

        if action != .operations, isClosed(month: canonical) {
            showClosedMonthExplanation = true
            return
        }

        switch action {
        case .addOperation:
            viewModel.handle(.setSelectedMonth(canonical))
            presentedEditorMonth = canonical
            viewModel.handle(.addTransaction(.expense))
        case .importData:
            showImportHub = true
        case .operations:
            showMonthWorkspace = true
        }
        fireLightImpact()
    }

    private func isClosed(month: Date) -> Bool {
        let canonical = CashflowMonthSelectionPolicy.canonicalMonth(month)
        return closureEvents.first {
            CashflowMonthSelectionPolicy.canonicalMonth($0.monthStart) == canonical
        }?.kind == .close
    }

    private func monthTitle(for month: Date) -> String {
        month.formatted(.dateTime.month(.wide).year().locale(AppLocalization.currentAppLocale))
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        GeometryReader { proxy in
            let useCompactMetrics = CashflowActionButtonsLayout.shouldUseCompactMetrics(
                containerWidth: proxy.size.width
            )
            let incomeTitle = L("main.quick_action.income")
            let expenseTitle = L("main.quick_action.expense")
            let transferTitle = L("cashflow.quick_action.transfer")

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
                title: L("cashflow.stats.assets_start"),
                value: formatMoney(viewModel.state.assetsAtPeriodStart),
                valueColor: AppColors.textPrimary
            )
            rowDivider

            expandableStatRow(
                title: String(
                    localized: "cashflow.stats.income",
                    defaultValue: "Доходы",
                    comment: "Cashflow stats income row title"
                ),
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
                    valueColor: { positiveColor(for: $0) },
                    onShowAll: { openHistory(filter: .income) }
                )
            }
            rowDivider

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text(L("cashflow.stats.asset_value_change"))
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
                title: L("cashflow.stats.expenses"),
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
                    valueColor: { negativeColor(for: -$0) },
                    onShowAll: { openHistory(filter: .expense) }
                )
            }
            rowDivider

            VStack(spacing: 8) {
                statRow(
                    title: L("cashflow.stats.assets_end"),
                    value: formatMoney(viewModel.state.assetsAtPeriodEnd),
                    valueColor: AppColors.textPrimary
                )

                Divider()
                    .overlay(innerSeparator)

                HStack {
                    Text(L("cashflow.stats.result"))
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

    // MARK: - Budget Hero Section (Фаза 1 редизайна add-flow)

    private var budgetHeroSection: some View {
        BudgetHeroCard(
            expenseSnapshot: viewModel.state.dashboardExpenseBudgetSnapshot,
            incomeSnapshot: viewModel.state.dashboardIncomeBudgetSnapshot,
            currencyCode: cashflowCurrencyCodeLabel(viewModel.state.displayCurrency),
            onTap: openBudgetSetup(for:)
        )
    }

    private func openBudgetSetup(for kind: CashflowCategoryKind) {
        let month = viewModel.state.selectedMonth
        let currency = viewModel.state.displayCurrency
        Task {
            let summary = await viewModel.monthlyBudgetSummary(for: kind, month: month, in: currency)
            budgetSetupKind = kind
            budgetSetupExistingAmount = summary.plan?.totalLimitAmount
            budgetSetupExistingCategoryLimits = summary.categoryLimits
            budgetSetupCategorySnapshots = summary.snapshot?.categorySnapshots ?? []
            showBudgetSetupSheet = true
        }
    }

    // MARK: - Upcoming Section (Фаза 0, Шаг 6 редизайна add-flow)

    /// Источник — `CashflowViewModel.upcomingSectionItems()`, который переиспользует
    /// `scheduledPlannerEntries` (тот же движок, что и полный «Планировщик») и
    /// `AccountsCoreDepositCashflowBridge.upcomingInterestEvents` — без пересчёта.
    private var upcomingItems: [CashflowUpcomingItem] {
        viewModel.upcomingSectionItems()
    }

    private var upcomingSection: some View {
        CashflowUpcomingCard(items: upcomingItems, onShowAll: openUpcomingPlanner)
    }

    /// Полный «Планировщик» (`CashflowScheduledTransactionsView`) построен вокруг одного `kind`
    /// (доход ИЛИ расход) — управление им не меняется (§5 плана). Ссылка «Все» открывает его для
    /// kind ближайшей (первой в списке) предстоящей операции — так пользователь попадает туда,
    /// где реально есть данные, вместо произвольного дефолта.
    private func openUpcomingPlanner() {
        upcomingPlannerKind = upcomingItems.first?.kind ?? .expense
        showUpcomingPlanner = true
    }

    private var upcomingPlannerSheet: some View {
        NavigationStack {
            CashflowScheduledTransactionsView(
                viewModel: viewModel,
                kind: upcomingPlannerKind,
                mode: .planner
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showUpcomingPlanner = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("cashflow.common.close"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var budgetSetupPeriodTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: viewModel.state.selectedMonth).localizedCapitalized
    }

    private var budgetSetupSheetContent: some View {
        let kind = budgetSetupKind
        let repeatSuggestion = viewModel.previousMonthlyBudgetSuggestion(
            for: viewModel.state.selectedMonth,
            categoryKind: kind
        )
        return BudgetSetupSheet(
            categoryKind: kind,
            periodTitle: budgetSetupPeriodTitle,
            currencyCode: cashflowCurrencyCodeLabel(viewModel.state.displayCurrency),
            existingAmount: budgetSetupExistingAmount,
            categoryOptions: viewModel.categoryOptions(for: kind),
            existingCategoryLimits: budgetSetupExistingCategoryLimits,
            categorySnapshots: budgetSetupCategorySnapshots,
            repeatSuggestion: repeatSuggestion,
            isAutoRepeatEnabled: viewModel.isMonthlyBudgetAutoRepeatEnabled,
            onSave: { amount, limits in
                viewModel.saveMonthlyBudgetConfiguration(
                    categoryKind: kind,
                    month: viewModel.state.selectedMonth,
                    totalAmount: amount,
                    categoryLimits: limits,
                    currency: viewModel.state.displayCurrency
                )
                viewModel.updateChartData()
            },
            onAutoRepeatChanged: { isEnabled in
                viewModel.isMonthlyBudgetAutoRepeatEnabled = isEnabled
            }
        )
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
                .accessibilityLabel(
                    Text(
                        isExpanded.wrappedValue
                            ? "cashflow.accessibility.hide_details"
                            : "cashflow.accessibility.show_details"
                    )
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    /// Фаза 4 редизайна add-flow (§2.4): развёрнутый блок Доходы/Расходы показывает
    /// не весь список категорий, а топ-N + ссылку в полную Историю — сортировка по
    /// убыванию суммы уже сделана на сервисе (`CashflowAnalyticsService`). Cap-формула
    /// вынесена в `CashflowBreakdownCapPolicy` (юнит-тестируется без View-харнеса).
    private func breakdownList(
        entries: [CashflowCategoryBreakdownEntry],
        showNoCardsHint: Bool,
        signedAmount: @escaping (Double) -> Double,
        valueColor: @escaping (Double) -> Color,
        onShowAll: @escaping () -> Void
    ) -> some View {
        let visibleEntries = CashflowBreakdownCapPolicy.visibleEntries(from: entries)
        return VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                if showNoCardsHint {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("cashflow.breakdown.empty.no_cards.title"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primarySecondaryText)

                        Text(L("cashflow.breakdown.empty.no_cards.subtitle"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(primarySecondaryText)

                        Button {
                            appState.pendingOpenFinanceAddCard = true
                            MiniAppNavigation.navigate(to: .finances, from: currentRoute, router: router)
                            fireLightImpact()
                        } label: {
                            Text(L("cashflow.breakdown.empty.no_cards.cta"))
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
                    Text(L("cashflow.main.empty.no_transactions"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(primarySecondaryText)
                }
            } else {
                ForEach(visibleEntries) { entry in
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

                if CashflowBreakdownCapPolicy.showsExpandLink(totalCount: entries.count) {
                    breakdownShowAllRow(action: onShowAll)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    /// Ссылка "Показать всё → История" под топ-3 категориями (§2.4). Не появляется,
    /// если весь список и так помещается в cap (R6: пустой список тоже не показывает).
    private func breakdownShowAllRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                Text(L("cashflow.breakdown.show_all", defaultValue: "Show all"))
                Image(systemName: "chevron.right")
                    .font(.millioCaption2)
            }
            .font(.millioCalloutSemibold)
            .foregroundStyle(AppColors.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Period Selection Section

    private var periodSelectionHeader: some View {
        let range = viewModel.currentDateRange()
        return HStack(spacing: 8) {
            Button {
                draftStartDate = viewModel.state.customStartDate
                draftEndDate = viewModel.state.customEndDate
                viewModel.handle(.showPeriodSelector)
                fireLightImpact()
            } label: {
                HStack(spacing: 5) {
                    Image("calendar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .opacity(0.7)
                    Text(String(format: L("cashflow.period.range_format"), formatPeriod(range.0), formatPeriod(range.1)))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(primarySecondaryText)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(periodControlBackground)
            }
            .buttonStyle(.plain)

            Spacer()

            if isTabMode {
                cashflowMenu
                    .background(periodControlBackground)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.state.customStartDate)
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        let itemSize: CGFloat = 28
        let iconSize: CGFloat = 18

        if !isTabMode {
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
                    .accessibilityLabel(Text(L("cashflow.accessibility.back")))

                    Button {
                        showQuickNavigationPopover.toggle()
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: iconSize - 2, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.90))
                            .frame(width: itemSize, height: itemSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L("cashflow.accessibility.quick_navigation")))
                    .popover(isPresented: $showQuickNavigationPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                        MiniAppQuickNavigationPopover(
                            destinations: MiniAppNavigation.destinations(excluding: currentRoute)
                        ) { destination in
                            showQuickNavigationPopover = false
                            MiniAppNavigation.navigate(to: destination.route, from: currentRoute, router: router)
                        }
                        .presentationCompactAdaptation(.popover)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
            }
        }

        if !isTabMode {
            ToolbarItem(placement: .topBarTrailing) {
                cashflowMenu
            }
        }

    }

    private var cashflowMenu: some View {
        Menu {
            ForEach(CashflowMenuPresentation.sections, id: \.kind) { section in
                Section {
                    ForEach(section.destinations) { destination in
                        Button {
                            handleMenuDestination(destination)
                        } label: {
                            Label(menuTitle(for: destination), systemImage: destination.systemImage)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary.opacity(0.90))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(L("common.more")))
    }

    private func handleMenuDestination(_ destination: CashflowMenuDestination) {
        fireLightImpact()
        viewModel.handle(.showCurrencySelector)
    }

    private var statementImportClient: any CashflowStatementImportClient {
        guard let diContainer else { return UnavailableCashflowStatementImportClient() }
        return diContainer.apiClientFactory.makeCashflowStatementImportClient(authService: diContainer.authService)
    }

    private func menuTitle(for destination: CashflowMenuDestination) -> String {
        "\(L("cashflow.accessibility.display_currency_selector")): \(toolbarCurrencyLabel())"
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

    private var currentCalendarMonthHistoryRange: ClosedRange<Date> {
        let range = CashflowViewModel.defaultPeriodRange(referenceDate: Date(), calendar: .current)
        return range.start...range.end
    }

    private func financeCardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(panelFill)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.7)
            )
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
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
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
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(financeCardBackground(cornerRadius: panelCornerRadius))
    }

    private var cashflowChartContent: some View {
        let presentation = cashflowInsightsPresentation
        let granularity = cashflowInsightsGranularity

        return VStack(spacing: 18) {
            HStack {
                Spacer()
                Button {
                    showExpandedChart = true
                    fireLightImpact()
                } label: {
                    Label(L("cashflow.chart.expand"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(primarySecondaryText)
                .accessibilityLabel(Text(L("cashflow.chart.expand")))
            }

            cashflowVariantAChart(
                presentation: presentation,
                granularity: granularity,
                totalHeight: CashflowInsightsControlsStyle.compactBarsHeight,
                barsAreaHeight: 120,
                minimumGroupWidth: 50,
                barWidth: 32,
                labelFontSize: 13,
                visibleWindowPeriods: compactChartVisiblePeriods,
                onBarTap: handleChartBarTap
            )
        }
    }

    private var cashflowExpandedChartSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        expandedChartHeroHeader

                        HStack(spacing: 12) {
                            cashflowInsightCard(
                                model: cashflowFullScreenPresentation.expenseCard,
                                accent: neonNegative,
                                showsComparisonAndDelta: false,
                                onTap: {
                                    openHistory(filter: .expense)
                                }
                            )
                            cashflowInsightCard(
                                model: cashflowFullScreenPresentation.incomeCard,
                                accent: neonPositive,
                                showsComparisonAndDelta: false,
                                onTap: {
                                    openHistory(filter: .income)
                                }
                            )
                        }

                        cashflowFullScreenChart
                    }
                    .padding(16)
                    .padding(
                        .bottom,
                        CashflowExpandedChartLayoutPolicy.scrollContentBottomPadding(
                            isHintHidden: isExpandedHintHidden
                        )
                    )
                }
                .safeAreaInset(edge: .bottom, alignment: .center, spacing: 0) {
                    VStack(spacing: 10) {
                        if !isExpandedHintHidden {
                            expandedChartBottomHint
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
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
                    .padding(.bottom, CashflowExpandedChartLayoutPolicy.controlsOverlayBottomPadding)
                }
            }
            .navigationTitle(L("cashflow.chart.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        let range = viewModel.currentDateRange()
                        draftStartDate = range.0
                        draftEndDate = range.1
                        showExpandedPeriodSelector = true
                        fireLightImpact()
                    } label: {
                        Image("calendar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .frame(width: 40, height: 40, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L("cashflow.accessibility.select_period")))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarGlassIconButton(
                        systemName: "checkmark",
                        accessibilityLabel: L("cashflow.common.done"),
                        isHighlighted: true
                    ) {
                        showExpandedChart = false
                    }
                }
            }
            .sheet(isPresented: $showExpandedPeriodSelector) {
                CashflowCustomPeriodSheetView(
                    viewModel: viewModel,
                    draftStartDate: $draftStartDate,
                    draftEndDate: $draftEndDate
                )
            }
        }
    }

    private var expandedChartHeroHeader: some View {
        let range = viewModel.currentDateRange()
        let presentation = cashflowFullScreenPresentation
        let net = presentation.incomeCard.amount - presentation.expenseCard.amount

        let netColor = positiveColor(for: net)
        return VStack(spacing: 4) {
            Text(
                String(
                    format: L("cashflow.period.range_format"),
                    formatPeriod(range.0),
                    formatPeriod(range.1)
                )
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(primarySecondaryText.opacity(0.70))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.opacity)

            Text(chartSignedAmountText(net))
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(netColor)
                .lineLimit(1)
                .minimumScaleFactor(0.60)
                .contentTransition(.numericText())
                .padding(.top, 2)

            Text(L("cashflow.stats.result"))
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(netColor.opacity(0.65))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(netColor.opacity(0.10))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(netColor.opacity(0.30), lineWidth: 0.7)
                        )
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var cashflowChartEmptyState: some View {
        VStack(spacing: 14) {
            Image("loans")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .padding(.top, 2)

            Text(L("cashflow.chart.empty.banner.title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(L("cashflow.main.empty_intro.description"))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                viewModel.handle(.addTransaction(.expense))
                fireLightImpact()
            } label: {
                Text(L("cashflow.chart.empty.banner.add_action"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Button {
                MiniAppNavigation.navigate(to: .finances, from: currentRoute, router: router)
                fireLightImpact()
            } label: {
                Text(L("cashflow.chart.empty.banner.open_finances"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 330)
        .background(
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "041B32").opacity(0.95), Color.black.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [neonCyan.opacity(0.35), neonViolet.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
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
        !viewModel.state.convertedTransactions.isEmpty
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
        return CashflowInsightsChartBuilder.makeFullScreenPresentation(
            entries: viewModel.state.convertedTransactions,
            granularity: cashflowInsightsGranularity,
            selectedPeriodStart: selectedChartPeriodStart,
            referenceDate: compactChartReferenceDate,
            maxVisiblePeriods: compactChartMaxPeriods,
            monthLabelStyle: .abbreviatedWithYear,
            calendar: .current,
            locale: AppLocalization.currentAppLocale
        )
    }

    private var cashflowFullScreenPresentation: CashflowInsightsPresentation {
        CashflowInsightsChartBuilder.makeFullScreenPresentation(
            entries: viewModel.state.convertedTransactions,
            granularity: cashflowInsightsGranularity,
            selectedPeriodStart: selectedChartPeriodStart,
            referenceDate: fullScreenChartReferenceDate,
            maxVisiblePeriods: fullScreenChartVisiblePeriods,
            monthLabelStyle: fullScreenChartVisiblePeriods >= 12 ? .monthNumber : .abbreviatedWithYear,
            calendar: .current,
            locale: AppLocalization.currentAppLocale
        )
    }

    private var fullScreenVisiblePeriodsControl: some View {
        HStack(spacing: 10) {
            Text(L("cashflow.chart.visible_range"))
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

    private var compactChartVisiblePeriods: Int {
        viewModel.state.chartPeriod == .custom ? 4 : 3
    }

    private var compactChartMaxPeriods: Int {
        viewModel.state.chartPeriod == .custom ? 4 : compactChartHistoricalPeriods
    }

    private var compactChartReferenceDate: Date {
        viewModel.state.chartPeriod == .custom ? cashflowInsightsSelectedDateRange.upperBound : chartReferenceAnchorDate
    }

    private var fullScreenChartReferenceDate: Date {
        viewModel.state.chartPeriod == .custom ? cashflowInsightsSelectedDateRange.upperBound : chartReferenceAnchorDate
    }

    @ViewBuilder
    private func cashflowInsightCard(
        model: CashflowInsightsCardModel,
        accent: Color,
        showsComparisonAndDelta: Bool = true,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: accent.opacity(0.3), radius: 3, x: 0, y: 0)

                Text(model.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primarySecondaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(primarySecondaryText.opacity(0.50))
            }

            Text(chartAmountText(model.amount))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, 14)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .contentTransition(.numericText())

            if showsComparisonAndDelta {
                Spacer(minLength: 14)

                Text(model.comparisonText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(primarySecondaryText.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(chartSignedAmountText(model.delta))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(chartDeltaColor(for: model.deltaTone))
                    .padding(.top, 6)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: showsComparisonAndDelta ? 200 : 130, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.18), .clear],
                                startPoint: .top, endPoint: .center
                            )
                        )
                        .frame(height: 60)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(accent.opacity(0.15), lineWidth: 1)
                )
        )
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

    private var cashflowFullScreenChart: some View {
        let presentation = cashflowFullScreenPresentation
        let granularity = cashflowInsightsGranularity

        return GeometryReader { proxy in
            let metrics = CashflowInsightsChartStyle.fullScreenMetrics(
                containerWidth: proxy.size.width,
                barCount: presentation.bars.count,
                visiblePeriods: fullScreenChartVisiblePeriods
            )

            cashflowVariantAChart(
                presentation: presentation,
                granularity: granularity,
                totalHeight: 332,
                barsAreaHeight: metrics.maxBarHeight,
                groupWidth: metrics.groupWidth,
                spacing: metrics.spacing,
                barWidth: metrics.barWidth,
                labelFontSize: metrics.labelFontSize,
                bottomPadding: AppSpacing.ml,
                onBarTap: handleChartBarTap
            )
        }
        .frame(height: 332)
    }

    /// Вариант A редизайна графика Cashflow (§7.6 плана): единое полотно с общей нулевой осью
    /// вместо прежних плиток-«таблеток» на каждый месяц. Высота баров строго пропорциональна
    /// сумме на единой шкале (см. `CashflowChartVariantALayout`), поверх — net-линия с точками.
    private func cashflowVariantAChart(
        presentation: CashflowInsightsPresentation,
        granularity: CashflowInsightsGranularity,
        totalHeight: CGFloat,
        barsAreaHeight: CGFloat,
        minimumGroupWidth: CGFloat = 50,
        groupWidth: CGFloat? = nil,
        spacing: CGFloat = 8,
        barWidth: CGFloat,
        labelFontSize: CGFloat,
        visibleWindowPeriods: Int? = nil,
        bottomPadding: CGFloat = 0,
        onBarTap: @escaping (CashflowInsightsBar) -> Void
    ) -> some View {
        GeometryReader { proxy in
            let resolvedGroupWidth = groupWidth ?? CashflowInsightsChartStyle.compactGroupWidth(
                containerWidth: proxy.size.width,
                barCount: visibleWindowPeriods ?? presentation.bars.count,
                minimumGroupWidth: minimumGroupWidth
            )
            let halfHeight = barsAreaHeight / 2
            // Резервируем полосу под подпись суммы выбранного месяца сверху/снизу —
            // иначе при максимальном значении бар доходит до самого края полотна и подпись
            // того же оттенка зелёного/красного сливается с баром (нечитаемо, а не просто "тесно").
            let usableHalfHeight = max(halfHeight - Self.variantALabelMargin, 10)
            let layouts = CashflowChartVariantALayout.barLayouts(
                bars: presentation.bars,
                halfHeight: usableHalfHeight
            )
            let totalWidth = CGFloat(presentation.bars.count) * resolvedGroupWidth
                + CGFloat(max(presentation.bars.count - 1, 0)) * spacing

            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            drawVariantACanvas(
                                context: &context,
                                size: size,
                                bars: presentation.bars,
                                layouts: layouts,
                                selectedPeriodStart: presentation.selectedPeriodStart,
                                granularity: granularity,
                                groupWidth: resolvedGroupWidth,
                                spacing: spacing,
                                barWidth: barWidth,
                                halfHeight: halfHeight
                            )
                        }
                        .frame(width: totalWidth, height: barsAreaHeight)

                        HStack(alignment: .top, spacing: spacing) {
                            ForEach(Array(zip(presentation.bars, layouts)), id: \.0.id) { bar, _ in
                                variantAColumn(
                                    bar: bar,
                                    granularity: granularity,
                                    selectedPeriodStart: presentation.selectedPeriodStart,
                                    groupWidth: resolvedGroupWidth,
                                    barsAreaHeight: barsAreaHeight,
                                    labelFontSize: labelFontSize,
                                    onTap: { onBarTap(bar) }
                                )
                            }
                        }
                    }
                }
                .scrollClipDisabled()
                .onAppear {
                    scrollChartToLatestPeriod(reader: reader, bars: presentation.bars)
                }
                .onChange(of: presentation.bars.map(\.periodStart)) { _, _ in
                    scrollChartToLatestPeriod(reader: reader, bars: presentation.bars)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 2)
            .padding(.top, AppSpacing.s)
            .padding(.bottom, bottomPadding)
        }
        .frame(height: totalHeight)
    }

    /// Рисует общую фоновую сетку, зеркальные бары income/expense и net-линию с точками —
    /// одним полотном на весь видимый диапазон (а не отдельной плиткой на месяц).
    private func drawVariantACanvas(
        context: inout GraphicsContext,
        size: CGSize,
        bars: [CashflowInsightsBar],
        layouts: [CashflowChartVariantABar],
        selectedPeriodStart: Date,
        granularity: CashflowInsightsGranularity,
        groupWidth: CGFloat,
        spacing: CGFloat,
        barWidth: CGFloat,
        halfHeight: CGFloat
    ) {
        let zeroY = halfHeight

        var edgePath = Path()
        edgePath.move(to: CGPoint(x: 0, y: 1))
        edgePath.addLine(to: CGPoint(x: size.width, y: 1))
        edgePath.move(to: CGPoint(x: 0, y: size.height - 1))
        edgePath.addLine(to: CGPoint(x: size.width, y: size.height - 1))
        context.stroke(edgePath, with: .color(Color.white.opacity(0.06)), lineWidth: 1)

        var zeroPath = Path()
        zeroPath.move(to: CGPoint(x: 0, y: zeroY))
        zeroPath.addLine(to: CGPoint(x: size.width, y: zeroY))
        context.stroke(zeroPath, with: .color(Color.white.opacity(0.18)), lineWidth: 1)

        let comparisonGranularity: Calendar.Component = {
            switch granularity {
            case .year: return .year
            case .month: return .month
            case .week: return .weekOfYear
            }
        }()

        var netPoints: [(point: CGPoint, isPositive: Bool, isSelected: Bool)] = []

        for (index, pair) in zip(bars, layouts).enumerated() {
            let (bar, layout) = pair
            let isSelected = Calendar.current.isDate(
                bar.periodStart,
                equalTo: selectedPeriodStart,
                toGranularity: comparisonGranularity
            )
            let columnX = CGFloat(index) * (groupWidth + spacing)
            let centerX = columnX + groupWidth / 2
            let opacity = isSelected ? 1.0 : 0.42

            if isSelected {
                let highlightRect = CGRect(x: columnX, y: 0, width: groupWidth, height: size.height)
                context.stroke(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: highlightRect),
                    with: .color(Color.white.opacity(0.10)),
                    lineWidth: 1
                )
            }

            if layout.incomeHeight > 0 {
                let rect = CGRect(
                    x: centerX - barWidth / 2,
                    y: zeroY - layout.incomeHeight,
                    width: barWidth,
                    height: layout.incomeHeight
                )
                let path = RoundedRectangle(cornerRadius: min(10, barWidth / 2), style: .continuous).path(in: rect)
                context.fill(path, with: .color(neonPositive.opacity(opacity)))
            }
            if layout.expenseHeight > 0 {
                let rect = CGRect(
                    x: centerX - barWidth / 2,
                    y: zeroY,
                    width: barWidth,
                    height: layout.expenseHeight
                )
                let path = RoundedRectangle(cornerRadius: min(10, barWidth / 2), style: .continuous).path(in: rect)
                context.fill(path, with: .color(neonNegative.opacity(opacity)))
            }

            netPoints.append((CGPoint(x: centerX, y: zeroY - layout.netOffset), layout.isPositiveNet, isSelected))
        }

        if netPoints.count > 1 {
            var linePath = Path()
            linePath.move(to: netPoints[0].point)
            for entry in netPoints.dropFirst() {
                linePath.addLine(to: entry.point)
            }
            context.stroke(linePath, with: .color(Color.white.opacity(0.35)), lineWidth: 1.5)
        }

        for entry in netPoints {
            let radius: CGFloat = entry.isSelected ? 4.5 : 3
            let dotColor = entry.isPositive ? neonPositive : neonNegative
            let rect = CGRect(x: entry.point.x - radius, y: entry.point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(dotColor))
            if entry.isSelected {
                let glowRect = rect.insetBy(dx: -3, dy: -3)
                context.fill(Path(ellipseIn: glowRect), with: .color(dotColor.opacity(0.22)))
            }
        }
    }

    /// Тач-таргет и подписи одного месяца: сумма income/expense видна только у выбранного месяца,
    /// сами бары рисуются в `drawVariantACanvas` — колонка лишь задаёт геометрию и лейбл периода.
    @ViewBuilder
    private func variantAColumn(
        bar: CashflowInsightsBar,
        granularity: CashflowInsightsGranularity,
        selectedPeriodStart: Date,
        groupWidth: CGFloat,
        barsAreaHeight: CGFloat,
        labelFontSize: CGFloat,
        onTap: @escaping () -> Void
    ) -> some View {
        let comparisonGranularity: Calendar.Component = {
            switch granularity {
            case .year: return .year
            case .month: return .month
            case .week: return .weekOfYear
            }
        }()
        let isSelected = Calendar.current.isDate(
            bar.periodStart,
            equalTo: selectedPeriodStart,
            toGranularity: comparisonGranularity
        )

        VStack(spacing: 0) {
            Color.clear
                .frame(width: groupWidth, height: barsAreaHeight)
                .overlay(alignment: .top) {
                    if isSelected, bar.income > 0 {
                        Text("+\(compactChartAmount(bar.income))")
                            .font(.millioCaption2)
                            .foregroundStyle(neonPositive)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            // Явный width — иначе подпись может запросить больше места, чем своя
                            // колонка, и вылезти за пределы полотна графика (обрезается соседями).
                            .frame(width: groupWidth)
                            .padding(.top, AppSpacing.xs)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isSelected, bar.expense > 0 {
                        Text("−\(compactChartAmount(bar.expense))")
                            .font(.millioCaption2)
                            .foregroundStyle(neonNegative)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .frame(width: groupWidth)
                            .padding(.bottom, AppSpacing.xs)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                    fireLightImpact()
                }

            // Динамический размер шрифта лейбла периода зависит от ширины колонки —
            // считается в CashflowInsightsChartStyle/Style-метриках, фиксированный AppTypography-токен
            // тут не подходит (адаптив под разные экраны и число видимых месяцев).
            Text(bar.label)
                .font(.system(size: labelFontSize, weight: .medium))
                .foregroundStyle(AppColors.textPrimary.opacity(isSelected ? 0.95 : (bar.isPlaceholder ? 0.45 : 0.65)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, AppSpacing.s)
                .padding(.vertical, AppSpacing.xs)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isSelected ? 0.15 : 0.0))
                )
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.s)
        }
        .frame(width: groupWidth)
        .animation(AppAnimation.spring, value: isSelected)
    }

    /// Компактная сумма для подписи бара ("120 тыс.", "1,2 млн" — локализуется системным форматтером).
    private func compactChartAmount(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...1))
                .notation(.compactName)
        )
    }

    private func handleChartBarTap(_ bar: CashflowInsightsBar) {
        selectedChartPeriodStart = bar.periodStart
        if cashflowInsightsGranularity == .month {
            viewModel.handle(.setSelectedMonth(bar.periodStart))
        }
    }

    private func scrollChartToLatestPeriod(
        reader: ScrollViewProxy,
        bars: [CashflowInsightsBar]
    ) {
        guard let last = bars.last else { return }
        DispatchQueue.main.async {
            reader.scrollTo(last.periodStart, anchor: .trailing)
        }
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

    private var expandedChartBottomHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primarySecondaryText)
                .padding(.top, 1)

            Text(cashflowExpandedHintText(visiblePeriods: fullScreenChartVisiblePeriods))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(primarySecondaryText)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpandedHintHidden = true
                }
                HintsVisibilityPrefs(key: "cashflow.expanded_chart.bottom_hint").setHidden(true)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(primarySecondaryText)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("cashflow.accessibility.hide_hints"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
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

    private func fireLightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.9)
    }

    private var assetChangeInfoSheet: some View {
        let isBalanced = assetChangeBalanceDelta < 0.01

        return NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(L("cashflow.asset_change.info_title"))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(
                            String(
                                localized: "cashflow.asset_change.subtitle",
                                defaultValue: "Это разница между началом и концом периода после учёта всех зафиксированных доходов и расходов",
                                comment: "Cashflow asset change info subtitle"
                            )
                        )
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)

                        assetChangeInfoCard(
                            title: String(
                                localized: "cashflow.asset_change.formula_title",
                                defaultValue: "Формула",
                                comment: "Cashflow asset change formula section title"
                            )
                        ) {
                            Text(L("cashflow.asset_change.formula"))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                        }

                        assetChangeInfoCard(title: L("cashflow.asset_change.substitution")) {
                            VStack(spacing: 14) {
                                assetChangeValueRow(
                                    title: assetChangeLabel("cashflow.asset_change.start_total_format"),
                                    value: formatMoney(viewModel.state.assetsAtPeriodStart),
                                    valueColor: AppColors.textPrimary
                                )
                                assetChangeValueRow(
                                    title: assetChangeLabel("cashflow.asset_change.end_total_format"),
                                    value: formatMoney(viewModel.state.assetsAtPeriodEnd),
                                    valueColor: AppColors.textPrimary
                                )
                                assetChangeValueRow(
                                    title: assetChangeLabel("cashflow.asset_change.income_format"),
                                    value: formatSignedMoney(viewModel.state.totalIncome),
                                    valueColor: positiveColor(for: viewModel.state.totalIncome)
                                )
                                assetChangeValueRow(
                                    title: assetChangeLabel("cashflow.asset_change.expenses_format"),
                                    value: formatSignedMoney(-viewModel.state.contributedExpense),
                                    valueColor: negativeColor(for: -viewModel.state.contributedExpense)
                                )
                                assetChangeValueRow(
                                    title: assetChangeLabel("cashflow.asset_change.change_format"),
                                    value: formatSignedMoney(viewModel.state.assetValueChange),
                                    valueColor: positiveColor(for: viewModel.state.assetValueChange),
                                    emphasizesValue: true
                                )
                            }
                        }

                        assetChangeInfoCard(title: L("cashflow.asset_change.balance_check")) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: isBalanced ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(isBalanced ? Color.green : AppColors.warning)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(
                                        isBalanced
                                        ? L("cashflow.asset_change.matches")
                                        : L("cashflow.asset_change.mismatch")
                                    )
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)

                                    Text(
                                        isBalanced
                                        ? String(
                                            localized: "cashflow.asset_change.matches_detail",
                                            defaultValue: "Итог периода сходится с движением активов",
                                            comment: "Cashflow asset change balanced detail"
                                        )
                                        : String(
                                            localized: "cashflow.asset_change.mismatch_detail",
                                            defaultValue: "Есть расхождение между итогом периода и движением активов",
                                            comment: "Cashflow asset change mismatch detail"
                                        )
                                    )
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                                }

                                Spacer()

                                Text(formatMoney(assetChangeBalanceDelta))
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isBalanced ? AppColors.textSecondary : AppColors.warning)
                                    .monospacedDigit()
                            }
                        }

                        Text(L("cashflow.asset_change.explanation"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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

    private var assetChangeBalanceDelta: Double {
        abs(
            (viewModel.state.assetsAtPeriodEnd - viewModel.state.assetsAtPeriodStart) -
            (viewModel.state.totalIncome + viewModel.state.assetValueChange - viewModel.state.contributedExpense)
        )
    }

    private func assetChangeInfoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func assetChangeValueRow(
        title: String,
        value: String,
        valueColor: Color,
        emphasizesValue: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: emphasizesValue ? 18 : 17, weight: emphasizesValue ? .bold : .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func assetChangeLabel(_ key: String) -> String {
        let format = AppLocalization.string(key, locale: AppLocalization.currentAppLocale)
        if let separatorIndex = format.firstIndex(of: ":") {
            return String(format[..<separatorIndex]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        return format
            .replacingOccurrences(of: "%@", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private var customPeriodSheet: some View {
        CashflowCustomPeriodSheetView(
            viewModel: viewModel,
            draftStartDate: $draftStartDate,
            draftEndDate: $draftEndDate
        )
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
                        .fill(gradientStroke.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: compactMetrics ? 15 : 16, weight: .semibold))
                        .foregroundStyle(gradientStroke)
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
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.20))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            }
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
