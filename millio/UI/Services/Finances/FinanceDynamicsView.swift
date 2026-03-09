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

struct FinanceDynamicsEstimatedRateWarningPrefs {
    static let hiddenKey = "finance_dynamics_estimated_rate_warning_hidden"

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
    static let baseScrollContentTopPadding: CGFloat = 8
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
    @State private var showTradeSheet: Bool = false
    @State private var tradeMode: InvestmentOrderSide = .buy
    @State private var tradePriceMode: TradePriceMode = .market
    @State private var tradeQuantityText: String = "1"
    @State private var tradePriceText: String = ""
    @State private var tradeErrorText: String?
    @State private var isInlineMarketEdit: Bool = false
    @State private var editQuantityText: String = ""
    @State private var editUnitPriceText: String = ""
    @State private var editPurchasePriceText: String = ""
    @State private var showFullProductEditSheet: Bool = false
    @State private var showCashflowHistory: Bool = false
    @State private var cashflowViewModel: CashflowViewModel? = nil
    @State private var isInlineAccountEdit: Bool = false
    @State private var inlineAmountText: String = ""
    @State private var inlineCreditLimitText: String = ""
    @State private var inlineCreditDebtText: String = ""
    @State private var isEstimatedRateWarningHidden: Bool = FinanceDynamicsEstimatedRateWarningPrefs().isHidden()
    @State private var showOverviewExpandedChart: Bool = false
    @State private var selectedOverviewGranularity: FinanceOverviewGranularity = .month
    @State private var selectedOverviewPeriods: [FinanceOverviewGranularity: Date] = [:]
    @State private var overviewEntriesByGranularity: [FinanceOverviewGranularity: [FinanceOverviewPeriodEntry]] = [:]
    @State private var isOverviewChartLoading: Bool = false
    @State private var showDeleteAccountConfirmation: Bool = false

    // Кэшированные значения для графика
    @State private var cachedSelectedPoint: (date: Date, value: Double)? = nil

    private enum TradePriceMode: String, CaseIterable, Hashable {
        case market
        case custom
    }

