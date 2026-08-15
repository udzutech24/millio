//
//  FinanceDynamicsView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//
//  Обновлено: Новый дизайн графика с интерактивным выбором точки,
//  collapsing header и улучшенным UX.
//

import SwiftUI
import SwiftData
import Charts



enum FinanceDynamicsTopBarStyle {
    static let passiveIconColor = Color.white.opacity(0.9)
    static let compactButtonSide: CGFloat = 30
    static let compactIconSize: CGFloat = 17
    static let compactSeparatorHeight: CGFloat = 14
    static let compactSeparatorColor = Color.white.opacity(0.14)
    static let containerFillColor = Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.96)
    static let containerStrokeColor = Color.white.opacity(0.16)
    static let containerStrokeWidth: CGFloat = 0.7
    static let containerHorizontalPadding: CGFloat = 6
    static let containerVerticalPadding: CGFloat = 4
    static let baseScrollContentTopPadding: CGFloat = 18
    static let singleAccountCreditCardScrollContentClearanceTopPadding: CGFloat = 24
    static let periodSelectorTopPadding: CGFloat = 10

    static func inlineEditorSymbol(isEditing: Bool) -> String {
        isEditing ? "checkmark" : "square.and.pencil"
    }

    /// В single-account режиме (детали продукта) navigation bar становится визуально "прозрачным",
    /// и его trailing-кнопки могут пересекаться с самым верхом ScrollView.
    /// Для кредитных карт мы добавляем дополнительный отступ сверху, чтобы:
    /// - название продукта не пересекалось с navigation bar,
    /// - блок лимита/долга начинался ниже.
    static func scrollContentTopPadding(needsClearance: Bool) -> CGFloat {
        baseScrollContentTopPadding + (needsClearance ? singleAccountCreditCardScrollContentClearanceTopPadding : 0)
    }
}

enum FinanceDynamicsHeaderStyle {
    static let summaryCardCornerRadius: CGFloat = 16
    static let summaryCardHeight: CGFloat = 88
    static let summaryTitleFontSize: CGFloat = 12
    static let summaryAmountFontSize: CGFloat = 24
}

enum FinanceAccountArchivePolicy {
    /// Нужно ли показывать предупреждение перед архивированием счёта
    static func shouldShowBalanceWarning(balance: Double) -> Bool {
        abs(balance) > 0.01
    }
}

enum FinanceDynamicsDeleteLayoutPolicy {
    static func showsDeleteFooter(
        isSingleAccountMode: Bool,
        hasInitialAccount: Bool,
        hasMarketInvestment: Bool
    ) -> Bool {
        isSingleAccountMode && hasInitialAccount && !hasMarketInvestment
    }

    static func showsMarketDeleteFooter(
        isSingleAccountMode: Bool,
        hasInitialAccount: Bool,
        hasMarketInvestment: Bool
    ) -> Bool {
        isSingleAccountMode && hasInitialAccount && hasMarketInvestment
    }
}

// MARK: - Finance Dynamics View

