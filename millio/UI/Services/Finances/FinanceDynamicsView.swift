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

                        // Карточка графика
                        chartCard

                        if let warning = viewModel.state.currencyConversionWarning {
                            currencyWarningView(text: warning)
                        }

                        // Список динамики
                        dynamicsListCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
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
        .navigationTitle(viewModel.state.isSingleAccountMode ? "" : "Динамика")
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
                                        Text("Позиция всего, \(resolvedInvestmentCurrency(investment))")
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

                        Text("Информация об инструменте")
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
                                "Цена за единицу, \(resolvedInvestmentCurrency(investment))",
                                money(investment.lastKnownUnitPrice ?? 0, currency: resolvedInvestmentCurrency(investment)),
                                isEditable: true,
                                isEditing: isInlineMarketEdit,
                                editText: $editUnitPriceText,
                                keyboardType: .decimalPad,
                                compactLayout: compactLayout
                            )
                            statCell(
                                "Цена покупки",
                                money(investment.averagePurchaseUnitPrice ?? 0, currency: resolvedInvestmentCurrency(investment)),
                                isEditable: true,
                                isEditing: isInlineMarketEdit,
                                editText: $editPurchasePriceText,
                                keyboardType: .decimalPad,
                                compactLayout: compactLayout
                            )
                            statCell(
                                "Сумма покупки",
                                money(investment.totalPurchaseCost ?? 0, currency: resolvedInvestmentCurrency(investment)),
                                compactLayout: compactLayout
                            )
                        }

                    }
                }

                VStack(alignment: .leading, spacing: compactLayout ? 6 : 8) {
                    Text("Действия")
                        .font(.system(size: compactLayout ? 18 : 20, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    FinancesGlassCard(
                        accentColor: Color.cyan.opacity(0.95),
                        contentPadding: EdgeInsets(top: compactLayout ? 10 : 12, leading: 12, bottom: compactLayout ? 10 : 12, trailing: 12)
                    ) {
                        HStack(spacing: compactLayout ? 8 : 10) {
                            actionButton(title: "Купить", icon: "cart.badge.plus", color: Color.green.opacity(0.88), compactLayout: compactLayout) {
                                tradeMode = .buy
                                prepareTradeDraft(for: investment)
                                showTradeSheet = true
                            }
                            actionButton(title: "Продать", icon: "cart.badge.minus", color: Color.red.opacity(0.9), compactLayout: compactLayout) {
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

            marketEditTopBar(for: investment, compactLayout: compactLayout)
        }
    }

    private func marketEditTopBar(for investment: Investment, compactLayout: Bool) -> some View {
        HStack(spacing: 8) {
            let canFinish = canFinishInlineMarketEdit(for: investment)
            if isInlineMarketEdit {
                Button {
                    if canFinish {
                        finishInlineMarketEdit(for: investment)
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: compactLayout ? 18 : 19, weight: .bold))
                        .foregroundStyle(canFinish ? Color.black : Color.white.opacity(0.75))
                        .frame(width: compactLayout ? 34 : 38, height: compactLayout ? 34 : 38)
                        .background(
                            Circle()
                                .fill(canFinish ? Color.green.opacity(0.92) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    isInlineMarketEdit = true
                    syncMarketDraft(from: investment)
                } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: compactLayout ? 18 : 19, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                            .frame(width: compactLayout ? 34 : 38, height: compactLayout ? 34 : 38)
                }
                .buttonStyle(.plain)
            }

            Button {
                if cashflowViewModel == nil {
                    cashflowViewModel = CashflowViewModel(modelContext: modelContext)
                }
                cashflowViewModel?.handle(.loadTransactions)
                showCashflowHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: compactLayout ? 19 : 20, weight: .medium))
                    .foregroundStyle(Color.cyan)
                    .frame(width: compactLayout ? 34 : 38, height: compactLayout ? 34 : 38)
            }
            .buttonStyle(.plain)

            Button {
                showFullProductEditSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: compactLayout ? 19 : 20, weight: .medium))
                    .foregroundStyle(Color.cyan)
                    .frame(width: compactLayout ? 34 : 38, height: compactLayout ? 34 : 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, compactLayout ? 8 : 10)
        .padding(.vertical, compactLayout ? 6 : 7)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                )
        )
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
                    Text("Рост")
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
                        Picker("Режим сделки", selection: $tradeMode) {
                            Text("Купить").tag(InvestmentOrderSide.buy)
                            Text("Продать").tag(InvestmentOrderSide.sell)
                        }
                        .pickerStyle(.segmented)

                        FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
                            VStack(spacing: 12) {
                                Picker("Режим цены", selection: $tradePriceMode) {
                                    Text("Рыночная").tag(TradePriceMode.market)
                                    Text("Своя").tag(TradePriceMode.custom)
                                }
                                .pickerStyle(.segmented)

                                tradeRow(
                                    title: "Цена, \(resolvedInvestmentCurrency(investment))",
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
                                    title: "Итого, \(resolvedInvestmentCurrency(investment))",
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
                            title: tradeMode == .buy ? "Проведите вправо, чтобы купить" : "Проведите вправо, чтобы продать",
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
            .navigationTitle("Сделка")
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
            tradeErrorText = "Проверьте количество и цену."
            return
        }

        if tradeMode == .sell, quantity > (investment.marketQuantity ?? 0) {
            tradeErrorText = "Недостаточно количества для продажи."
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
        investment.category == .crypto ? "Количество монет" : "Количество"
    }

    private func marketQuantityUnit(for investment: Investment) -> String {
        investment.category == .crypto ? "мон." : "шт"
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
                if !appState.isPro {
                    proBlockedView
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
        .frame(height: currentHeight + 100)
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

                // Бейдж с дельтой
                if viewModel.state.chartData.count >= 2 && !isSingleAccountSummaryMode {
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
                HStack(spacing: 6) {
                    Image(systemName: accountInfo.icon)
                        .font(.caption)
                    Text(accountInfo.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.14), Color.white.opacity(0.06)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.cyan.opacity(0.45), lineWidth: 0.8)
                        )
                )
                .foregroundStyle(AppColors.textPrimary.opacity(0.92))
            }

            if let account = initialAccount, inlineCreditCard(for: account) != nil {
                inlineAccountEditor(for: account)
            }

            // Период
            let (startDate, endDate) = viewModel.getPeriodDates()
            let sameYear = Calendar.current.component(.year, from: startDate) == Calendar.current.component(.year, from: endDate)
            let startFormat: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
            let endFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
            Text("\(startDate.formatted(startFormat)) — \(endDate.formatted(endFormat))")
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 0)
    }

    private var singleAccountSummaryTable: some View {
        let symbol = MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency
        let delta = viewModel.state.periodDelta
        let growthTextColor: Color = delta.absolute > 0
            ? Color(.sRGB, red: 127.0 / 255.0, green: 1.0, blue: 189.0 / 255.0, opacity: 1.0)
            : (delta.absolute < 0
               ? Color(.sRGB, red: 1.0, green: 0.37, blue: 0.37, opacity: 1.0)
               : AppColors.textSecondary)

        let accountName: String = {
            guard case .singleAccount(let accountID) = viewModel.state.dynamicsMode,
                  let account = viewModel.getAccountsForSelectedGroups().first(where: { $0.accountUniqueID == accountID }),
                  let accountInfo = viewModel.getAccountInfoForDynamics(account: account) else {
                return "Счет"
            }
            return accountInfo.name
        }()

        return HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                .frame(maxWidth: .infinity)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                )
                .overlay {
                    VStack(spacing: 5) {
                        Text("Рост")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                        Text(formatPercent(delta.percent))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(growthTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: 118)
        }
        .frame(height: 88)
    }

    private var shouldShowSingleAccountActionBar: Bool {
        viewModel.state.isSingleAccountMode && initialAccount != nil && marketInvestment == nil
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
                Image(systemName: isInlineAccountEdit ? "checkmark" : "minus")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(
                        isInlineAccountEdit
                            ? (canSave ? Color(red: 0.20, green: 0.92, blue: 0.49) : Color.cyan.opacity(0.4))
                            : Color.cyan
                    )
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.16))

            Button {
                if cashflowViewModel == nil {
                    cashflowViewModel = CashflowViewModel(modelContext: modelContext)
                }
                cashflowViewModel?.handle(.loadTransactions)
                showCashflowHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.16))

            Button {
                showFullProductEditSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.cyan)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
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
                    title: "Кредитный лимит",
                    value: limit,
                    currency: info.currency,
                    isEditing: isInlineAccountEdit,
                    text: Binding(
                        get: { AmountInputFormatter.display(inlineCreditLimitText) },
                        set: { inlineCreditLimitText = AmountInputFormatter.sanitize($0) }
                    )
                )
                creditFieldRow(
                    title: "Общий долг",
                    value: debt,
                    currency: info.currency,
                    isEditing: isInlineAccountEdit,
                    text: Binding(
                        get: { AmountInputFormatter.display(inlineCreditDebtText) },
                        set: { inlineCreditDebtText = AmountInputFormatter.sanitize($0) }
                    )
                )
                creditFieldRow(
                    title: "Остаток лимита",
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
        NavigationStack {
            CurrencyPickerView(
                allCodes: viewModel.state.availableCurrencies.isEmpty
                    ? CurrencySelectionSupport.allCurrencyCodesForPicker
                    : viewModel.state.availableCurrencies,
                searchText: $displayCurrencySearchText,
                selectedCodes: CurrencySelectionSupport.pinnedCurrencyCodes(for: viewModel.state.displayCurrency),
                favoriteCodes: [],
                currentSelection: viewModel.state.displayCurrency,
                onToggleFavorite: nil,
                onSelect: { code in
                    viewModel.handle(.setDisplayCurrency(code))
                    displayCurrencySearchText = ""
                    showDisplayCurrencySheet = false
                }
            )
            .navigationTitle("Валюта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        displayCurrencySearchText = ""
                        showDisplayCurrencySheet = false
                    }
                }
            }
        }
        .presentationDetents([.large])
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
                        Text("Период: \(min(draftStartDate, draftEndDate).formatted(startFormat)) — \(max(draftStartDate, draftEndDate).formatted(endFormat))")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Выберите начало и конец периода на календаре")
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
                        Text("Сбросить")
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
                        customStartDate = clampedStart
                        customEndDate = clampedEnd
                        useCustomPeriod = true
                        viewModel.handle(.setCustomPeriod(start: clampedStart, end: clampedEnd))
                        cachedSelectedPoint = nil
                        showCustomPeriodSheet = false
                    } label: {
                        Text("Показать")
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
                Text(viewModel.state.viewMode == .groups ? "Нет групп" : "Нет продуктов")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(viewModel.state.viewMode == .groups ? "Создайте первую группу" : "Создайте первый продукт")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
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
                Text("Начало")
                    .font(.caption2).foregroundStyle(AppColors.textSecondary)
                    .frame(width: 92, alignment: .trailing)
                Text("Конец")
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
        return Picker("Режим динамики", selection: dynamicsViewModeSelection) {
            Text("Группы").tag(0)
            Text("Счета").tag(1)
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
                    Text("архив")
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

                    // Бейдж с изменением
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

    // MARK: - Total Row

    private var totalRow: DynamicsBreakdownItem? {
        guard !viewModel.state.dynamicsBreakdown.isEmpty else { return nil }
        let startSum = viewModel.state.dynamicsBreakdown.reduce(0) { $0 + $1.startValue }
        let endSum = viewModel.state.dynamicsBreakdown.reduce(0) { $0 + $1.endValue }
        let delta = endSum - startSum
        let percent: Double = abs(startSum) > 0.01 ? (delta / abs(startSum)) * 100 : 0
        return DynamicsBreakdownItem(
            id: "total",
            name: "Итого",
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

    private var proBlockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text("График доступен в PRO версии")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Оформите подписку для доступа к расширенной аналитике")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showSubscriptionSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                    Text("Оформить PRO")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule().stroke(
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2
                            )
                        }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .padding(24)
    }

    private var emptyChartView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text("Нет данных для отображения")
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

    private func currencyWarningView(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
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
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { }
        }
    }

    private var filterSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            TextField("Поиск", text: $filterSearchText)
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Spacer()
            Button("Отменить") {
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
            Text("Принять фильтр")
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
                filterPrimaryButton(title: "Показать все") {
                    viewModel.handle(.selectAllGroups)
                }
                .frame(maxWidth: .infinity)

                filterSecondaryButton(title: "Снять выбор") {
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
                Text("Нет групп")
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
            Text("Архив")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            Toggle("Показывать архивные счета", isOn: Binding(
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