    var body: some View {
        ZStack {
            GradientBackground()

            if let marketInvestment = marketInvestment {
                marketInvestmentDetailsView(marketInvestment)
            } else {
                let isCreditCardAccount = initialAccount.map { inlineCreditCard(for: $0) != nil } ?? false
                let needsTopClearance = viewModel.state.isSingleAccountMode && isCreditCardAccount && shouldShowSingleAccountActionBar
                let scrollTopPadding = FinanceDynamicsTopBarStyle.scrollContentTopPadding(needsClearance: needsTopClearance)

                ScrollView {
                    VStack(spacing: 16) {
                        // Якорь для измерения скролла
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

                        if let warning = viewModel.state.currencyConversionWarning, !isEstimatedRateWarningHidden {
                            currencyWarningView(text: warning) {
                                isEstimatedRateWarningHidden = true
                                FinanceDynamicsEstimatedRateWarningPrefs().setHidden(true)
                            }
                        }

                        // Список динамики
                        dynamicsListCard

                        if shouldShowDeleteAccountFooter, let account = initialAccount {
                            deleteAccountFooterButton(account: account)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, scrollTopPadding)
                    .padding(.bottom, shouldShowDeleteAccountFooter ? 44 : 32)
                }
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
        .confirmationDialog(
            deleteAccountConfirmationTitle,
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "finances.common.delete"), role: .destructive) {
                guard let account = initialAccount else { return }
                financeViewModel.handle(.removeAccountFromGroup(account))
                dismiss()
            }
            Button(String(localized: "finances.common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "finances.dynamics.delete_account.confirm.message"))
        }
        .navigationTitle(viewModel.state.isSingleAccountMode ? "" : String(localized: "finances.dynamics.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(marketInvestment != nil ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if shouldShowSingleAccountActionBar, let account = initialAccount {
                ToolbarItem(placement: .navigationBarTrailing) {
                    singleAccountActionBar(account: account)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showFilterSheet },
            set: { if !$0 { viewModel.handle(.hideFilterSheet) } }
        )) {
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
        .sheet(isPresented: $showTradeSheet) {
            if let marketInvestment = marketInvestment {
                tradeSheet(for: marketInvestment)
            }
        }
        .sheet(isPresented: $showFullProductEditSheet) {
            if let account = initialAccount {
                FinanceAddAccountView(
                    viewModel: financeViewModel,
                    editingCard: resolvedCard(for: account),
                    editingCredit: resolvedCredit(for: account),
                    editingInvestment: resolvedInvestment(for: account)
                )
                .onDisappear {
                    viewModel.handle(.loadData)
                }
            }
        }
        .sheet(isPresented: $showCashflowHistory) {
            if let cashflowViewModel {
                CashflowTransactionsHistoryView(viewModel: cashflowViewModel)
            }
        }
        .onAppear {
            // Синхронизация с ViewModel при появлении
            if let customPeriod = viewModel.state.customPeriod {
                customStartDate = customPeriod.start
                customEndDate = customPeriod.end
                useCustomPeriod = viewModel.state.period == .custom
            }
            if let marketInvestment {
                syncMarketDraft(from: marketInvestment)
            }
            if cashflowViewModel == nil {
                cashflowViewModel = CashflowViewModel(modelContext: modelContext)
            }
        }
        .onChange(of: marketInvestment?.updatedAt) { _, _ in
            if let marketInvestment, !isInlineMarketEdit {
                syncMarketDraft(from: marketInvestment)
            }
        }
    }

    private var marketInvestment: Investment? {
        guard viewModel.state.isSingleAccountMode,
              let account = initialAccount else {
            return nil
        }
        return financeViewModel.getMarketInvestment(account: account)
    }

    private func marketInvestmentDetailsView(_ investment: Investment) -> some View {
        GeometryReader { proxy in
            let compactLayout = proxy.size.height < 820
            let topInset = proxy.safeAreaInsets.top

            VStack(spacing: compactLayout ? 8 : 12) {
                marketScreenTopBar(for: investment, compactLayout: compactLayout)

                FinancesGlassCard(
                    accentColor: Color.cyan.opacity(0.95),
                    cornerRadius: compactLayout ? 16 : 18,
                    contentPadding: EdgeInsets(top: compactLayout ? 10 : 14, leading: 12, bottom: compactLayout ? 10 : 14, trailing: 12)
                ) {
                    VStack(alignment: .leading, spacing: compactLayout ? 8 : 12) {
                        HStack {
                            Text(investment.marketSymbol ?? investment.name)
                                .font(.system(size: compactLayout ? 30 : 34, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                        }

                        HStack(spacing: compactLayout ? 8 : 9) {
                            RoundedRectangle(cornerRadius: compactLayout ? 14 : 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    VStack(spacing: compactLayout ? 3 : 5) {
                                        Text(
                                            FinancesL10n.format(
                                                "finances.dynamics.market.position_total_with_currency",
                                                resolvedInvestmentCurrency(investment)
                                            )
                                        )
                                            .font(.system(size: compactLayout ? 11 : 12, weight: .medium))
                                            .foregroundStyle(AppColors.textSecondary)
                                            .lineLimit(1)
                                        Text(money(investment.positionTotal ?? investment.amount, currency: resolvedInvestmentCurrency(investment)))
                                            .font(.system(size: compactLayout ? 22 : 25, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.78)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, compactLayout ? 10 : 12)
                                }
                                .frame(maxWidth: .infinity)

                            growthCard(for: investment, compactLayout: compactLayout)
                                .frame(width: compactLayout ? 106 : 118)
                        }
                        .frame(height: compactLayout ? 78 : 88)

                        Divider()
                            .overlay(Color.white.opacity(0.09))

                        Text(String(localized: "finances.dynamics.market.instrument_info"))
                            .font(.system(size: compactLayout ? 18 : 20, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: compactLayout ? 6 : 8) {
                            statCell(
                                marketQuantityTitle(for: investment),
                                "\(marketNumber(investment.marketQuantity ?? 0, digits: 8)) \(marketQuantityUnit(for: investment))",
                                isEditable: true,
                                isEditing: isInlineMarketEdit,
                                editText: $editQuantityText,
                                keyboardType: .decimalPad,
                                compactLayout: compactLayout
                            )
                            statCell(
                                FinancesL10n.format(
                                    "finances.dynamics.trade.price_with_currency",
                                    resolvedInvestmentCurrency(investment)
                                ),
                                money(investment.lastKnownUnitPrice ?? 0, currency: resolvedInvestmentCurrency(investment)),
                                isEditable: true,
                                isEditing: isInlineMarketEdit,
                                editText: $editUnitPriceText,
                                keyboardType: .decimalPad,
                                compactLayout: compactLayout
                            )
                            statCell(
                                String(localized: "finances.add_account.investment.purchase_price"),
                                money(investment.averagePurchaseUnitPrice ?? 0, currency: resolvedInvestmentCurrency(investment)),
                                isEditable: true,
                                isEditing: isInlineMarketEdit,
                                editText: $editPurchasePriceText,
                                keyboardType: .decimalPad,
                                compactLayout: compactLayout
                            )
                            statCell(
                                String(localized: "finances.dynamics.market.purchase_total"),
                                money(investment.totalPurchaseCost ?? 0, currency: resolvedInvestmentCurrency(investment)),
                                compactLayout: compactLayout
                            )
                        }

                    }
                }

                VStack(alignment: .leading, spacing: compactLayout ? 6 : 8) {
                    Text(String(localized: "finances.dynamics.market.actions"))
                        .font(.system(size: compactLayout ? 18 : 20, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    FinancesGlassCard(
                        accentColor: Color.cyan.opacity(0.95),
                        contentPadding: EdgeInsets(top: compactLayout ? 10 : 12, leading: 12, bottom: compactLayout ? 10 : 12, trailing: 12)
                    ) {
                        HStack(spacing: compactLayout ? 8 : 10) {
                            actionButton(title: String(localized: "finances.dynamics.market.action.buy"), icon: "cart.badge.plus", color: Color.green.opacity(0.88), compactLayout: compactLayout) {
                                tradeMode = .buy
                                prepareTradeDraft(for: investment)
                                showTradeSheet = true
                            }
                            actionButton(title: String(localized: "finances.dynamics.market.action.sell"), icon: "cart.badge.minus", color: Color.red.opacity(0.9), compactLayout: compactLayout) {
                                tradeMode = .sell
                                prepareTradeDraft(for: investment)
                                showTradeSheet = true
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, max(4, topInset))
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(edges: .top)
    }

    private func marketScreenTopBar(for investment: Investment, compactLayout: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: compactLayout ? 17 : 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: compactLayout ? 34 : 38, height: compactLayout ? 34 : 38)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            marketEditTopBar(for: investment)
        }
    }

    private func marketEditTopBar(for investment: Investment) -> some View {
        HStack(spacing: 8) {
            let canFinish = canFinishInlineMarketEdit(for: investment)
            if isInlineMarketEdit {
                Button {
                    if canFinish {
                        finishInlineMarketEdit(for: investment)
                    }
                } label: {
                    Image(systemName: FinanceDynamicsTopBarStyle.inlineEditorSymbol(isEditing: true))
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: FinanceDynamicsTopBarStyle.compactIconSize, weight: .regular))
                        .foregroundStyle(canFinish ? Color(red: 0.20, green: 0.92, blue: 0.49) : Color.white.opacity(0.4))
                        .frame(width: FinanceDynamicsTopBarStyle.compactButtonSide, height: FinanceDynamicsTopBarStyle.compactButtonSide)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    isInlineMarketEdit = true
                    syncMarketDraft(from: investment)
                } label: {
                        Image(systemName: FinanceDynamicsTopBarStyle.inlineEditorSymbol(isEditing: false))
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: FinanceDynamicsTopBarStyle.compactIconSize, weight: .regular))
                        .foregroundStyle(FinanceDynamicsTopBarStyle.passiveIconColor)
                            .frame(width: FinanceDynamicsTopBarStyle.compactButtonSide, height: FinanceDynamicsTopBarStyle.compactButtonSide)
                }
                .buttonStyle(.plain)
            }

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

            Divider()
                .frame(height: FinanceDynamicsTopBarStyle.compactSeparatorHeight)
                .overlay(FinanceDynamicsTopBarStyle.compactSeparatorColor)

            Button {
                showFullProductEditSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: FinanceDynamicsTopBarStyle.compactIconSize, weight: .regular))
                    .foregroundStyle(FinanceDynamicsTopBarStyle.passiveIconColor)
                    .frame(width: FinanceDynamicsTopBarStyle.compactButtonSide, height: FinanceDynamicsTopBarStyle.compactButtonSide)
            }
            .buttonStyle(.plain)
        }
    }

    private func statCell(
        _ title: String,
        _ value: String,
        isEditable: Bool = false,
        isEditing: Bool = false,
        editText: Binding<String>? = nil,
        keyboardType: UIKeyboardType = .default,
        compactLayout: Bool = false
    ) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: compactLayout ? 11 : 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if isEditable, isEditing, let editText {
                        TextField("0", text: Binding(
                            get: { AmountInputFormatter.display(editText.wrappedValue, maxFractionDigits: 8) },
                            set: { newValue in
                                editText.wrappedValue = AmountInputFormatter.sanitize(newValue, maxFractionDigits: 8)
                            }
                        ))
                        .font(.system(size: compactLayout ? 15 : 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .keyboardType(keyboardType)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    } else {
                        Text(value)
                            .font(.system(size: compactLayout ? 15 : 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .padding(10)
            }
            .overlay {
                if isEditable && isEditing {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.cyan.opacity(0.65), lineWidth: 1)
                }
            }
            .frame(height: compactLayout ? 78 : 86)
    }

    private func growthCard(for investment: Investment, compactLayout: Bool) -> some View {
        let growth = investment.positionGrowthPercent ?? 0
        let textColor: Color = growth > 0 ? .green : (growth < 0 ? .red : AppColors.textSecondary)

        return RoundedRectangle(cornerRadius: compactLayout ? 14 : 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.07),
                        Color.white.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: compactLayout ? 14 : 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .overlay {
                VStack(spacing: compactLayout ? 3 : 5) {
                    Text(String(localized: "finances.dynamics.growth"))
                        .font(.system(size: compactLayout ? 13 : 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                    Text(formatPercent(growth))
                        .font(.system(size: compactLayout ? 17 : 18, weight: .semibold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .padding(.horizontal, 6)
            }
    }

    private func actionButton(
        title: String,
        icon: String,
        color: Color,
        compactLayout: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: compactLayout ? 5 : 6) {
                Circle()
                    .fill(color)
                    .frame(width: compactLayout ? 46 : 52, height: compactLayout ? 46 : 52)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: compactLayout ? 18 : 20, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                Text(title)
                    .font(.system(size: compactLayout ? 15 : 16, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func tradeSheet(for investment: Investment) -> some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        Picker(String(localized: "finances.dynamics.trade.mode"), selection: $tradeMode) {
                            Text(String(localized: "finances.dynamics.market.action.buy")).tag(InvestmentOrderSide.buy)
                            Text(String(localized: "finances.dynamics.market.action.sell")).tag(InvestmentOrderSide.sell)
                        }
                        .pickerStyle(.segmented)

                        FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
                            VStack(spacing: 12) {
                                Picker(String(localized: "finances.dynamics.trade.price_mode"), selection: $tradePriceMode) {
                                    Text(String(localized: "finances.dynamics.trade.price_mode.market")).tag(TradePriceMode.market)
                                    Text(String(localized: "finances.dynamics.trade.price_mode.custom")).tag(TradePriceMode.custom)
                                }
                                .pickerStyle(.segmented)

                                tradeRow(
                                    title: FinancesL10n.format(
                                        "finances.dynamics.trade.price_with_currency",
                                        resolvedInvestmentCurrency(investment)
                                    ),
                                    valueText: Binding(
                                        get: { tradePriceMode == .market ? money(investment.lastKnownUnitPrice ?? 0, currency: resolvedInvestmentCurrency(investment)) : AmountInputFormatter.display(tradePriceText) },
                                        set: { newValue in tradePriceText = AmountInputFormatter.sanitize(newValue) }
                                    ),
                                    editable: tradePriceMode == .custom
                                )
                                tradeRow(
                                    title: marketQuantityTitle(for: investment),
                                    valueText: Binding(
                                        get: { AmountInputFormatter.display(tradeQuantityText, maxFractionDigits: 8) },
                                        set: { newValue in tradeQuantityText = AmountInputFormatter.sanitize(newValue, maxFractionDigits: 8) }
                                    ),
                                    editable: true
                                )

                                let qty = AmountInputFormatter.parse(tradeQuantityText) ?? 0
                                let price = currentTradeUnitPrice(for: investment)
                                tradeRow(
                                    title: FinancesL10n.format(
                                        "finances.dynamics.trade.total_with_currency",
                                        resolvedInvestmentCurrency(investment)
                                    ),
                                    valueText: .constant(money(qty * price, currency: resolvedInvestmentCurrency(investment))),
                                    editable: false
                                )
                            }
                        }

                        if let tradeErrorText, !tradeErrorText.isEmpty {
                            Text(tradeErrorText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        SwipeConfirmButton(
                            title: tradeMode == .buy
                                ? String(localized: "finances.dynamics.trade.swipe.buy")
                                : String(localized: "finances.dynamics.trade.swipe.sell"),
                            accentColor: tradeMode == .buy ? Color.green : Color.red,
                            isEnabled: canSubmitTrade(for: investment),
                            onConfirmed: {
                                submitTrade(for: investment)
                            }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(String(localized: "finances.dynamics.trade.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTradeSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func tradeRow(title: String, valueText: Binding<String>, editable: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            if editable {
                TextField("0", text: valueText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: 170)
            } else {
                Text(valueText.wrappedValue)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 10)
    }

    private func prepareTradeDraft(for investment: Investment) {
        tradeErrorText = nil
        tradeQuantityText = "1"
        if let lastPrice = investment.lastKnownUnitPrice {
            tradePriceText = String(lastPrice)
        } else {
            tradePriceText = ""
        }
        tradePriceMode = .market
    }

    private func currentTradeUnitPrice(for investment: Investment) -> Double {
        switch tradePriceMode {
        case .market:
            return investment.lastKnownUnitPrice ?? 0
        case .custom:
            return AmountInputFormatter.parse(tradePriceText) ?? 0
        }
    }

    private func canSubmitTrade(for investment: Investment) -> Bool {
        let quantity = AmountInputFormatter.parse(tradeQuantityText) ?? 0
        let unitPrice = currentTradeUnitPrice(for: investment)
        guard quantity > 0, unitPrice > 0 else {
            return false
        }
        if tradeMode == .sell {
            let available = investment.marketQuantity ?? 0
            return quantity <= available
        }
        return true
    }

    private func submitTrade(for investment: Investment) {
        let quantity = AmountInputFormatter.parse(tradeQuantityText) ?? 0
        let unitPrice = currentTradeUnitPrice(for: investment)
        guard quantity > 0, unitPrice > 0 else {
            tradeErrorText = String(localized: "finances.dynamics.trade.error.invalid_inputs")
            return
        }

        if tradeMode == .sell, quantity > (investment.marketQuantity ?? 0) {
            tradeErrorText = String(localized: "finances.dynamics.trade.error.insufficient_quantity")
            return
        }

        tradeErrorText = nil
        if let account = initialAccount {
            financeViewModel.handle(
                .executeInvestmentOrder(
                    account: account,
                    side: tradeMode,
                    quantity: quantity,
                    unitPrice: unitPrice
                )
            )
        }
        showTradeSheet = false
    }

    private func resolvedInvestmentCurrency(_ investment: Investment) -> String {
        let code = investment.currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !code.isEmpty { return code }
        if let marketCurrency = investment.marketCurrency?.trimmingCharacters(in: .whitespacesAndNewlines),
           !marketCurrency.isEmpty {
            return marketCurrency.uppercased()
        }
        return viewModel.state.displayCurrency
    }

    private func money(_ value: Double, currency: String) -> String {
        let number = marketNumber(value, digits: 2)
        return "\(number) \(currency)"
    }

    private func marketQuantityTitle(for investment: Investment) -> String {
        investment.category == .crypto
            ? String(localized: "finances.market.field_quantity_coins")
            : String(localized: "finances.market.field_quantity")
    }

    private func marketQuantityUnit(for investment: Investment) -> String {
        investment.category == .crypto
            ? String(localized: "finances.quick_edit.unit.coins_short")
            : String(localized: "finances.investment.unit.shares_short")
    }

    private func marketNumber(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func syncMarketDraft(from investment: Investment) {
        editQuantityText = rawNumberString(investment.marketQuantity ?? 0, maxFractionDigits: 8)
        editUnitPriceText = rawNumberString(investment.lastKnownUnitPrice ?? 0, maxFractionDigits: 8)
        editPurchasePriceText = rawNumberString(investment.averagePurchaseUnitPrice ?? 0, maxFractionDigits: 8)
    }

    private func canFinishInlineMarketEdit(for investment: Investment) -> Bool {
        guard isInlineMarketEdit else {
            return true
        }
        guard let quantity = AmountInputFormatter.parse(editQuantityText),
              let unitPrice = AmountInputFormatter.parse(editUnitPriceText),
              quantity > 0, unitPrice > 0 else {
            return false
        }

        if let purchasePrice = AmountInputFormatter.parse(editPurchasePriceText), purchasePrice < 0 {
            return false
        }

        return true
    }

    private func finishInlineMarketEdit(for investment: Investment) {
        guard canFinishInlineMarketEdit(for: investment),
              let quantity = AmountInputFormatter.parse(editQuantityText),
              let unitPrice = AmountInputFormatter.parse(editUnitPriceText) else {
            return
        }

        let purchasePrice = AmountInputFormatter.parse(editPurchasePriceText)
        if let account = initialAccount {
            financeViewModel.handle(
                .updateMarketInvestmentDetails(
                    account: account,
                    quantity: quantity,
                    unitPrice: unitPrice,
                    purchaseUnitPrice: purchasePrice
                )
            )
        }
        isInlineMarketEdit = false
    }

    private func rawNumberString(_ value: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "0"
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

        async let weekEntries = viewModel.buildOverviewEntries(granularity: .week)
        async let monthEntries = viewModel.buildOverviewEntries(granularity: .month)
        async let yearEntries = viewModel.buildOverviewEntries(granularity: .year)

        overviewEntriesByGranularity = [
            .week: await weekEntries,
            .month: await monthEntries,
            .year: await yearEntries
        ]
        isOverviewChartLoading = false
    }

    private var financeOverviewChartSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(String(localized: "finances.overview.chart.title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button {
                    showOverviewExpandedChart = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(localized: "finances.overview.chart.full"))
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
            .navigationTitle(String(localized: "finances.overview.chart.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "cashflow.common.dismiss")) {
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
                title: String(localized: "finances.overview.chart.credit"),
                value: presentation.selectedBar.credit,
                accent: AppColors.error,
                compact: compact
            )
            financeOverviewSummaryCard(
                title: String(localized: "finances.overview.chart.debit"),
                value: presentation.selectedBar.debit,
                accent: Color(red: 0.38, green: 0.96, blue: 0.71),
                compact: compact
            )
            financeOverviewSummaryCard(
                title: String(localized: "finances.overview.chart.saldo"),
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
                            Text(String(localized: "finances.overview.chart.credit"))
                                .foregroundStyle(AppColors.textSecondary)
                            Text(String(localized: "finances.overview.chart.debit"))
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
            Text(String(localized: "finances.overview.chart.empty"))
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
                            get: { AmountInputFormatter.display(inlineAmountText) },
                            set: { inlineAmountText = AmountInputFormatter.sanitize($0) }
                        )
                        HStack(spacing: 6) {
                            TextField("0", text: editText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            Text(symbol)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    } else {
                        Button {
                            showDisplayCurrencySheet = true
                        } label: {
                            Text("\(formatBalance(viewModel.state.currentBalance)) \(symbol)")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Бейдж с дельтой (скрываем для detail-режима не-акций)
                if viewModel.state.chartData.count >= 2 && !isSingleAccountSummaryMode && !(viewModel.state.isSingleAccountMode && marketInvestment == nil) {
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
                        Text(formatPercent(delta.percent))
                            .font(.caption.weight(.semibold))
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
            let (startDate, endDate) = viewModel.getPeriodDates()
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
                return String(localized: "finances.dynamics.chart.account_fallback")
            }
            return accountInfo.name
        }()

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                VStack(spacing: 5) {
                    Text("\(accountName), \(symbol)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)

                    Text("\(formatBalance(viewModel.state.currentBalance)) \(symbol)")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        .frame(height: 88)
    }

    private var shouldShowSingleAccountActionBar: Bool {
        viewModel.state.isSingleAccountMode && initialAccount != nil && marketInvestment == nil
    }

    private var shouldShowDeleteAccountFooter: Bool {
        viewModel.state.isSingleAccountMode && initialAccount != nil && marketInvestment == nil
    }

    private var deleteAccountConfirmationTitle: String {
        guard let account = initialAccount else {
            return String(localized: "finances.dynamics.delete_account")
        }
        let name = financeViewModel.getAccountInfo(account: account)?.name
            ?? String(localized: "finances.dynamics.chart.account_fallback")
        return FinancesL10n.format("finances.dynamics.delete_account.confirm.title", name)
    }

    private func deleteAccountFooterButton(account: FinanceAccount) -> some View {
        Button(role: .destructive) {
            showDeleteAccountConfirmation = true
        } label: {
            Text(String(localized: "finances.dynamics.delete_account"))
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

            Divider()
                .frame(height: FinanceDynamicsTopBarStyle.compactSeparatorHeight)
                .overlay(FinanceDynamicsTopBarStyle.compactSeparatorColor)

            Button {
                showFullProductEditSheet = true
            } label: {
                Image(systemName: "gearshape")
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

    private func resolvedCard(for account: FinanceAccount) -> Card? {
        guard account.accountType == .card else { return nil }
        return financeViewModel.state.availableCards.first(where: { $0.cardUniqueID == account.accountID })
    }

    private func resolvedCredit(for account: FinanceAccount) -> Credit? {
        guard account.accountType == .credit else { return nil }
        return financeViewModel.state.availableCredits.first(where: { $0.creditUniqueID == account.accountID })
    }

    private func resolvedInvestment(for account: FinanceAccount) -> Investment? {
        guard account.accountType == .investment else { return nil }
        return financeViewModel.state.availableInvestments.first(where: { $0.investmentUniqueID == account.accountID })
    }

    private func startInlineAccountEdit(for account: FinanceAccount) {
        if let card = inlineCreditCard(for: account) {
            inlineCreditLimitText = rawNumberString(card.creditLimit ?? 0, maxFractionDigits: 2)
            let debt = max(0, (card.creditLimit ?? 0) - card.balance)
            inlineCreditDebtText = rawNumberString(debt, maxFractionDigits: 2)
        } else if let info = financeViewModel.getAccountInfo(account: account) {
            inlineAmountText = rawNumberString(info.amount, maxFractionDigits: 2)
        }
        isInlineAccountEdit = true
    }

    private func finishInlineAccountEdit(for account: FinanceAccount) {
        guard canSaveInlineAccountEdit(for: account) else { return }
        if inlineCreditCard(for: account) != nil {
            let limit = AmountInputFormatter.parse(inlineCreditLimitText) ?? 0
            let debt = AmountInputFormatter.parse(inlineCreditDebtText) ?? 0
            financeViewModel.handle(.updateCreditCardQuickFields(account: account, creditLimit: limit, debt: debt))
        } else {
            let amount = AmountInputFormatter.parse(inlineAmountText) ?? 0
            financeViewModel.handle(.updateAccountAmount(account, amount))
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
                    title: String(localized: "finances.add_account.card.credit_limit"),
                    value: limit,
                    currency: info.currency,
                    isEditing: isInlineAccountEdit,
                    text: Binding(
                        get: { AmountInputFormatter.display(inlineCreditLimitText) },
                        set: { inlineCreditLimitText = AmountInputFormatter.sanitize($0) }
                    )
                )
                creditFieldRow(
                    title: String(localized: "finances.add_account.card.total_debt"),
                    value: debt,
                    currency: info.currency,
                    isEditing: isInlineAccountEdit,
                    text: Binding(
                        get: { AmountInputFormatter.display(inlineCreditDebtText) },
                        set: { inlineCreditDebtText = AmountInputFormatter.sanitize($0) }
                    )
                )
                creditFieldRow(
                    title: String(localized: "finances.add_account.card.remaining_limit"),
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
        let (startDate, endDate) = viewModel.getPeriodDates()
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
            onSelectPoint: { newPoint in
                if let pt = newPoint {
                    cachedSelectedPoint = (date: pt.0, value: pt.1)
                } else {
                    cachedSelectedPoint = nil
                }
            }
        )
    }

    private var displayCurrencySheet: some View {
        let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
        return NavigationStack {
            CurrencyPickerView(
                allCodes: viewModel.state.availableCurrencies.isEmpty
                    ? CurrencySelectionSupport.allCurrencyCodesForPicker
                    : viewModel.state.availableCurrencies,
                searchText: $displayCurrencySearchText,
                selectedCodes: favoriteCodes,
                favoriteCodes: Set(favoriteCodes),
                currentSelection: viewModel.state.displayCurrency,
                primaryPinnedCode: SettingsManager.shared.primaryCurrencyCode,
                onToggleFavorite: nil,
                onSelect: { code in
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
            .navigationTitle(String(localized: "finances.dynamics.currency.title"))
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
                    Button(String(localized: "finances.common.cancel")) {
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
            .alert(String(localized: "finances.dynamics.currency.hint.title"), isPresented: $showDisplayCurrencyInfoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(displayCurrencyInfoMessage)
            }
        }
        .presentationDetents([.large])
    }

    private var displayCurrencyInfoMessage: String {
        String(localized: "finances.display_currency.hint.message")
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
            .accessibilityLabel(String(localized: "finances.dynamics.currency.hint.dismiss_accessibility"))
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
        let periodBg = Color(.sRGB, red: 217.0 / 255.0, green: 217.0 / 255.0, blue: 217.0 / 255.0, opacity: 0.2)
        let calendarBg = Color(.sRGB, red: 217.0 / 255.0, green: 217.0 / 255.0, blue: 217.0 / 255.0, opacity: 0.4)
        return HStack(spacing: 8) {
            // Кнопки периодов
            ForEach([DynamicsPeriod.all, .week, .month, .year], id: \.self) { period in
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
                            Capsule().fill(
                                period == viewModel.state.period && !useCustomPeriod
                                    ? periodBg
                                    : periodBg
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                Color.white.opacity(
                                    period == viewModel.state.period && !useCustomPeriod ? 0.20 : 0.08
                                ),
                                lineWidth: 0
                            )
                        )
                        .foregroundStyle(
                            period == viewModel.state.period && !useCustomPeriod
                                ? AppColors.textPrimary
                                : AppColors.textSecondary
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 60, height: 32)
            }

            Spacer(minLength: 8)

            // Кнопка календаря
            Button {
                draftStartDate = customStartDate
                draftEndDate = customEndDate
                showCustomPeriodSheet = true
            } label: {
                Image("calendar")
                    .frame(width: 24, height: 24)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(calendarBg))
                    .foregroundStyle(useCustomPeriod ? AppColors.textPrimary : AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: 60, height: 32)
        }
        .frame(maxWidth: .infinity)
//        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Custom Period Sheet

    private var customPeriodSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 16) {
                    // Header с информацией о периоде
                    VStack(alignment: .leading, spacing: 6) {
                        let sameYear = Calendar.current.component(.year, from: draftStartDate) == Calendar.current.component(.year, from: draftEndDate)
                        let startFormat: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
                        let endFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
                        Text(
                            FinancesL10n.format(
                                "finances.dynamics.custom_period.title",
                                min(draftStartDate, draftEndDate).formatted(startFormat),
                                max(draftStartDate, draftEndDate).formatted(endFormat)
                            )
                        )
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(String(localized: "finances.dynamics.custom_period.subtitle"))
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 0)
                    .padding(.top, 4)

                    // Календарь
                    CalendarRangeMonthView(startDate: $draftStartDate, endDate: $draftEndDate)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCustomPeriodSheet = false
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
                        draftStartDate = Date()
                        draftEndDate = Date()
                        customStartDate = draftStartDate
                        customEndDate = draftEndDate
                        useCustomPeriod = false
                        viewModel.handle(.setPeriod(.month))
                        cachedSelectedPoint = nil
                        showCustomPeriodSheet = false
                    } label: {
                        Text(String(localized: "finances.common.reset"))
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
                        let clampedEnd = min(end, Date())
                        let clampedStart = min(start, clampedEnd)
                        customStartDate = clampedStart
                        customEndDate = clampedEnd
                        useCustomPeriod = true
                        viewModel.handle(.setCustomPeriod(start: clampedStart, end: clampedEnd))
                        cachedSelectedPoint = nil
                        showCustomPeriodSheet = false
                    } label: {
                        Text(String(localized: "finances.dynamics.custom_period.show"))
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
                                                    colors: AppColors.financesGradient,
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
                            .foregroundStyle(Color.cyan)
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
                    // Заголовок таблицы
                    tableHeader

                    // Итого
                    if let total = totalRow {
                        totalRowView(total)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.horizontal, 16)
                    }

                    // Строки данных
                    ForEach(viewModel.state.dynamicsBreakdown) { item in
                        rowView(item)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
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
                        ? String(localized: "finances.dynamics.empty.groups.title")
                        : String(localized: "finances.dynamics.empty.products.title")
                )
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.textPrimary)

                if viewModel.state.viewMode != .groups {
                    Text(String(localized: "finances.dynamics.empty.products.subtitle"))
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
                Text(String(localized: "finances.dynamics.table.start"))
                    .font(.caption2).foregroundStyle(AppColors.textSecondary)
                    .frame(width: 92, alignment: .trailing)
                Text(String(localized: "finances.dynamics.table.end"))
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
        return Picker(String(localized: "finances.dynamics.view_mode.title"), selection: dynamicsViewModeSelection) {
            Text(String(localized: "finances.dynamics.view_mode.groups")).tag(0)
            Text(String(localized: "finances.dynamics.view_mode.accounts")).tag(1)
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

    private var dynamicsCardBackground: some View {
        let accentColor = AppColors.financesGradient.first ?? .cyan
        let fillGradient = LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.06, blue: 0.10),
                Color(red: 0.02, green: 0.03, blue: 0.06),
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
                }

                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(AppColors.textPrimary)
                
                if item.isArchived {
                    Text(String(localized: "finances.dynamics.archived_badge"))
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

                    if !(viewModel.state.isSingleAccountMode && marketInvestment == nil) {
                        let badgeColor = deltaColor(for: item)
                        let badgeBg = deltaBackground(for: item)
                        let badgeText = "\(formatDelta(item.delta))  •  \(formatPercent(item.deltaPercent))"
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

                    if !(viewModel.state.isSingleAccountMode && marketInvestment == nil) {
                        let badgeColor = deltaColor(for: item)
                        let badgeBg = deltaBackground(for: item)
                        let badgeText = "\(formatDelta(item.delta))  •  \(formatPercent(item.deltaPercent))"
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
        guard !viewModel.state.dynamicsBreakdown.isEmpty else { return nil }
        let startSum = viewModel.state.dynamicsBreakdown.reduce(0) { $0 + $1.startValue }
        let endSum = viewModel.state.dynamicsBreakdown.reduce(0) { $0 + $1.endValue }
        let delta = endSum - startSum
        let percent: Double = abs(startSum) > 0.01 ? (delta / abs(startSum)) * 100 : 0
        return DynamicsBreakdownItem(
            id: "total",
            name: String(localized: "finances.dynamics.chart.total_label"),
            startValue: startSum,
            endValue: endSum,
            delta: delta,
            deltaPercent: percent,
            icon: nil,
            accountType: nil,
            isCreditCard: false,
            isArchived: false
        )
    }

    // MARK: - Blocked/Empty Views

    /// Единая заглушка для PRO-блокировки графика (без "подсказок"/вспомогательных карточек),
    /// чтобы внешний вид был консистентным во всех местах приложения.
    private func proBlockedView(size: ProChartUpsellMetrics.Size) -> some View {
        ProChartUpsellView(
            titleKey: "finances.dynamics.pro.title",
            subtitleKey: "finances.dynamics.pro.subtitle",
            ctaKey: "finances.dynamics.pro.cta",
            size: size,
            onTapCTA: { showSubscriptionSheet = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyChartView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text(String(localized: "finances.dynamics.empty.chart"))
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var xAxisStride: Calendar.Component {
        switch viewModel.state.period {
        case .week: return .day
        case .month: return .day
        case .year: return .month
        case .all, .custom: return .month
        }
    }

    private var xAxisCount: Int {
        switch viewModel.state.period {
        case .week: return 1
        case .month: return 7
        case .year: return 2
        case .all, .custom: return 3
        }
    }

    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }

    private func formatDelta(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(formatBalance(delta))"
    }

    private func formatPercent(_ percent: Double) -> String {
        if abs(percent) >= 999999 {
            return percent > 0 ? "+∞" : "-∞"
        }
        return String(format: "%+.1f%%", percent)
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

    private func currencyWarningView(text: String, onClose: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "finances.dynamics.currency.hint.dismiss_accessibility"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 16)
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
            .navigationTitle(String(localized: "finances.dynamics.filter.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { }
        }
    }

    private var filterSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            TextField(String(localized: "finances.dynamics.filter.search_placeholder"), text: $filterSearchText)
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Spacer()
            Button(String(localized: "finances.common.cancel")) {
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
            Text(String(localized: "finances.dynamics.filter.apply"))
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
                filterPrimaryButton(title: String(localized: "finances.dynamics.filter.show_all")) {
                    viewModel.handle(.selectAllGroups)
                }
                .frame(maxWidth: .infinity)

                filterSecondaryButton(title: String(localized: "finances.dynamics.filter.clear_selection")) {
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
                Text(String(localized: "finances.dynamics.empty.groups.title"))
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
            Text(String(localized: "finances.dynamics.filter.archive_section"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            Toggle(String(localized: "finances.dynamics.filter.show_archived_accounts"), isOn: Binding(
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