struct FinanceDynamicsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @ObservedObject var financeViewModel: FinanceViewModel
    @State private var dynamicsViewModel: FinanceDynamicsViewModel?
    @State private var showSubscriptionSheet = false

    /// ID группы для предустановки фильтров (опционально)
    var initialGroupID: String? = nil

    /// Валюта группы для предустановки (опционально)
    var initialGroupCurrency: String? = nil

    /// ID счета для предустановки фильтров (опционально)
    var initialAccountID: String? = nil

    /// Валюта счета для предустановки (опционально)
    var initialAccountCurrency: String? = nil

    /// Счет для действий (редактирование/удаление) в режиме одного счета
    var initialAccount: FinanceAccount? = nil

    /// Нужно ли оборачивать в NavigationStack (для sheet'ов нужен, для navigationDestination - нет)
    var wrapInNavigationStack: Bool = true

    var body: some View {
        let content = Group {
            if let dynamicsViewModel = dynamicsViewModel {
                FinanceDynamicsContentView(
                    viewModel: dynamicsViewModel,
                    appState: appState,
                    showSubscriptionSheet: $showSubscriptionSheet,
                    financeViewModel: financeViewModel,
                    initialAccountID: initialAccountID,
                    initialAccount: initialAccount
                )
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if dynamicsViewModel == nil {
                dynamicsViewModel = FinanceDynamicsViewModel(
                    modelContext: modelContext,
                    financeViewModel: financeViewModel,
                    initialGroupID: initialGroupID,
                    initialGroupCurrency: initialGroupCurrency,
                    initialAccountID: initialAccountID,
                    initialAccountCurrency: initialAccountCurrency
                )
                dynamicsViewModel?.handle(.loadData)
            } else {
                // Обновляем данные при возврате на экран
                dynamicsViewModel?.handle(.loadData)
            }
        }
        .onChange(of: financeViewModel.state.availableCards.map {
            "\($0.cardUniqueID)_\($0.balance)_\($0.updatedAt.timeIntervalSince1970)"
        }) { _, _ in
            dynamicsViewModel?.handle(.loadData)
        }
        .onChange(of: financeViewModel.state.availableCredits.map {
            "\($0.creditUniqueID)_\($0.remainingAmount)_\($0.updatedAt.timeIntervalSince1970)"
        }) { _, _ in
            dynamicsViewModel?.handle(.loadData)
        }
        .onChange(of: financeViewModel.state.availableInvestments.map {
            "\($0.investmentUniqueID)_\($0.amount)_\($0.updatedAt.timeIntervalSince1970)"
        }) { _, _ in
            dynamicsViewModel?.handle(.loadData)
        }
        .onChange(of: appState.primaryCurrencyCode) { _, newValue in
            dynamicsViewModel?.handle(.setDisplayCurrency(newValue))
        }

        if wrapInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Finance Dynamics Content View

private struct FinanceDynamicsContentView: View {
    @ObservedObject var viewModel: FinanceDynamicsViewModel
    @Bindable var appState: AppState
    @Binding var showSubscriptionSheet: Bool
    @ObservedObject var financeViewModel: FinanceViewModel
    @AppStorage("finance_display_currency_hint_seen") private var hasSeenDisplayCurrencyHint: Bool = false
    var initialAccountID: String? = nil
    var initialAccount: FinanceAccount? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @State private var collapseProgress: CGFloat = 0
    @State private var lastCollapseProgress: CGFloat = 0

    // Локальное состояние для кастомного периода
    @State private var useCustomPeriod: Bool = false
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    @State private var showCustomPeriodSheet: Bool = false
    @State private var draftStartDate: Date = Date()
    @State private var draftEndDate: Date = Date()
    @State private var showDisplayCurrencyInfoBanner: Bool = false
    @State private var showDisplayCurrencyInfoAlert: Bool = false
    @State private var showDisplayCurrencySheet: Bool = false
    @State private var displayCurrencySearchText: String = ""
    @State private var isBreakdownExpanded: Bool = false
    @State private var showCashflowHistory: Bool = false
    @State private var cashflowViewModel: CashflowViewModel? = nil
    @State private var isInlineAccountEdit: Bool = false
    @State private var inlineAmountText: String = ""
    @State private var inlineCreditLimitText: String = ""
    @State private var inlineCreditDebtText: String = ""
    @State private var showOverviewExpandedChart: Bool = false
    @State private var selectedOverviewGranularity: FinanceOverviewGranularity = .month
    @State private var selectedOverviewPeriods: [FinanceOverviewGranularity: Date] = [:]
    @State private var overviewEntriesByGranularity: [FinanceOverviewGranularity: [FinanceOverviewPeriodEntry]] = [:]
    @State private var isOverviewChartLoading: Bool = false
    @State private var showDeleteAccountConfirmation: Bool = false
    @State private var showConvertToCoreConfirmation: Bool = false
    @State private var showPurgeLegacyConfirmation: Bool = false
    @State private var purgeLegacyTransactionCount: Int = 0
    @State private var showDeleteGroupConfirmation: Bool = false
    @State private var showArchiveBalanceWarning: Bool = false
    @State private var archiveBalanceWarningAmount: Double = 0
    @State private var archiveBalanceWarningCurrency: String = ""

    // Кэшированные значения для графика
    @State private var cachedSelectedPoint: (date: Date, value: Double)? = nil

    private var isAmountHidden: Bool {
        financeViewModel.state.isAmountHidden
    }

    /// Вклад для текущего одиночного аккаунта (nil если не вклад)
    private var depositInvestment: Investment? {
        guard viewModel.state.isSingleAccountMode,
              let account = initialAccount else { return nil }
        return financeViewModel.state.availableInvestments
            .first { $0.investmentUniqueID == account.accountID && $0.isDeposit }
    }

    /// Прогнозные точки роста вклада (для пунктирной линии на графике)
    private var depositProjectedPoints: [ChartDataPoint]? {
        guard let deposit = depositInvestment,
              let rate = deposit.depositInterestRate, rate > 0,
              let endDate = deposit.depositEndDate else { return nil }
        let startDate = deposit.depositStartDate ?? Date()
        let today = Date()
        guard endDate > today else { return nil }
        let cap = DepositCapitalization(rawValue: deposit.depositCapitalizationRaw) ?? .none
        var points: [ChartDataPoint] = []
        var date = today
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        while date <= endDate {
            let months = max(0, Calendar.current.dateComponents([.month], from: startDate, to: date).month ?? 0)
            let income: Double
            switch cap {
            case .none:
                income = deposit.amount * rate / 100.0 / 12.0 * Double(months)
            case .monthly:
                income = deposit.amount * (pow(1.0 + rate / 100.0 / 12.0, Double(months)) - 1.0)
            }
            points.append(ChartDataPoint(date: date, value: deposit.amount + income, label: formatter.string(from: date)))
            if let next = Calendar.current.date(byAdding: .month, value: 1, to: date) {
                date = next
            } else { break }
        }
        return points.isEmpty ? nil : points
    }

    private enum NavigationToolbarMode {
        case group(AccountGroup)
        case account(FinanceAccount)
        case none
    }

    var body: some View {
        configuredContent
    }

    private var configuredContent: some View {
        Group {
            if case .none = navigationToolbarMode {
                baseContent
            } else {
                baseContent
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { navigationToolbarContent }
            }
        }
        .sheet(isPresented: filterSheetBinding) {
            FinanceDynamicsFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showCustomPeriodSheet) {
            customPeriodSheet
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            NavigationStack {
                SubscriptionView()
            }
        }
        .sheet(isPresented: $showDisplayCurrencySheet) {
            displayCurrencySheet
        }
        .sheet(isPresented: $showCashflowHistory) {
            cashflowHistorySheetContent
        }
        .onAppear(perform: handleOnAppear)
    }

    private var baseContent: some View {
        ZStack {
            GradientBackground()
            dynamicsBodyContent
        }
        .overlay {
            ZStack {
                FinancesDestructiveConfirmationOverlay(
                    isPresented: showDeleteAccountConfirmation,
                    title: deleteAccountConfirmationTitle,
                    message: String(localized: deleteAccountConfirmationMessageKey),
                    confirmTitle: L("finances.common.delete"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: confirmDeleteAccount,
                    onCancel: { showDeleteAccountConfirmation = false }
                )

                FinancesDestructiveConfirmationOverlay(
                    isPresented: showPurgeLegacyConfirmation,
                    title: purgeLegacyConfirmationTitle,
                    message: purgeLegacyConfirmationMessage,
                    confirmTitle: L("finances.common.delete"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: confirmPurgeLegacyAccount,
                    onCancel: { showPurgeLegacyConfirmation = false }
                )

                FinancesDestructiveConfirmationOverlay(
                    isPresented: showConvertToCoreConfirmation,
                    title: L("finances.convert_to_core.confirm.title"),
                    message: L("finances.convert_to_core.confirm.message"),
                    confirmTitle: L("finances.convert_to_core.confirm.action"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: confirmConvertToCore,
                    onCancel: { showConvertToCoreConfirmation = false }
                )

                FinancesDestructiveConfirmationOverlay(
                    isPresented: showDeleteGroupConfirmation,
                    title: deleteGroupConfirmationTitle,
                    message: deleteGroupConfirmationMessage,
                    confirmTitle: L("finances.common.delete"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: confirmDeleteCurrentGroup,
                    onCancel: { showDeleteGroupConfirmation = false }
                )

                FinancesDestructiveConfirmationOverlay(
                    isPresented: showArchiveBalanceWarning,
                    title: L("finances.archive.balance_warning.title"),
                    message: archiveBalanceWarningMessage,
                    confirmTitle: L("finances.archive.balance_warning.confirm"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: {
                        showArchiveBalanceWarning = false
                        confirmDeleteAccount()
                    },
                    onCancel: { showArchiveBalanceWarning = false }
                )
            }
        }
    }

    private var navigationTitleText: String {
        if viewModel.state.isSingleAccountMode {
            return ""
        }
        if let group = currentDynamicsGroup {
            return group.name
        }
        return L("finances.dynamics.title")
    }

    private var filterSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.state.showFilterSheet },
            set: { if !$0 { viewModel.handle(.hideFilterSheet) } }
        )
    }

    @ToolbarContentBuilder
    private var navigationToolbarContent: some ToolbarContent {
        switch navigationToolbarMode {
        case .group(let group):
            ToolbarItem(placement: .navigationBarTrailing) {
                singleGroupActionBar(group: group)
            }
        case .account(let account):
            ToolbarItem(placement: .navigationBarTrailing) {
                singleAccountActionBar(account: account)
            }
        case .none:
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EmptyView()
            }
        }
    }

    private var navigationToolbarMode: NavigationToolbarMode {
        if let group = currentDynamicsGroup {
            return .group(group)
        }
        if shouldShowSingleAccountActionBar, let account = initialAccount {
            return .account(account)
        }
        return .none
    }

    @ViewBuilder
    private var cashflowHistorySheetContent: some View {
        if let cashflowViewModel {
            CashflowTransactionsHistoryView(viewModel: cashflowViewModel)
        }
    }

    private func handleOnAppear() {
        if let customPeriod = viewModel.state.customPeriod {
            customStartDate = customPeriod.start
            customEndDate = customPeriod.end
            useCustomPeriod = viewModel.state.period == .custom
        }
        if cashflowViewModel == nil {
            cashflowViewModel = CashflowViewModel(modelContext: modelContext)
        }
    }

    private var dynamicsBodyContent: some View {
        standardDynamicsContent
    }

    private var standardDynamicsContent: some View {
        let isCreditCardAccount = initialAccount.map { inlineCreditCard(for: $0) != nil } ?? false
        let needsTopClearance = viewModel.state.isSingleAccountMode && isCreditCardAccount && shouldShowSingleAccountActionBar
        let scrollTopPadding = FinanceDynamicsTopBarStyle.scrollContentTopPadding(needsClearance: needsTopClearance)

        return GeometryReader { safeProxy in
            let topInset = safeProxy.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 16) {
                    Color.clear
                        .frame(height: 0)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetKey.self,
                                        value: proxy.frame(in: .named("dynScroll")).minY
                                    )
                            }
                        )

                    chartCard

                    // Полоса параметров вклада (Phase 5)
                    if let deposit = depositInvestment {
                        depositParamsStrip(for: deposit)
                    }

                    dynamicsListCard

                    if !viewModel.state.isSingleAccountMode && !viewModel.state.dynamicsBreakdown.isEmpty {
                        if EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro) {
                            groupsDonutCard
                        } else {
                            proBlockedDonutCard(
                                titleKey: "finances.dynamics.chart_type.distribution",
                                accentColor: Color(red: 0.75, green: 0.60, blue: 1.00)
                            )
                        }
                    }

                    if !viewModel.state.isSingleAccountMode && !viewModel.state.currencyBreakdown.isEmpty {
                        if EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro) {
                            currencyBreakdownCard
                        } else {
                            proBlockedDonutCard(
                                titleKey: "finances.dynamics.chart_type.currency",
                                accentColor: Color(red: 1.00, green: 0.72, blue: 0.30)
                            )
                        }
                    }

                    // Блок прогноза дохода по вкладу (Phase 5 + 8)
                    if let deposit = depositInvestment {
                        depositForecastSection(for: deposit)
                    }

                    if shouldShowDeleteAccountFooter, let account = initialAccount {
                        convertToCoreFooterButton(account: account)
                        deleteAccountFooterButton(account: account)
                        purgeLegacyAccountFooterButton(account: account)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, topInset + scrollTopPadding)
                .padding(.bottom, shouldShowDeleteAccountFooter ? 44 : 32)
            }
            .ignoresSafeArea(edges: .top)
            .coordinateSpace(name: "dynScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { y in
                let threshold: CGFloat = 140
                let p = min(max(-y / threshold, 0), 1)
                let quant: CGFloat = 0.02
                if abs(p - lastCollapseProgress) > quant {
                    lastCollapseProgress = p
                    collapseProgress = p
                }
            }
        }
    }

    private var currentDynamicsGroup: AccountGroup? {
        guard viewModel.state.isSingleGroupMode, !viewModel.state.isSingleAccountMode else { return nil }
        guard let groupID = viewModel.state.selectedGroupIDs.first else { return nil }
        return financeViewModel.state.groups.first { $0.groupUniqueID == groupID }
    }

    private func singleGroupActionBar(group: AccountGroup) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                FinanceAddAccountView(
                    viewModel: financeViewModel,
                    preselectedGroup: group,
                    presentationStyle: .pushed
                )
                .onDisappear {
                    viewModel.handle(.loadData)
                }
            } label: {
                Image(systemName: "plus")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: FinanceDynamicsTopBarStyle.compactIconSize, weight: .regular))
                    .foregroundStyle(FinanceDynamicsTopBarStyle.passiveIconColor)
                    .frame(width: FinanceDynamicsTopBarStyle.compactButtonSide, height: FinanceDynamicsTopBarStyle.compactButtonSide)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: FinanceDynamicsTopBarStyle.compactSeparatorHeight)
                .overlay(FinanceDynamicsTopBarStyle.compactSeparatorColor)

            NavigationLink {
                FinanceGroupEditorView(
                    viewModel: financeViewModel,
                    editingGroupOverride: group,
                    presentationStyle: .pushed
                )
                .onDisappear {
                    viewModel.handle(.loadData)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: FinanceDynamicsTopBarStyle.compactIconSize, weight: .regular))
                    .foregroundStyle(FinanceDynamicsTopBarStyle.passiveIconColor)
                    .frame(width: FinanceDynamicsTopBarStyle.compactButtonSide, height: FinanceDynamicsTopBarStyle.compactButtonSide)
            }
            .buttonStyle(.plain)
        }
    }

    private func confirmDeleteCurrentGroup() {
        guard let group = currentGroup else { return }
        showDeleteGroupConfirmation = false
        financeViewModel.handle(.hideGroupDynamics)
        financeViewModel.handle(.deleteGroup(group))
    }

    private func rawNumberString(_ value: Double, maxFractionDigits: Int) -> String {
        AmountInputFormatter.display(
            AmountInputFormatter.plainString(from: value, maxFractionDigits: maxFractionDigits),
            maxFractionDigits: maxFractionDigits
        )
    }

    private var overviewReloadToken: String {
        let chartSignature = viewModel.state.chartData.map {
            "\($0.date.timeIntervalSince1970)_\($0.value)"
        }.joined(separator: "|")
        let groups = viewModel.state.selectedGroupIDs.sorted().joined(separator: ",")
        let accounts = viewModel.state.selectedAccountIDs.sorted().joined(separator: ",")
        return [
            viewModel.state.displayCurrency,
            viewModel.state.showArchivedAccounts ? "1" : "0",
            groups,
            accounts,
            chartSignature
        ].joined(separator: "#")
    }

    private func reloadOverviewChart() async {
        guard EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro) else { return }
        isOverviewChartLoading = true

        // The structured external-coverage adapter owns query-scoped evidence while the producer
        // awaits FX/market resolution. Keep these reads sequential so three overview queries cannot
        // overwrite each other's prepared legacy boundary state.
        let weekEntries = await viewModel.buildOverviewEntries(granularity: .week)
        let monthEntries = await viewModel.buildOverviewEntries(granularity: .month)
        let yearEntries = await viewModel.buildOverviewEntries(granularity: .year)
        overviewEntriesByGranularity = [
            .week: weekEntries,
            .month: monthEntries,
            .year: yearEntries
        ]
        isOverviewChartLoading = false
    }

    private var financeOverviewChartSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L("finances.overview.chart.title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button {
                    showOverviewExpandedChart = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L("finances.overview.chart.full"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if !EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro) {
                proBlockedView(size: .compact)
            } else if isOverviewChartLoading {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if hasOverviewData {
                VStack(spacing: 16) {
                    financeOverviewSummaryRow(presentation: compactOverviewPresentation, compact: true)
                    financeOverviewBars(
                        presentation: compactOverviewPresentation,
                        chartHeight: 170,
                        maxBarHeight: 108,
                        minimumGroupWidth: 60,
                        barWidth: 16,
                        labelFontSize: 13,
                        scrollable: false
                    )
                    financeOverviewGranularityPicker
                }
            } else {
                financeOverviewEmptyState
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(dynamicsCardBackground)
    }

    private var financeOverviewExpandedChartSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        financeOverviewSummaryRow(presentation: fullScreenOverviewPresentation, compact: false)
                        financeOverviewBars(
                            presentation: fullScreenOverviewPresentation,
                            chartHeight: 270,
                            maxBarHeight: 186,
                            minimumGroupWidth: 58,
                            barWidth: 18,
                            labelFontSize: 14,
                            scrollable: true
                        )
                        financeOverviewGranularityPicker
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L("finances.overview.chart.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("cashflow.common.dismiss")) {
                        showOverviewExpandedChart = false
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }

    private func financeOverviewSummaryRow(
        presentation: FinanceOverviewPresentation,
        compact: Bool
    ) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            financeOverviewSummaryCard(
                title: L("finances.overview.chart.credit"),
                value: presentation.selectedBar.credit,
                accent: AppColors.error,
                compact: compact
            )
            financeOverviewSummaryCard(
                title: L("finances.overview.chart.debit"),
                value: presentation.selectedBar.debit,
                accent: Color(red: 0.38, green: 0.96, blue: 0.71),
                compact: compact
            )
            financeOverviewSummaryCard(
                title: L("finances.overview.chart.saldo"),
                value: presentation.selectedBar.saldo,
                accent: overviewSaldoColor(for: presentation.selectedBar.saldo),
                compact: compact,
                signed: true
            )
        }
    }

    private func financeOverviewSummaryCard(
        title: String,
        value: Double,
        accent: Color,
        compact: Bool,
        signed: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Text(signed ? formatDelta(value) : formatBalance(value))
                .font(.system(size: compact ? 18 : 22, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 0.9)
                )
        )
    }

    private func financeOverviewBars(
        presentation: FinanceOverviewPresentation,
        chartHeight: CGFloat,
        maxBarHeight: CGFloat,
        minimumGroupWidth: CGFloat,
        barWidth: CGFloat,
        labelFontSize: CGFloat,
        scrollable: Bool
    ) -> some View {
        Group {
            if scrollable {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(presentation.bars) { bar in
                            financeOverviewBarGroup(
                                bar: bar,
                                presentation: presentation,
                                maxValue: overviewBarMaxValue(for: presentation),
                                groupWidth: minimumGroupWidth,
                                maxBarHeight: maxBarHeight,
                                barWidth: barWidth,
                                labelFontSize: labelFontSize
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } else {
                GeometryReader { proxy in
                    let groupWidth = max((proxy.size.width - 24) / CGFloat(max(presentation.bars.count, 1)), minimumGroupWidth)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(presentation.bars) { bar in
                            financeOverviewBarGroup(
                                bar: bar,
                                presentation: presentation,
                                maxValue: overviewBarMaxValue(for: presentation),
                                groupWidth: groupWidth,
                                maxBarHeight: maxBarHeight,
                                barWidth: barWidth,
                                labelFontSize: labelFontSize
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .frame(height: chartHeight)
    }

    private func financeOverviewBarGroup(
        bar: FinanceOverviewBar,
        presentation: FinanceOverviewPresentation,
        maxValue: Double,
        groupWidth: CGFloat,
        maxBarHeight: CGFloat,
        barWidth: CGFloat,
        labelFontSize: CGFloat
    ) -> some View {
        let isSelected = bar.periodStart == presentation.selectedPeriodStart
        let creditHeight = overviewBarHeight(value: bar.credit, maxValue: maxValue, maxBarHeight: maxBarHeight, isSelected: isSelected)
        let debitHeight = overviewBarHeight(value: bar.debit, maxValue: maxValue, maxBarHeight: maxBarHeight, isSelected: isSelected)

        return Button {
            selectedOverviewPeriods[selectedOverviewGranularity] = bar.periodStart
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.08 : 0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(isSelected ? 0.18 : 0.08), lineWidth: 0.8)
                        )

                    VStack(spacing: 10) {
                        Spacer(minLength: 0)

                        HStack(alignment: .bottom, spacing: 10) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppColors.error.opacity(0.95), AppColors.error.opacity(0.55)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: barWidth, height: creditHeight)

                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.38, green: 0.96, blue: 0.71), Color(red: 0.26, green: 0.72, blue: 1.0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: barWidth, height: debitHeight)
                        }
                        .frame(height: maxBarHeight, alignment: .bottom)

                        HStack(spacing: 10) {
                            Text(L("finances.overview.chart.credit"))
                                .foregroundStyle(AppColors.textSecondary)
                            Text(L("finances.overview.chart.debit"))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
                .frame(width: groupWidth, height: maxBarHeight + 64)

                VStack(spacing: 4) {
                    Text(bar.label)
                        .font(.system(size: labelFontSize, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(formatDelta(bar.saldo))
                        .font(.system(size: max(11, labelFontSize - 1), weight: .medium))
                        .foregroundStyle(overviewSaldoColor(for: bar.saldo))
                }
            }
            .frame(width: groupWidth)
        }
        .buttonStyle(.plain)
    }

    private var financeOverviewGranularityPicker: some View {
        HStack(spacing: 8) {
            ForEach(FinanceOverviewGranularity.allCases) { granularity in
                Button {
                    selectedOverviewGranularity = granularity
                } label: {
                    Text(granularity.title)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(selectedOverviewGranularity == granularity ? 0.14 : 0.05))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(selectedOverviewGranularity == granularity ? 0.18 : 0.08), lineWidth: 0.8)
                        )
                        .foregroundStyle(
                            selectedOverviewGranularity == granularity
                                ? AppColors.textPrimary
                                : AppColors.textSecondary
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var compactOverviewPresentation: FinanceOverviewPresentation {
        FinanceOverviewChartBuilder.makePresentation(
            entries: overviewEntriesByGranularity[selectedOverviewGranularity] ?? [],
            granularity: selectedOverviewGranularity,
            selectedPeriodStart: selectedOverviewPeriods[selectedOverviewGranularity],
            referenceDate: Date(),
            calendar: .current,
            locale: .autoupdatingCurrent
        )
    }

    private var fullScreenOverviewPresentation: FinanceOverviewPresentation {
        FinanceOverviewChartBuilder.makeFullScreenPresentation(
            entries: overviewEntriesByGranularity[selectedOverviewGranularity] ?? [],
            granularity: selectedOverviewGranularity,
            selectedPeriodStart: selectedOverviewPeriods[selectedOverviewGranularity] ?? compactOverviewPresentation.selectedPeriodStart,
            referenceDate: Date(),
            calendar: .current,
            locale: .autoupdatingCurrent
        )
    }

    private var hasOverviewData: Bool {
        (overviewEntriesByGranularity[selectedOverviewGranularity] ?? []).contains {
            $0.debit > 0.01 || $0.credit > 0.01
        }
    }

    private var financeOverviewEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text(L("finances.overview.chart.empty"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func overviewBarHeight(
        value: Double,
        maxValue: Double,
        maxBarHeight: CGFloat,
        isSelected: Bool
    ) -> CGFloat {
        guard value > 0.000001 else { return 0 }
        let normalized = maxValue > 0.000001 ? CGFloat(value / maxValue) : 0
        let minimumHeight: CGFloat = isSelected ? 22 : 16
        return max(minimumHeight, normalized * maxBarHeight)
    }

    private func overviewBarMaxValue(for presentation: FinanceOverviewPresentation) -> Double {
        max(
            presentation.bars.flatMap { [$0.debit, $0.credit] }.max() ?? 0,
            1
        )
    }

    private func overviewSaldoColor(for value: Double) -> Color {
        if value > 0.01 {
            return Color(red: 0.38, green: 0.96, blue: 0.71)
        }
        if value < -0.01 {
            return AppColors.error
        }
        return AppColors.textSecondary
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        let expandedHeight: CGFloat = 260
        let minHeight: CGFloat = 64
        let effectiveCollapse = viewModel.state.isSingleAccountMode ? CGFloat(0) : collapseProgress
        let currentHeight = minHeight + (expandedHeight - minHeight) * max(0, 1 - effectiveCollapse)

        return ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                // Header с балансом и дельтой
                chartHeader

                // График
                if !EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro) {
                    proBlockedView(size: .regular)
                        .frame(height: max(0, currentHeight - 64))
                } else if viewModel.state.isLoading {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(0, currentHeight - 64))
                } else if viewModel.state.chartData.isEmpty {
                    emptyChartView
                        .frame(height: max(0, currentHeight - 64))
                } else {
                    chartContent
                        .frame(height: max(0, currentHeight - 64))
                        .padding(.top, 8)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.state.period)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.state.displayCurrency)
                }

                // Селектор периодов
                periodSelector
                    .padding(.top, FinanceDynamicsTopBarStyle.periodSelectorTopPadding)
            }
            .scaleEffect(x: 1, y: max(CGFloat(0.6), CGFloat(1) - effectiveCollapse * CGFloat(0.6)), anchor: .top)
            .clipped()
            .opacity(Double(max(CGFloat(0.35), CGFloat(1) - effectiveCollapse * CGFloat(0.65))))

            // Градиент при сворачивании
            if effectiveCollapse > 0.05 {
                LinearGradient(
                    colors: [AppColors.textTertiary.opacity(0.14), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: max(12, 24 * effectiveCollapse))
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.3))
        }
        .clipped()
        .frame(height: currentHeight + 100 + FinanceDynamicsTopBarStyle.periodSelectorTopPadding)
    }

    // MARK: - Chart Header

    private var chartHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            let isCreditCardAccount = initialAccount.map { inlineCreditCard(for: $0) != nil } ?? false
            let isSingleAccountSummaryMode = viewModel.state.isSingleAccountMode && !isCreditCardAccount && !isInlineAccountEdit
            HStack(alignment: .center, spacing: 10) {
                // Баланс с валютой
                let symbol = MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency
                if !isCreditCardAccount && !isSingleAccountSummaryMode {
                    if isInlineAccountEdit,
                       let account = initialAccount,
                       inlineCreditCard(for: account) == nil {
                        let editText = Binding(
                            get: { inlineAmountText },
                            set: { inlineAmountText = AmountInputFormatter.display($0) }
                        )
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TextField("0", text: editText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                            dynamicsCurrencySuffix(
                                symbol: symbol,
                                amountFontSize: 30,
                                color: AppColors.textSecondary.opacity(0.82),
                                showsChevron: false
                            )
                        }
                    } else {
                        Button {
                            showDisplayCurrencySheet = true
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(formatBalance(viewModel.state.currentBalance))
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)

                                dynamicsCurrencySuffix(
                                    symbol: symbol,
                                    amountFontSize: 30,
                                    color: AppColors.textSecondary.opacity(0.82),
                                    showsChevron: true
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Бейдж с дельтой (скрываем для detail-режима не-акций)
                if viewModel.state.chartData.count >= 2 && !isSingleAccountSummaryMode && !viewModel.state.isSingleAccountMode {
                    let delta = viewModel.state.periodDelta
                    let positiveText = Color(.sRGB, red: 127.0 / 255.0, green: 1.0, blue: 189.0 / 255.0, opacity: 1.0)
                    let positiveBg = Color(.sRGB, red: 127.0 / 255.0, green: 1.0, blue: 189.0 / 255.0, opacity: 0.3)
                    let negativeText = Color(.sRGB, red: 1.0, green: 0.37, blue: 0.37, opacity: 1.0)
                    let negativeBg = Color(.sRGB, red: 1.0, green: 0.37, blue: 0.37, opacity: 0.3)
                    let neutralText = Color(.sRGB, red: 181.0 / 255.0, green: 181.0 / 255.0, blue: 181.0 / 255.0, opacity: 1.0)
                    let neutralBg = Color(.sRGB, red: 181.0 / 255.0, green: 181.0 / 255.0, blue: 181.0 / 255.0, opacity: 0.3)
                    let isPositive = delta.absolute > 0
                    let isNegative = delta.absolute < 0
                    let color: Color = isPositive ? positiveText : (isNegative ? negativeText : neutralText)
                    let bg: Color = isPositive ? positiveBg : (isNegative ? negativeBg : neutralBg)
                    HStack(spacing: 6) {
                        Text(formatDelta(delta.absolute))
                            .font(.caption.weight(.semibold))
                        // A zero financial baseline has no truthful percentage; keep only the
                        // absolute delta. Privacy mode does not invent a percentage either.
                        if let percent = delta.percent {
                            Text(formatPercent(percent))
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(bg))
                    .foregroundStyle(color)
                }
            }

            if isSingleAccountSummaryMode {
                singleAccountSummaryTable
            }

            // Бейдж счета (если выбран один счет)
            if !isSingleAccountSummaryMode,
               case .singleAccount(let accountID) = viewModel.state.dynamicsMode,
               let account = viewModel.getAccountsForSelectedGroups().first(where: { $0.accountUniqueID == accountID }),
               let accountInfo = viewModel.getAccountInfoForDynamics(account: account) {
                HStack(spacing: 8) {
                    Image(systemName: accountInfo.icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(accountInfo.name)
                        .font(.system(size: 30, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let account = initialAccount, inlineCreditCard(for: account) != nil {
                inlineAccountEditor(for: account)
            }

            // Период
            let (startDate, endDate) = displayedPeriodDates
            let sameYear = Calendar.current.component(.year, from: startDate) == Calendar.current.component(.year, from: endDate)
            let startFormat: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
            let endFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
            Text(
                FinancesL10n.format(
                    "finances.dynamics.period.range",
                    startDate.formatted(startFormat),
                    endDate.formatted(endFormat)
                )
            )
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 0)
    }

    private var singleAccountSummaryTable: some View {
        let symbol = MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency

        let accountName: String = {
            guard case .singleAccount(let accountID) = viewModel.state.dynamicsMode,
                  let account = viewModel.getAccountsForSelectedGroups().first(where: { $0.accountUniqueID == accountID }),
                  let accountInfo = viewModel.getAccountInfoForDynamics(account: account) else {
                return L("finances.dynamics.chart.account_fallback")
            }
            return accountInfo.name
        }()

        return dynamicsSummaryCard(title: accountName, symbol: symbol, value: formatBalance(viewModel.state.currentBalance)) {
            EmptyView()
        }
    }

    private func dynamicsSummaryCard<Trailing: View>(
        title: String,
        symbol: String,
        value: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        RoundedRectangle(cornerRadius: FinanceDynamicsHeaderStyle.summaryCardCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(title + ",")
                                .font(.system(size: FinanceDynamicsHeaderStyle.summaryTitleFontSize, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)

                            dynamicsCurrencySuffix(
                                symbol: symbol,
                                amountFontSize: FinanceDynamicsHeaderStyle.summaryTitleFontSize,
                                color: AppColors.textSecondary.opacity(0.82),
                                showsChevron: false
                            )
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(value)
                                .font(.system(size: FinanceDynamicsHeaderStyle.summaryAmountFontSize, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            dynamicsCurrencySuffix(
                                symbol: symbol,
                                amountFontSize: FinanceDynamicsHeaderStyle.summaryAmountFontSize,
                                color: AppColors.textSecondary.opacity(0.82),
                                showsChevron: false
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    trailing()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .frame(height: FinanceDynamicsHeaderStyle.summaryCardHeight)
    }

    private func dynamicsCurrencySuffix(
        symbol: String,
        amountFontSize: CGFloat,
        color: Color,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: showsChevron ? 3 : 0) {
            Text(symbol)
                .font(.system(size: max(11, amountFontSize * 0.75), weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: max(7, amountFontSize * 0.28), weight: .bold))
                    .foregroundStyle(color.opacity(0.9))
                    .offset(y: -1)
            }
        }
    }

    private var shouldShowSingleAccountActionBar: Bool {
        viewModel.state.isSingleAccountMode && initialAccount != nil
    }

    private var shouldShowDeleteAccountFooter: Bool {
        FinanceDynamicsDeleteLayoutPolicy.showsDeleteFooter(
            isSingleAccountMode: viewModel.state.isSingleAccountMode,
            hasInitialAccount: initialAccount != nil,
            hasMarketInvestment: false
        )
    }

    private var shouldShowDeleteMarketInvestmentFooter: Bool {
        FinanceDynamicsDeleteLayoutPolicy.showsMarketDeleteFooter(
            isSingleAccountMode: viewModel.state.isSingleAccountMode,
            hasInitialAccount: initialAccount != nil,
            hasMarketInvestment: false
        )
    }

    private var deleteAccountConfirmationTitle: String {
        guard let account = initialAccount else {
            return L("finances.dynamics.delete_account")
        }
        let name = financeViewModel.getAccountInfo(account: account)?.name
            ?? L("finances.dynamics.chart.account_fallback")
        return FinanceDeleteProductCopy.confirmationTitle(for: account.accountType, name: name)
    }

    private var deleteAccountActionTitle: LocalizedStringResource {
        guard let account = initialAccount else {
            return "finances.dynamics.delete_account"
        }
        return FinanceDeleteProductCopy.actionTitle(for: account.accountType)
    }

    private var deleteAccountConfirmationMessageKey: LocalizedStringResource {
        guard let account = initialAccount else {
            return "finances.dynamics.delete_account.confirm.message"
        }
        return FinanceDeleteProductCopy.confirmationMessage(for: account.accountType)
    }

    private var currentGroup: AccountGroup? {
        guard viewModel.state.isSingleGroupMode,
              let groupID = viewModel.state.selectedGroupIDs.first else {
            return nil
        }
        return financeViewModel.state.groups.first(where: { $0.groupUniqueID == groupID })
    }

    private var deleteGroupConfirmationTitle: String {
        let groupName = currentGroup?.name ?? L("finances.group.ungrouped")
        return FinancesL10n.format("finances.dynamics.delete_group.confirm.title_format", groupName)
    }

    private var deleteGroupConfirmationMessage: String {
        FinancesL10n.tr("finances.dynamics.delete_group.confirm.message")
    }

    private var archiveBalanceWarningMessage: String {
        let symbol = MonetaCurrency(rawValue: archiveBalanceWarningCurrency)?.symbol ?? archiveBalanceWarningCurrency
        let formatted = FinanceAmountText.withCurrency(
            value: abs(archiveBalanceWarningAmount),
            currencySymbol: symbol,
            isHidden: false
        )
        return FinancesL10n.format("finances.archive.balance_warning.message", formatted)
    }

    /// Track C: «Перевести в новое ядро» — рядом с «Удалить актив» в деталке одиночного счёта.
    private func convertToCoreFooterButton(account: FinanceAccount) -> some View {
        Button {
            showConvertToCoreConfirmation = true
        } label: {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "arrow.up.forward.square")
                Text(L("finances.convert_to_core.action"))
            }
            .font(.millioCalloutSemibold)
            .foregroundStyle(AppColors.textPrimary.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.ml)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        }
        .padding(.bottom, AppSpacing.s)
        .accessibilityIdentifier("finances.convert_to_core.button")
    }

    private func confirmConvertToCore() {
        guard let account = initialAccount else { return }
        showConvertToCoreConfirmation = false
        financeViewModel.handle(.convertAccountToCore(account))
        dismiss()
    }

    private func deleteAccountFooterButton(account: FinanceAccount) -> some View {
        Button(role: .destructive) {
            let info = financeViewModel.getAccountInfo(account: account)
            let amount = info?.amount ?? 0
            if FinanceAccountArchivePolicy.shouldShowBalanceWarning(balance: amount) {
                archiveBalanceWarningAmount = amount
                archiveBalanceWarningCurrency = info?.currency ?? ""
                showArchiveBalanceWarning = true
            } else {
                showDeleteAccountConfirmation = true
            }
        } label: {
            Text(String(localized: deleteAccountActionTitle))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.error.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        }
        .accessibilityIdentifier("finances.delete_account.button")
    }

    private func confirmDeleteAccount() {
        guard let account = initialAccount else { return }
        showDeleteAccountConfirmation = false
        // [Ф5c.7 contract] `.removeAccountFromGroup` теперь core-типизирован — легаси-путь напрямую.
        financeViewModel.removeLegacyAccountFromGroup(account)
        dismiss()
    }

    /// Кнопка полного удаления легаси-счёта (в отличие от «Удалить» выше, которая архивирует).
    /// Показывается только на деталке легаси-счёта (новое ядро использует свой AccountDetailView).
    private func purgeLegacyAccountFooterButton(account: FinanceAccount) -> some View {
        Button(role: .destructive) {
            purgeLegacyTransactionCount = financeViewModel.legacyRelatedTransactionCount(for: account)
            showPurgeLegacyConfirmation = true
        } label: {
            Text(L("finances.purge_legacy.action"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.error.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColors.error.opacity(0.28), lineWidth: 0.8)
                )
        }
        .accessibilityIdentifier("finances.purge_legacy_account.button")
    }

    private func confirmPurgeLegacyAccount() {
        guard let account = initialAccount else { return }
        showPurgeLegacyConfirmation = false
        financeViewModel.handle(.physicallyDeleteLegacyAccount(account))
        dismiss()
    }

    private var purgeLegacyConfirmationTitle: String {
        let name = initialAccount.flatMap { financeViewModel.getAccountInfo(account: $0)?.name }
            ?? L("finances.dynamics.chart.account_fallback")
        return FinancesL10n.format("finances.purge_legacy.confirm.title_format", name)
    }

    private var purgeLegacyConfirmationMessage: String {
        FinancesL10n.format("finances.purge_legacy.confirm.message_format", purgeLegacyTransactionCount)
    }

    // MARK: - Deposit Blocks (Phase 5, 6, 8)

    @ViewBuilder
    private func depositParamsStrip(for deposit: Investment) -> some View {
        let rate = deposit.depositInterestRate ?? 0
        let today = Date()
        let hasEndDate = deposit.depositEndDate != nil
        let daysRemaining: Int? = deposit.depositEndDate.map {
            max(0, Calendar.current.dateComponents([.day], from: today, to: $0).day ?? 0)
        }
        let isMatured = daysRemaining.map { $0 == 0 } ?? false

        VStack(alignment: .leading, spacing: 8) {
            // Строка параметров
            HStack(spacing: 6) {
                Image(systemName: "percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.toggleOnGreen)
                Text("\(rate, specifier: "%.2g")% \(L("finances.deposit.params.per_year", defaultValue: "годовых"))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                if hasEndDate, let end = deposit.depositEndDate {
                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(end, style: .date)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                if isMatured {
                    Text(L("finances.deposit.params.matured"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.warning)
                } else if let days = daysRemaining {
                    Text(String(format: L("finances.deposit.params.days_remaining"), days))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Progress bar срока
            if let end = deposit.depositEndDate,
               let start = deposit.depositStartDate {
                let total = end.timeIntervalSince(start)
                let elapsed = today.timeIntervalSince(start)
                let progress = total > 0 ? min(max(elapsed / total, 0), 1) : 0
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppColors.toggleOnGreen.opacity(0.8))
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColors.toggleOnGreen.opacity(0.2), lineWidth: 0.8)
                )
        }
    }

    @ViewBuilder
    private func depositForecastSection(for deposit: Investment) -> some View {
        if let rate = deposit.depositInterestRate, rate > 0 {
            DepositForecastView(deposit: deposit, rate: rate)
        }
    }

    private func singleAccountActionBar(account: FinanceAccount) -> some View {
        HStack(spacing: 8) {
            let canSave = canSaveInlineAccountEdit(for: account)
            Button {
                if isInlineAccountEdit {
                    if canSave {
                        finishInlineAccountEdit(for: account)
                    }
                } else {
                    startInlineAccountEdit(for: account)
                }
            } label: {
                Image(systemName: FinanceDynamicsTopBarStyle.inlineEditorSymbol(isEditing: isInlineAccountEdit))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: FinanceDynamicsTopBarStyle.compactIconSize, weight: .regular))
                    .foregroundStyle(
                        isInlineAccountEdit
                            ? (canSave ? Color(red: 0.20, green: 0.92, blue: 0.49) : Color.white.opacity(0.4))
                            : FinanceDynamicsTopBarStyle.passiveIconColor
                    )
                    .frame(width: FinanceDynamicsTopBarStyle.compactButtonSide, height: FinanceDynamicsTopBarStyle.compactButtonSide)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: FinanceDynamicsTopBarStyle.compactSeparatorHeight)
                .overlay(FinanceDynamicsTopBarStyle.compactSeparatorColor)

            Button {
                if cashflowViewModel == nil {
                    cashflowViewModel = CashflowViewModel(modelContext: modelContext)
                }
                cashflowViewModel?.handle(.loadTransactions)
                showCashflowHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: FinanceDynamicsTopBarStyle.compactIconSize, weight: .regular))
                    .foregroundStyle(FinanceDynamicsTopBarStyle.passiveIconColor)
                    .frame(width: FinanceDynamicsTopBarStyle.compactButtonSide, height: FinanceDynamicsTopBarStyle.compactButtonSide)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, FinanceDynamicsTopBarStyle.containerHorizontalPadding)
        .padding(.vertical, FinanceDynamicsTopBarStyle.containerVerticalPadding)
    }

    private func startInlineAccountEdit(for account: FinanceAccount) {
        if let card = inlineCreditCard(for: account) {
            inlineCreditLimitText = rawNumberString(card.creditLimit ?? 0, maxFractionDigits: 2)
            let debt = max(0, (card.creditLimit ?? 0) - card.balance)
            inlineCreditDebtText = rawNumberString(debt, maxFractionDigits: 2)
        } else if let info = viewModel.getLiveAccountInfoForDynamics(account: account) {
            inlineAmountText = rawNumberString(info.amount, maxFractionDigits: 2)
        }
        isInlineAccountEdit = true
    }

    private func finishInlineAccountEdit(for account: FinanceAccount) {
        guard canSaveInlineAccountEdit(for: account) else { return }
        // [Ф5c.7 contract] Легаси инлайн-редактор — actions теперь core-типизированы, легаси-путь напрямую.
        if inlineCreditCard(for: account) != nil {
            let limit = AmountInputFormatter.parse(inlineCreditLimitText) ?? 0
            let debt = AmountInputFormatter.parse(inlineCreditDebtText) ?? 0
            financeViewModel.updateLegacyCreditCardQuickFields(account: account, creditLimit: limit, debt: debt)
        } else {
            let amount = AmountInputFormatter.parse(inlineAmountText) ?? 0
            financeViewModel.updateLegacyAccountAmount(account: account, newAmount: amount)
        }
        viewModel.handle(.loadData)
        isInlineAccountEdit = false
    }

    private func inlineCreditCard(for account: FinanceAccount) -> Card? {
        guard account.accountType == .card else { return nil }
        return financeViewModel.state.availableCards.first(where: { $0.cardUniqueID == account.accountID && $0.cardType == .credit })
    }

    private func canSaveInlineAccountEdit(for account: FinanceAccount) -> Bool {
        if inlineCreditCard(for: account) != nil {
            guard let limit = AmountInputFormatter.parse(inlineCreditLimitText),
                  let debt = AmountInputFormatter.parse(inlineCreditDebtText) else { return false }
            return limit >= 0 && debt >= 0 && debt <= limit
        }
        guard let amount = AmountInputFormatter.parse(inlineAmountText) else { return false }
        return amount >= 0
    }

    @ViewBuilder
    private func inlineAccountEditor(for account: FinanceAccount) -> some View {
        if let info = financeViewModel.getAccountInfo(account: account),
           let creditCard = inlineCreditCard(for: account) {
            let persistedLimit = creditCard.creditLimit ?? 0
            let persistedDebt = max(0, persistedLimit - creditCard.balance)
            let limit = isInlineAccountEdit ? (AmountInputFormatter.parse(inlineCreditLimitText) ?? persistedLimit) : persistedLimit
            let debt = isInlineAccountEdit ? (AmountInputFormatter.parse(inlineCreditDebtText) ?? persistedDebt) : persistedDebt
            let remaining = max(0, limit - debt)

            VStack(spacing: 8) {
                creditFieldRow(
                    title: L("finances.add_account.card.credit_limit"),
                    value: limit,
                    currency: info.currency,
                    isEditing: isInlineAccountEdit,
                    text: Binding(
                        get: { inlineCreditLimitText },
                        set: { inlineCreditLimitText = AmountInputFormatter.display($0) }
                    )
                )
                creditFieldRow(
                    title: L("finances.add_account.card.total_debt"),
                    value: debt,
                    currency: info.currency,
                    isEditing: isInlineAccountEdit,
                    text: Binding(
                        get: { inlineCreditDebtText },
                        set: { inlineCreditDebtText = AmountInputFormatter.display($0) }
                    )
                )
                creditFieldRow(
                    title: L("finances.add_account.card.remaining_limit"),
                    value: remaining,
                    currency: info.currency,
                    isEditing: false,
                    text: nil
                )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.12), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 0.8)
                    )
            )
        }
    }

    private func creditFieldRow(
        title: String,
        value: Double,
        currency: String,
        isEditing: Bool,
        text: Binding<String>?
    ) -> some View {
        let isEditable = text != nil
        return HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEditable ? AppColors.textSecondary : AppColors.textSecondary.opacity(0.85))
            Spacer()
            if isEditing, let text {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: 170)
            } else {
                Text(formatBalance(value))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }
            Text(currency)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.03, green: 0.10, blue: 0.16),
                            Color.black.opacity(isEditable ? 0.6 : 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isEditing && isEditable
                                ? Color.cyan.opacity(0.75)
                                : Color.cyan.opacity(isEditable ? 0.22 : 0.12),
                            lineWidth: isEditing && isEditable ? 1.2 : 0.7
                        )
                )
        )
    }

    private func inlineEditRow(title: String, text: Binding<String>, suffix: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: 150)
            Text(suffix)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Chart Content

    private var chartContent: some View {
        let points = viewModel.state.chartData
        let values = points.map { $0.value }
        let niceY = NiceYScale.make(values: values)
        let (startDate, endDate) = displayedPeriodDates
        let xDomain = startDate...endDate

        let seriesColor = Color(red: 0.47, green: 0.69, blue: 1.0)
        return FinanceChartContainerView(
            points: points,
            selectedPoint: cachedSelectedPoint,
            seriesColor: seriesColor,
            niceY: niceY,
            xDomain: xDomain,
            xAxisStride: xAxisStride,
            xAxisCount: xAxisCount,
            currencyCode: viewModel.state.displayCurrency,
            isAmountHidden: isAmountHidden,
            onSelectPoint: { newPoint in
                if let pt = newPoint {
                    cachedSelectedPoint = (date: pt.0, value: pt.1)
                } else {
                    cachedSelectedPoint = nil
                }
            },
            projectedPoints: depositProjectedPoints
        )
    }

    private var displayCurrencySheet: some View {
        let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
        let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
        return NavigationStack {
            CurrencyPickerView(
                allCodes: viewModel.state.availableCurrencies.isEmpty
                    ? CurrencySelectionSupport.pickerCodes()
                    : viewModel.state.availableCurrencies,
                searchText: $displayCurrencySearchText,
                selectedCodes: favoriteCodes,
                favoriteCodes: Set(favoriteCodes),
                currentSelection: viewModel.state.displayCurrency,
                primaryPinnedCode: SettingsManager.shared.primaryCurrencyCode,
                onToggleFavorite: nil,
                badgeForCode: { code in
                    guard CurrencySelectionSupport.isCrypto(code), !canUseCrypto else { return nil }
                    return .pro
                },
                onSelect: { code in
                    if CurrencySelectionSupport.isCrypto(code), !canUseCrypto {
                        showSubscriptionSheet = true
                        return
                    }
                    viewModel.handle(.setDisplayCurrency(code))
                    displayCurrencySearchText = ""
                    showDisplayCurrencySheet = false
                }
            )
            .safeAreaInset(edge: .top) {
                if showDisplayCurrencyInfoBanner {
                    displayCurrencyInfoBanner(message: displayCurrencyInfoMessage)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
            .navigationTitle(L("finances.dynamics.currency.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDisplayCurrencyInfoAlert = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("finances.common.cancel")) {
                        displayCurrencySearchText = ""
                        showDisplayCurrencySheet = false
                    }
                }
            }
            .onAppear {
                if !hasSeenDisplayCurrencyHint {
                    showDisplayCurrencyInfoBanner = true
                    hasSeenDisplayCurrencyHint = true
                }
            }
            .alert(L("finances.dynamics.currency.hint.title"), isPresented: $showDisplayCurrencyInfoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(displayCurrencyInfoMessage)
            }
        }
        .presentationDetents([.large])
    }

    private var displayedPeriodDates: (start: Date, end: Date) {
        let stateStart = viewModel.state.periodStartDate
        let stateEnd = viewModel.state.periodEndDate
        if stateEnd >= stateStart {
            return (stateStart, stateEnd)
        }
        return viewModel.getPeriodDates()
    }

    private var displayCurrencyInfoMessage: String {
        L("finances.display_currency.hint.message")
    }

    private func displayCurrencyInfoBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            Button {
                showDisplayCurrencyInfoBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("finances.dynamics.currency.hint.dismiss_accessibility"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        let selectedFill = Color.white.opacity(0.10)
        let quietFill = Color.white.opacity(0.05)
        return HStack(spacing: 6) {
            // Кнопки периодов
            ForEach([DynamicsPeriod.day, .week, .month, .year, .all], id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.handle(.setPeriod(period))
                        useCustomPeriod = false
                    }
                    cachedSelectedPoint = nil
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 13, weight: .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(period == viewModel.state.period && !useCustomPeriod ? selectedFill : quietFill)
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    period == viewModel.state.period && !useCustomPeriod
                                        ? CalendarRangeTheme.finances.ringColor.opacity(0.9)
                                        : Color.white.opacity(0.14),
                                    lineWidth: period == viewModel.state.period && !useCustomPeriod ? 1.2 : 1
                                )
                        )
                        .foregroundStyle(
                            period == viewModel.state.period && !useCustomPeriod
                                ? AppColors.textPrimary
                                : AppColors.textSecondary
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 48, height: 32)
            }

            // Кнопка календаря
            Button {
                draftStartDate = customStartDate
                draftEndDate = customEndDate
                showCustomPeriodSheet = true
            } label: {
                Image("calendar")
                    .frame(width: 18, height: 18)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(
                        Capsule()
                            .fill(useCustomPeriod ? selectedFill : quietFill)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        useCustomPeriod
                                            ? CalendarRangeTheme.finances.ringColor.opacity(0.9)
                                            : Color.white.opacity(0.14),
                                        lineWidth: useCustomPeriod ? 1.2 : 1
                                    )
                            )
                    )
                    .foregroundStyle(useCustomPeriod ? AppColors.textPrimary : AppColors.textSecondary)
            }
            .buttonStyle(.plain)

        }
        .frame(maxWidth: .infinity)
//        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Chart Type Toggle

    private var chartTypeToggle: some View {
        let currentType = viewModel.state.selectedChartType
        let icon: String = {
            switch currentType {
            case .line: return "chart.line.uptrend.xyaxis"
            case .distribution: return "chart.pie"
            case .currencyDistribution: return "dollarsign.circle"
            }
        }()
        return Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.handle(.setChartViewType(.line))
                }
            } label: {
                Label(L("finances.dynamics.chart_type.line"), systemImage: "chart.line.uptrend.xyaxis")
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.handle(.setChartViewType(.distribution))
                }
            } label: {
                Label(L("finances.dynamics.chart_type.distribution"), systemImage: "chart.pie")
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.handle(.setChartViewType(.currencyDistribution))
                }
            } label: {
                Label(L("finances.dynamics.chart_type.currency"), systemImage: "dollarsign.circle")
            }
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .frame(width: 18, height: 18)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
        }
        .frame(height: 32)
    }

    // MARK: - Custom Period Sheet

    private var customPeriodSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                CalendarRangePickerPanel(
                    title: CalendarRangePickerCopy.sheetTitle(locale: locale),
                    subtitle: L("finances.dynamics.custom_period.subtitle"),
                    startDate: $draftStartDate,
                    endDate: $draftEndDate,
                    theme: .finances
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ToolbarGlassIconButton(
                        systemName: "xmark",
                        accessibilityLabel: L("cashflow.common.dismiss")
                    ) {
                        showCustomPeriodSheet = false
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                CalendarRangeSheetActionBar(
                    secondaryTitle: L("finances.common.reset"),
                    primaryTitle: L("finances.dynamics.custom_period.show"),
                    theme: .finances
                ) {
                        draftStartDate = Date()
                        draftEndDate = Date()
                        customStartDate = draftStartDate
                        customEndDate = draftEndDate
                        useCustomPeriod = false
                        viewModel.handle(.setPeriod(.month))
                        cachedSelectedPoint = nil
                        showCustomPeriodSheet = false
                } primaryAction: {
                        let start = min(draftStartDate, draftEndDate)
                        let end = max(draftStartDate, draftEndDate)
                        let clampedEnd = min(end, Date())
                        let clampedStart = min(start, clampedEnd)
                        customStartDate = clampedStart
                        customEndDate = clampedEnd
                        useCustomPeriod = true
                        viewModel.handle(.setCustomPeriod(start: clampedStart, end: clampedEnd))
                        cachedSelectedPoint = nil
                        showCustomPeriodSheet = false
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    // MARK: - Dynamics List Card

    private var dynamicsListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Панель с фильтром и переключателем
            if !viewModel.state.isSingleAccountMode {
                HStack(spacing: 12) {
                    Button {
                        viewModel.handle(.showFilterSheet)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.07))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    dynamicsSegmentedControl
                }
            }

            // Блок таблицы
            if viewModel.state.dynamicsBreakdown.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(dynamicsCardBackground)
            } else {
                LazyVStack(spacing: 0) {
                    // Заголовок таблицы — только при раскрытом состоянии
                    if isBreakdownExpanded {
                        tableHeader
                    }

                    // Итого — всегда видна, тап раскрывает/скрывает список
                    if let total = totalRow {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isBreakdownExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 0) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                                    .rotationEffect(.degrees(isBreakdownExpanded ? 90 : 0))
                                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isBreakdownExpanded)
                                    .frame(width: 20)
                                totalRowView(total)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.horizontal, 16)
                    }

                    // Строки данных — только при раскрытом состоянии
                    if isBreakdownExpanded {
                        ForEach(viewModel.state.dynamicsBreakdown) { item in
                            rowView(item)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.vertical, 12)
                .background(dynamicsCardBackground)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.state.viewMode == .groups ? "folder.fill" : "creditcard.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.textSecondary.opacity(0.5))
            
            VStack(spacing: 6) {
                Text(
                    viewModel.state.viewMode == .groups
                        ? L("finances.dynamics.empty.groups.title")
                        : L("finances.dynamics.empty.products.title")
                )
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.textPrimary)

                if viewModel.state.viewMode != .groups {
                    Text(L("finances.dynamics.empty.products.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Table Header

    private var tableHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 12)
                Text(L("finances.dynamics.table.start"))
                    .font(.caption2).foregroundStyle(AppColors.textSecondary)
                    .frame(width: 92, alignment: .trailing)
                Text(L("finances.dynamics.table.end"))
                    .font(.caption2).foregroundStyle(AppColors.textSecondary)
                    .frame(width: 92, alignment: .trailing)
            }
            .padding(.vertical, 4)
            Divider()
                .overlay(Color.white.opacity(0.2))
                .padding(.horizontal, 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var dynamicsSegmentedControl: some View {
        return Picker(L("finances.dynamics.view_mode.title"), selection: dynamicsViewModeSelection) {
            Text(L("finances.dynamics.view_mode.groups")).tag(0)
            Text(L("finances.dynamics.view_mode.accounts")).tag(1)
        }
        .pickerStyle(.segmented)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        )
    }

    private var dynamicsViewModeSelection: Binding<Int> {
        Binding {
            viewModel.state.viewMode == .groups ? 0 : 1
        } set: { value in
            viewModel.handle(.setViewMode(value == 0 ? .groups : .accounts))
        }
    }

    // MARK: - Groups Donut Card

    private var groupsDonutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("finances.dynamics.chart_type.distribution"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.75, green: 0.60, blue: 1.00))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            DistributionChartView(
                items: viewModel.state.dynamicsBreakdown,
                currency: viewModel.state.displayCurrency,
                isAmountHidden: isAmountHidden
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(distributionCardBackground)
    }

    // MARK: - Currency Breakdown Card

    private var currencyBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("finances.dynamics.chart_type.currency"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 1.00, green: 0.72, blue: 0.30))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            CurrencyDistributionChartView(
                items: viewModel.state.currencyBreakdown,
                displayCurrency: viewModel.state.displayCurrency,
                isAmountHidden: isAmountHidden
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(currencyCardBackground)
    }

    private var distributionCardBackground: some View {
        let accentColor = Color(red: 0.75, green: 0.47, blue: 1.00)
        let fillGradient = LinearGradient(
            colors: [Color(white: 0.08), Color(white: 0.04), Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: [accentColor.opacity(0.10), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accentColor.opacity(0.28), lineWidth: 0.9)
            )
    }

    private var currencyCardBackground: some View {
        let accentColor = Color(red: 1.00, green: 0.72, blue: 0.30)
        let fillGradient = LinearGradient(
            colors: [Color(white: 0.08), Color(white: 0.04), Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: [accentColor.opacity(0.10), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accentColor.opacity(0.28), lineWidth: 0.9)
            )
    }

    private var dynamicsCardBackground: some View {
        let accentColor = AppColors.financesGradient.first ?? .cyan
        let fillGradient = LinearGradient(
            colors: [
                Color(white: 0.08),
                Color(white: 0.04),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let glowGradient = LinearGradient(
            colors: [
                accentColor.opacity(0.06),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(glowGradient)
                    .opacity(0.45)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            )
    }

    // MARK: - Row Views

    @ViewBuilder
    private func rowView(_ item: DynamicsBreakdownItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Иконка (для счетов)
                if viewModel.state.viewMode == .accounts, let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            (item.accountType == .credit || item.isCreditCard)
                                ? LinearGradient(colors: [AppColors.error, AppColors.error], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 20, height: 20)
                } else if viewModel.state.viewMode == .groups,
                          let group = dynamicsGroup(for: item),
                          let customIcon = group.customIconName {
                    // Только кастомная иконка группы — при nil breakdown-строка остаётся без иконки
                    // (поведение по умолчанию не меняется).
                    AccountIconBadgeView(
                        iconName: customIcon,
                        iconColor: group.colorHex,
                        fallback: "square.grid.2x2.fill",
                        size: AppSpacing.xl
                    )
                }

                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(AppColors.textPrimary)
                
                if item.isArchived {
                    Text(L("finances.dynamics.archived_badge"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(formatBalance(item.startValue))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 92, alignment: .trailing)
                        Text(formatBalance(item.endValue))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 92, alignment: .trailing)
                    }

                    if !viewModel.state.isSingleAccountMode {
                        let badgeColor = deltaColor(for: item)
                        let badgeBg = deltaBackground(for: item)
                        // Near-zero база → процент не определён: показываем только дельту, без «•» и процента.
                        let badgeText = item.deltaPercent.map {
                            "\(formatDelta(item.delta))  •  \(formatPercent($0))"
                        } ?? formatDelta(item.delta)
                        Text(badgeText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(badgeBg))
                            .foregroundStyle(badgeColor)
                            .fixedSize()
                    }
                }
            }
        }
        .listRowSeparator(.visible)
        .onLongPressGesture(minimumDuration: 0.45) {
            guard let group = dynamicsGroup(for: item) else { return }
            financeViewModel.handle(.showGroupDynamics(group))
        }
    }

    @ViewBuilder
    private func totalRowView(_ item: DynamicsBreakdownItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(formatBalance(item.startValue))
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 92, alignment: .trailing)
                        Text(formatBalance(item.endValue))
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 92, alignment: .trailing)
                    }

                    if !viewModel.state.isSingleAccountMode {
                        let badgeColor = deltaColor(for: item)
                        let badgeBg = deltaBackground(for: item)
                        // Near-zero база → процент не определён: показываем только дельту, без «•» и процента.
                        let badgeText = item.deltaPercent.map {
                            "\(formatDelta(item.delta))  •  \(formatPercent($0))"
                        } ?? formatDelta(item.delta)
                        Text(badgeText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(badgeBg))
                            .foregroundStyle(badgeColor)
                            .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - Total Row

    private var totalRow: DynamicsBreakdownItem? {
        // Unscoped-агрегат: карточка «Общая сумма» = концы единой серии (заголовок), а не повторный
        // reduce по breakdown — единый источник числа (AC1). Scoped/scrub → reduce по breakdown.
        if let aggregate = viewModel.aggregateTotalRow() {
            return aggregate
        }
        return FinanceDynamicsPresentation.totalRow(
            from: viewModel.state.dynamicsBreakdown,
            viewMode: viewModel.state.viewMode
        )
    }

    private func dynamicsGroup(for item: DynamicsBreakdownItem) -> AccountGroup? {
        guard viewModel.state.viewMode == .groups, item.id != "total" else { return nil }
        return financeViewModel.state.groups.first { $0.groupUniqueID == item.id }
    }

    // MARK: - Blocked/Empty Views

    private func proBlockedView(size: ProChartUpsellMetrics.Size) -> some View {
        ProChartUpsellView(
            titleKey: nil,
            subtitleKey: nil,
            ctaKey: "finances.dynamics.pro.cta",
            size: size,
            onTapCTA: { showSubscriptionSheet = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func proBlockedDonutCard(titleKey: LocalizedStringKey, accentColor: Color) -> some View {
        let fillGradient = LinearGradient(
            colors: [Color(white: 0.08), Color(white: 0.04), Color.black],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        return VStack(alignment: .leading, spacing: 0) {
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ZStack {
                FakeDonutBackground(accentColor: accentColor)
                    .blur(radius: 8)
                    .clipped()
                    .overlay(Color.black.opacity(0.6))

                Button(action: { showSubscriptionSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L("finances.dynamics.pro.cta"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().stroke(accentColor.opacity(0.7), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(fillGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(
                            colors: [accentColor.opacity(0.10), Color.clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accentColor.opacity(0.28), lineWidth: 0.9)
                )
        )
    }

    private var emptyChartView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text(L("finances.dynamics.empty.chart"))
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var xAxisStride: Calendar.Component {
        switch viewModel.state.period {
        case .day: return .hour
        case .week: return .day
        case .month: return .day
        case .year: return .month
        case .all, .custom: return .month
        }
    }

    private var xAxisCount: Int {
        switch viewModel.state.period {
        case .day: return 6
        case .week: return 1
        case .month: return 7
        case .year: return 2
        case .all, .custom: return 3
        }
    }

    private func formatBalance(_ balance: Double) -> String {
        if isAmountHidden {
            return FinanceAmountText.maskedDigits(for: balance)
        }

        return FinanceAmountText.decimal(value: balance)
    }

    private func formatDelta(_ delta: Double) -> String {
        if isAmountHidden {
            return FinanceAmountText.maskedDigits(for: delta)
        }

        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(formatBalance(delta))"
    }

    private func formatPercent(_ percent: Double) -> String {
        FinanceAmountText.percent(value: percent, isHidden: isAmountHidden)
    }

    private func deltaColor(for item: DynamicsBreakdownItem) -> Color {
        let positiveText = Color(.sRGB, red: 127.0 / 255.0, green: 1.0, blue: 189.0 / 255.0, opacity: 1.0)
        let negativeText = Color(.sRGB, red: 1.0, green: 0.37, blue: 0.37, opacity: 1.0)
        let neutralText = Color(.sRGB, red: 181.0 / 255.0, green: 181.0 / 255.0, blue: 181.0 / 255.0, opacity: 1.0)
        if item.accountType == .credit || item.isCreditCard {
            // Для долгов: уменьшение = хорошо (зелёный), рост = плохо (красный)
            let startAbs = abs(item.startValue)
            let endAbs = abs(item.endValue)
            if endAbs < startAbs { return positiveText }
            if endAbs > startAbs { return negativeText }
            return neutralText
        } else {
            if item.delta > 0 { return positiveText }
            if item.delta < 0 { return negativeText }
            return neutralText
        }
    }

    private func deltaBackground(for item: DynamicsBreakdownItem) -> Color {
        let positiveBg = Color(.sRGB, red: 127.0 / 255.0, green: 1.0, blue: 189.0 / 255.0, opacity: 0.3)
        let negativeBg = Color(.sRGB, red: 1.0, green: 0.37, blue: 0.37, opacity: 0.3)
        let neutralBg = Color(.sRGB, red: 181.0 / 255.0, green: 181.0 / 255.0, blue: 181.0 / 255.0, opacity: 0.3)
        if item.accountType == .credit || item.isCreditCard {
            let startAbs = abs(item.startValue)
            let endAbs = abs(item.endValue)
            if endAbs < startAbs { return positiveBg }
            if endAbs > startAbs { return negativeBg }
            return neutralBg
        } else {
            if item.delta > 0 { return positiveBg }
            if item.delta < 0 { return negativeBg }
            return neutralBg
        }
    }

}

private struct SwipeConfirmButton: View {
    let title: String
    let accentColor: Color
    let isEnabled: Bool
    let onConfirmed: () -> Void

    @State private var dragOffset: CGFloat = 0

    private let knobSize: CGFloat = 52
    private let height: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let maxOffset = max(0, width - knobSize - 10)
            let progress = max(0, min(1, dragOffset / maxOffset))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                Rectangle()
                    .fill(accentColor.opacity(0.35))
                    .frame(width: max(knobSize, dragOffset + knobSize * 0.65))
                    .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(isEnabled ? 0.95 : 0.5))
                    .frame(maxWidth: .infinity)

                Circle()
                    .fill(accentColor)
                    .frame(width: knobSize, height: knobSize)
                    .overlay(
                        Image(systemName: progress > 0.93 ? "checkmark" : "chevron.right.2")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                    )
                    .offset(x: 5 + dragOffset)
            }
            .frame(height: height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        dragOffset = min(max(0, value.translation.width), maxOffset)
                    }
                    .onEnded { _ in
                        guard isEnabled else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                dragOffset = 0
                            }
                            return
                        }
                        if progress > 0.93 {
                            onConfirmed()
                        }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            dragOffset = 0
                        }
                    }
            )
        }
        .frame(height: height)
        .opacity(isEnabled ? 1.0 : 0.55)
    }
}

// MARK: - Filter Sheet

private struct FinanceDynamicsFilterSheet: View {
    @ObservedObject var viewModel: FinanceDynamicsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var filterSearchText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        filterSearchBar

                        if !viewModel.state.isSingleGroupMode && !viewModel.state.isSingleAccountMode {
                            groupsFilterSection
                        }

                        archivedToggleSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .safeAreaInset(edge: .bottom) {
                filterApplyButton
            }
            .navigationTitle(L("finances.dynamics.filter.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { }
        }
    }

    private var filterSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            TextField(L("finances.dynamics.filter.search_placeholder"), text: $filterSearchText)
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Spacer()
            Button(L("finances.common.cancel")) {
                filterSearchText = ""
            }
            .foregroundStyle(Color(red: 0.46, green: 0.67, blue: 1.0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
    }

    private var filterApplyButton: some View {
        let gradient = LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.02, blue: 0.12),
                Color(red: 0.02, green: 0.12, blue: 0.10)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        return Button {
            dismiss()
        } label: {
            Text(L("finances.dynamics.filter.apply"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(gradient)
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var groupsFilterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                filterPrimaryButton(title: L("finances.dynamics.filter.show_all")) {
                    viewModel.handle(.selectAllGroups)
                }
                .frame(maxWidth: .infinity)

                filterSecondaryButton(title: L("finances.dynamics.filter.clear_selection")) {
                    viewModel.handle(.deselectAllGroups)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            let filteredGroups = viewModel.state.groups.filter { group in
                let q = filterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return q.isEmpty || group.name.lowercased().contains(q)
            }

            if filteredGroups.isEmpty {
                Text(L("finances.dynamics.empty.groups.title"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                VStack(spacing: 16) {
                    ForEach(filteredGroups) { group in
                        let accountsForGroup = viewModel.getAccounts(for: group).filter { account in
                            let q = filterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            guard !q.isEmpty else { return true }
                            if let info = viewModel.getAccountInfoForDynamics(account: account) {
                                return info.name.lowercased().contains(q)
                            }
                            return false
                        }
                        let selectedCount = accountsForGroup.filter { viewModel.state.selectedAccountIDs.contains($0.accountUniqueID) }.count
                        let totalCount = accountsForGroup.count

                        VStack(spacing: 0) {
                            Button {
                                viewModel.handle(.toggleGroup(group.groupUniqueID))
                            } label: {
                                HStack(spacing: 12) {
                                    filterCheckbox(isSelected: viewModel.state.selectedGroupIDs.contains(group.groupUniqueID))
                                    Text(group.name)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    Text("\(selectedCount)/\(max(totalCount, 1))")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)
                                    Image(systemName: "folder")
                                        .font(.system(size: 18))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .overlay(Color.white.opacity(0.12))
                                .padding(.horizontal, 16)

                            VStack(spacing: 0) {
                                ForEach(Array(accountsForGroup.enumerated()), id: \.element.id) { index, account in
                                    if let accountInfo = viewModel.getAccountInfoForDynamics(account: account) {
                                        Button {
                                            viewModel.handle(.toggleAccount(account.accountUniqueID))
                                        } label: {
                                            HStack(spacing: 12) {
                                                filterCheckbox(isSelected: viewModel.state.selectedAccountIDs.contains(account.accountUniqueID))
                                                Text(accountInfo.name)
                                                    .font(.system(size: 16, weight: .regular))
                                                    .foregroundStyle(AppColors.textPrimary)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                        }
                                        .buttonStyle(.plain)

                                        if index != accountsForGroup.count - 1 {
                                            Divider()
                                                .overlay(Color.white.opacity(0.12))
                                                .padding(.horizontal, 16)
                                        }
                                    }
                                }
                            }
                        }
                        .background(filterCardBackground)
                    }
                }
            }
        }
    }

    private var archivedToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("finances.dynamics.filter.archive_section"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            Toggle(L("finances.dynamics.filter.show_archived_accounts"), isOn: Binding(
                get: { viewModel.state.showArchivedAccounts },
                set: { viewModel.handle(.setShowArchivedAccounts($0)) }
            ))
            .tint(.blue)
        }
        .padding(20)
        .background(
            filterCardBackground
        )
    }

    private var filterCardBackground: some View {
        let accentColor = AppColors.financesGradient.first ?? .cyan
        let fillGradient = LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.07, blue: 0.11),
                Color(red: 0.02, green: 0.04, blue: 0.06),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let glowGradient = LinearGradient(
            colors: [
                accentColor.opacity(0.18),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(glowGradient)
                    .opacity(0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    private func filterPrimaryButton(title: String, action: @escaping () -> Void) -> some View {
        let gradient = LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.02, blue: 0.12),
                Color(red: 0.02, green: 0.12, blue: 0.10)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        return Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(gradient)
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func filterSecondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func filterCheckbox(isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.8), lineWidth: 1.2)
                .frame(width: 22, height: 22)
            if isSelected {
                Circle()
                    .fill(Color(red: 0.46, green: 0.67, blue: 1.0))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Scroll Offset Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Deposit Forecast View (Phase 5 + 8)

private struct DepositForecastView: View {
    let deposit: Investment
    let rate: Double

    private var cap: DepositCapitalization {
        DepositCapitalization(rawValue: deposit.depositCapitalizationRaw) ?? .none
    }
    private var amount: Double { deposit.amount }
    private var currency: String { deposit.currency }

    private var monthlyIncome: Double {
        switch cap {
        case .none: return (amount * rate / 100.0 / 12.0 * 100).rounded() / 100
        case .monthly:
            let m = pow(1.0 + rate / 100.0 / 12.0, 12.0) - 1.0
            return (amount * m / 12.0 * 100).rounded() / 100
        }
    }

    private var today: Date { Date() }
    private var startDate: Date { deposit.depositStartDate ?? today }

    private var elapsedMonths: Int {
        max(0, Calendar.current.dateComponents([.month], from: startDate, to: today).month ?? 0)
    }

    private var termMonths: Int? {
        deposit.depositEndDate.map {
            max(0, Calendar.current.dateComponents([.month], from: startDate, to: $0).month ?? 0)
        }
    }

    private var totalIncome: Double? {
        termMonths.map { months in
            switch cap {
            case .none: return monthlyIncome * Double(months)
            case .monthly: return amount * (pow(1.0 + rate / 100.0 / 12.0, Double(months)) - 1.0)
            }
        }
    }

    private var earnedSoFar: Double {
        switch cap {
        case .none: return monthlyIncome * Double(elapsedMonths)
        case .monthly: return amount * (pow(1.0 + rate / 100.0 / 12.0, Double(elapsedMonths)) - 1.0)
        }
    }

    private var remaining: Double? { totalIncome.map { $0 - earnedSoFar } }

    private func nextPaymentDate() -> Date {
        var candidate = startDate
        while candidate <= today {
            candidate = Calendar.current.date(byAdding: .month, value: 1, to: candidate) ?? today
        }
        return candidate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.deposit.forecast.section_title"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    row(label: L("finances.deposit.forecast.rate"),
                        value: "\(String(format: "%.2g", rate))%")
                    FinancesRowDivider()
                    row(label: L("finances.deposit.forecast.monthly"),
                        value: "\(String(format: "%.2f", monthlyIncome)) \(currency)")

                    if let total = totalIncome {
                        FinancesRowDivider()
                        row(label: L("finances.deposit.forecast.total"),
                            value: "\(String(format: "%.2f", total)) \(currency)")
                    }

                    FinancesRowDivider()
                    row(label: L("finances.deposit.forecast.earned"),
                        value: "\(String(format: "%.2f", earnedSoFar)) \(currency)")

                    if let rem = remaining {
                        FinancesRowDivider()
                        row(label: L("finances.deposit.forecast.remaining"),
                            value: "\(String(format: "%.2f", rem)) \(currency)")
                    }

                    if deposit.depositIncomeInCashflow {
                        FinancesRowDivider()
                        HStack {
                            Image(systemName: "calendar.badge.checkmark")
                                .foregroundStyle(AppColors.toggleOnGreen)
                                .font(.system(size: 13))
                            Text(L("finances.deposit.forecast.next_payment"))
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Text(nextPaymentDate(), style: .date)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }
}
