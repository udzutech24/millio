//
//  InvestmentEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 27.01.2026.
//

import SwiftUI

// MARK: - Investment Editor View

enum InvestmentEditorLayoutPolicy {
    static func showsDeleteButton(for editingInvestment: Investment?) -> Bool {
        editingInvestment != nil
    }
}

struct InvestmentEditorView: View {
    @ObservedObject var viewModel: InvestmentViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    @State private var name: String = ""
    @State private var selectedInvestmentType: InvestmentType = .positive
    @State private var selectedCategory: InvestmentCategory = .other
    @State private var amountText: String = ""
    @State private var selectedCurrency: String = SettingsManager.shared.primaryCurrencyCode
    @State private var includeInTotal: Bool = true
    @State private var selectedPriority: InvestmentPriority = .normal
    @State private var isFavorite: Bool = false
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""

    @State private var marketSymbol: String = ""
    @State private var marketAssetID: String?
    @State private var marketExchange: String?
    @State private var marketQuoteLookupKey: String?
    @State private var marketMICCode: String?
    @State private var marketCurrency: String?
    @State private var marketQuantityText: String = ""
    @State private var purchaseUnitPriceText: String = ""
    @State private var lastKnownUnitPrice: Double?
    @State private var lastKnownPriceUpdatedAt: Date?
    @State private var marketProviderRaw: String?
    @State private var showMarketSearchSheet: Bool = false
    @State private var isRefreshingPrice: Bool = false
    @State private var marketErrorMessage: String?
    @State private var lastMarketRefreshAt: Date?
    @State private var showPaywallAlert = false
    @State private var paywallMessage: LocalizedTextResolver = .empty
    @State private var showCryptoProAlert = false
    @State private var showDeleteConfirmation = false

    // MARK: - Deposit @State
    @State private var depositInterestRateText: String = ""
    @State private var depositStartDate: Date = Date()
    @State private var depositEndDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var depositHasEndDate: Bool = false
    @State private var depositIncomeInCashflow: Bool = false
    @State private var depositCapitalization: DepositCapitalization = .none
    @State private var depositNotifyDaysBefore: Int? = nil

    private let marketDataClient: MarketDataClientProtocol
    private let marketRefreshCooldown: TimeInterval = 10

    init(
        viewModel: InvestmentViewModel,
        marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared,
        onClose: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.marketDataClient = marketDataClient
        self.onClose = onClose
        self.onDelete = onDelete
    }

    private var isMarketCategory: Bool {
        selectedCategory == .stocks || selectedCategory == .crypto
    }

    private var marketFilter: MarketSymbolFilter {
        selectedCategory == .crypto ? .crypto : .stocks
    }

    private var isEditingMarketAssetWithLockedIdentity: Bool {
        guard let editing = viewModel.state.editingInvestment else {
            return false
        }
        return editing.category == .stocks || editing.category == .crypto
    }

    private var isDepositMode: Bool {
        // При редактировании существующего вклада — проверяем флаг модели.
        // При создании нового вклада — editingInvestment ещё nil, используем isCreatingDeposit.
        viewModel.state.editingInvestment?.isDeposit == true || viewModel.state.isCreatingDeposit
    }

    private var depositMonthlyIncome: Double {
        guard let rate = parseNumber(depositInterestRateText), rate > 0,
              let amt = parseNumber(amountText), amt > 0 else { return 0 }
        switch depositCapitalization {
        case .none:
            return ((amt * rate / 100.0 / 12.0) * 100).rounded() / 100
        case .monthly:
            let monthly = pow(1.0 + rate / 100.0 / 12.0, 12.0) - 1.0
            return ((amt * monthly / 12.0) * 100).rounded() / 100
        }
    }

    private var marketInstrumentTitle: LocalizedStringKey {
        selectedCategory == .crypto ? "finances.market.field_pair" : "finances.market.field_ticker"
    }

    private var marketQuantityTitle: LocalizedStringKey {
        selectedCategory == .crypto ? "finances.market.field_quantity_coins" : "finances.market.field_quantity"
    }

    private var marketSearchButtonTitle: LocalizedStringKey {
        selectedCategory == .crypto ? "finances.market.search_pair_button" : "finances.market.search_ticker_button"
    }

    private var needsMarketSymbolSelection: Bool {
        isMarketCategory && marketSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var marketSymbolHintText: String {
        selectedCategory == .crypto
            ? L("finances.add_account.hint.select_coin_or_pair")
            : L("finances.add_account.hint.select_ticker")
    }

    private var positionTotal: Double? {
        guard let quantity = parseMarketQuantity(marketQuantityText),
              let unitPrice = lastKnownUnitPrice else {
            return nil
        }
        return quantity * unitPrice
    }

    private var canDeleteInvestment: Bool {
        InvestmentEditorLayoutPolicy.showsDeleteButton(for: viewModel.state.editingInvestment)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        mainInfoSection
                        investmentParamsSection
                        if isDepositMode {
                            depositIncomeSection
                        }
                        additionalSection

                        if canDeleteInvestment {
                            deleteInvestmentButton
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()

                FinancesDestructiveConfirmationOverlay(
                    isPresented: showDeleteConfirmation,
                    title: deleteConfirmationTitle,
                    message: String(localized: deleteConfirmationMessageKey),
                    confirmTitle: L("finances.common.delete"),
                    cancelTitle: L("finances.common.cancel"),
                    onConfirm: confirmDeleteInvestment,
                    onCancel: { showDeleteConfirmation = false }
                )
            }
            .navigationTitle(
                viewModel.state.editingInvestment == nil
                    ? L("finances.editor.investment.new_title")
                    : L("finances.editor.investment.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("finances.common.cancel")) {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("finances.common.save")) {
                        saveInvestment()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.investmentsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingInvestment {
                    name = editing.name
                    selectedInvestmentType = editing.investmentType
                    selectedCategory = editing.category
                    amountText = String(format: "%.2f", editing.amount)
                    selectedCurrency = editing.currency
                    includeInTotal = editing.includeInTotal
                    selectedPriority = editing.priority
                    isFavorite = editing.isFavorite

                    marketSymbol = editing.marketSymbol ?? ""
                    marketAssetID = editing.assetID
                    marketExchange = editing.marketExchange
                    marketQuoteLookupKey = editing.marketQuoteLookupKey
                    marketMICCode = editing.marketMICCode
                    marketCurrency = editing.marketCurrency
                    marketQuantityText = editing.marketQuantity.map {
                        AmountInputFormatter.plainString(
                            from: $0,
                            maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits
                        )
                    } ?? ""
                    purchaseUnitPriceText = editing.averagePurchaseUnitPrice.map { String($0) } ?? ""
                    lastKnownUnitPrice = editing.lastKnownUnitPrice
                    lastKnownPriceUpdatedAt = editing.lastKnownPriceUpdatedAt
                    marketProviderRaw = editing.marketProviderRaw

                    if editing.isDeposit {
                        depositInterestRateText = editing.depositInterestRate.map { String($0) } ?? ""
                        depositStartDate = editing.depositStartDate ?? Date()
                        let end = editing.depositEndDate
                        depositHasEndDate = end != nil
                        depositEndDate = end ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
                        depositIncomeInCashflow = editing.depositIncomeInCashflow
                        depositCapitalization = DepositCapitalization(rawValue: editing.depositCapitalizationRaw) ?? .none
                        depositNotifyDaysBefore = editing.depositNotifyDaysBefore
                    }
                }

                loadAvailableCurrencies()
            }
            .onChange(of: selectedCategory) { oldValue, newValue in
                if (newValue == .stocks || newValue == .crypto),
                   !canUseMarketCategory(newValue),
                   !isEditingMarketAssetWithLockedIdentity {
                    paywallMessage = marketCategoryPaywallMessage(for: newValue)
                    showPaywallAlert = true
                    selectedCategory = .other
                    return
                }
                if !(newValue == .stocks || newValue == .crypto) {
                    clearMarketState()
                }
                if MarketSearchFlowPolicy.shouldAutoOpenSearch(
                    previousCategory: oldValue,
                    newCategory: newValue,
                    marketSymbol: marketSymbol,
                    isEditingLockedIdentity: isEditingMarketAssetWithLockedIdentity
                ) {
                    DispatchQueue.main.async {
                        showMarketSearchSheet = true
                    }
                }
            }
            .onChange(of: marketQuantityText) { _, _ in
                if let total = positionTotal {
                    amountText = String(total)
                }
            }
            .sheet(isPresented: $showMarketSearchSheet) {
                MarketSymbolSearchSheet(filter: marketFilter) { symbol in
                    applySelectedMarketSymbol(symbol)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
                    let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
                    CurrencyPickerView(
                        allCodes: availableCurrencies,
                        searchText: $currencySearchText,
                        selectedCodes: favoriteCodes,
                        favoriteCodes: Set(favoriteCodes),
                        currentSelection: selectedCurrency,
                        primaryPinnedCode: SettingsManager.shared.primaryCurrencyCode,
                        onToggleFavorite: nil,
                        badgeForCode: { code in
                            guard CurrencySelectionSupport.isCrypto(code), !canUseCrypto else { return nil }
                            return .pro
                        },
                        onSelect: { currency in
                            if CurrencySelectionSupport.isCrypto(currency), !canUseCrypto {
                                showCryptoProAlert = true
                                return
                            }
                            selectedCurrency = currency
                            showCurrencyPicker = false
                        }
                    )
                    .navigationTitle(L("finances.add_account.currency_picker.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("finances.common.cancel")) {
                                showCurrencyPicker = false
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .premiumUpsellAlert(
                isPresented: $showPaywallAlert,
                titleKey: "monetization.free_plan.title",
                message: paywallMessage,
                onSubscribe: { router.push(.subscription) }
            )
            .premiumUpsellAlert(
                isPresented: $showCryptoProAlert,
                titleKey: "monetization.crypto.pro_title",
                message: .key("monetization.crypto.pro_message"),
                onSubscribe: { router.push(.subscription) }
            )
        }
    }

    private var deleteInvestmentButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Text(String(localized: deleteActionTitle))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.error.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppColors.error.opacity(0.22), lineWidth: 0.9)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("finances.investment_editor.delete_account.button")
    }
    
    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.editor.section.main_info"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    TextField(L("finances.editor.investment.name_placeholder"), text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var investmentParamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.editor.investment.params_section"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(L("finances.editor.investment.type_label"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(L("finances.editor.investment.type_label"), selection: $selectedInvestmentType) {
                            ForEach(InvestmentType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    HStack {
                        Text(L("finances.editor.investment.category_label"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isEditingMarketAssetWithLockedIdentity {
                            Text(selectedCategory.displayName)
                                .foregroundStyle(AppColors.textTertiary)
                        } else {
                            Picker(L("finances.editor.investment.category_label"), selection: $selectedCategory) {
                                ForEach(InvestmentCategory.allCases, id: \.self) { category in
                                    Text(category.displayName).tag(category)
                                }
                            }
                            .tint(AppColors.textTertiary)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    if isMarketCategory {
                        marketRows
                    } else {
                        regularAmountRows
                    }
                }
            }

            if isMarketCategory {
                marketStatusInfo
            }
        }
    }

    private var marketRows: some View {
        Group {
            HStack(spacing: 12) {
                Text(marketInstrumentTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(marketSymbol.isEmpty ? "—" : marketSymbol)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            FinancesRowDivider()

            if !isEditingMarketAssetWithLockedIdentity {
                HStack(spacing: 12) {
                    Button {
                        guard canUseMarketCategory(selectedCategory) else {
                            paywallMessage = marketCategoryPaywallMessage(for: selectedCategory)
                            showPaywallAlert = true
                            return
                        }
                        showMarketSearchSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text(marketSearchButtonTitle)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    needsMarketSymbolSelection
                                        ? Color(red: 0.18, green: 0.95, blue: 0.45).opacity(0.16)
                                        : Color.clear
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            needsMarketSymbolSelection
                                                ? Color(red: 0.18, green: 0.95, blue: 0.45).opacity(0.75)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .foregroundStyle(
                        needsMarketSymbolSelection
                            ? AnyShapeStyle(Color(red: 0.18, green: 0.95, blue: 0.45))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: AppColors.investmentsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )

                    if needsMarketSymbolSelection {
                        Text(marketSymbolHintText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(red: 0.18, green: 0.95, blue: 0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if let marketExchange, !marketExchange.isEmpty {
                        Text(marketExchange)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                FinancesRowDivider()
            }

            HStack {
                Text(marketQuantityTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                TextField("0", text: Binding(
                    get: { formatMarketQuantityForDisplay(marketQuantityText) },
                    set: { newValue in
                        let sanitized = AmountInputFormatter.sanitize(
                            newValue,
                            maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits
                        )
                        marketQuantityText = sanitized
                    }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: 150)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            FinancesRowDivider()

            HStack(spacing: 8) {
                Text(L("finances.market.field_unit_price"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if isRefreshingPrice {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppColors.textTertiary)
                } else {
                    Text(formatOptionalPrice(lastKnownUnitPrice))
                        .foregroundStyle(AppColors.textPrimary)
                }
                Button {
                    refreshLatestPrice(forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(AppColors.textTertiary)
                }
                .disabled(marketSymbol.isEmpty || isRefreshingPrice)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            FinancesRowDivider()

            HStack {
                Text(L("finances.add_account.investment.purchase_price"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                TextField("0", text: Binding(
                    get: { formatNumberForDisplay(purchaseUnitPriceText) },
                    set: { newValue in
                        purchaseUnitPriceText = AmountInputFormatter.sanitize(newValue)
                    }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: 150)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            FinancesRowDivider()

            HStack {
                Text(L("finances.market.field_position_total"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(formatOptionalPrice(positionTotal))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            FinancesRowDivider()

            HStack {
                Text(L("finances.market.field_quote_currency"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(marketCurrency ?? selectedCurrency)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
    }

    private var regularAmountRows: some View {
        Group {
            HStack {
                Text(L("finances.add_account.field.amount"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                TextField("0", text: Binding(
                    get: { formatNumberForDisplay(amountText) },
                    set: { newValue in
                        let sanitized = AmountInputFormatter.sanitize(newValue)
                        amountText = sanitized
                    }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: 150)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            FinancesRowDivider()

            HStack {
                Text(L("finances.add_account.field.currency"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if isLoadingCurrencies {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppColors.textTertiary)
                } else {
                    Button {
                        showCurrencyPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedCurrency)
                                .foregroundStyle(AppColors.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
    }

    private var marketStatusInfo: some View {
        Group {
            if let marketErrorMessage, !marketErrorMessage.isEmpty {
                Text(marketErrorMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.error)
                    .padding(.horizontal, 4)
            } else if let lastKnownPriceUpdatedAt {
                Text("\(L("finances.market.price_updated_prefix")) \(formatDate(lastKnownPriceUpdatedAt))")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                    .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Deposit Income Section

    @ViewBuilder
    private var depositIncomeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.deposit.section.income_title"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    // Ставка
                    HStack {
                        Text(L("finances.deposit.field.rate"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: $depositInterestRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: 90)
                        Text("%")
                            .foregroundStyle(AppColors.textTertiary)
                            .font(.system(size: 15))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    // Дата открытия
                    DatePicker(
                        L("finances.deposit.field.start_date"),
                        selection: $depositStartDate,
                        displayedComponents: .date
                    )
                    .foregroundStyle(AppColors.textPrimary)
                    .tint(AppColors.textPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    // Срок вклада
                    Toggle(L("finances.deposit.field.has_end_date"), isOn: $depositHasEndDate)
                        .foregroundStyle(AppColors.textPrimary)
                        .tint(AppColors.toggleOnGreen)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)

                    FinancesRowDivider()

                    // Капитализация
                    HStack {
                        Text(L("finances.deposit.field.capitalization"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(L("finances.deposit.field.capitalization"), selection: $depositCapitalization) {
                            ForEach(DepositCapitalization.allCases, id: \.self) { cap in
                                Text(cap.displayName).tag(cap)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.brandPrimary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    if depositHasEndDate {
                        FinancesRowDivider()
                        DatePicker(
                            L("finances.deposit.field.end_date"),
                            selection: $depositEndDate,
                            in: depositStartDate...,
                            displayedComponents: .date
                        )
                        .foregroundStyle(AppColors.textPrimary)
                        .tint(AppColors.textPrimary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)

                        FinancesRowDivider()

                        // Уведомление о конце срока
                        HStack {
                            Text(L("finances.deposit.field.notify"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Picker(L("finances.deposit.field.notify"), selection: Binding(
                                get: { DepositNotifyDays(rawValue: depositNotifyDaysBefore ?? 0) ?? .off },
                                set: { depositNotifyDaysBefore = $0 == .off ? nil : $0.rawValue }
                            )) {
                                ForEach(DepositNotifyDays.allCases, id: \.self) { opt in
                                    Text(opt.displayName).tag(opt)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColors.brandPrimary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }

                    if depositMonthlyIncome > 0 {
                        FinancesRowDivider()
                        // Плановый доход
                        HStack {
                            Text(L("finances.deposit.monthly_income_label"))
                                .foregroundStyle(AppColors.textSecondary)
                                .font(.system(size: 14))
                            Spacer()
                            Text("~\(String(format: "%.2f", depositMonthlyIncome)) \(selectedCurrency)\(L("finances.deposit.per_month_suffix"))")
                                .foregroundStyle(AppColors.textPrimary)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        FinancesRowDivider()

                        // Тоггл Cashflow
                        Toggle(L("finances.deposit.cashflow_toggle"), isOn: $depositIncomeInCashflow)
                            .foregroundStyle(AppColors.textPrimary)
                            .tint(AppColors.toggleOnGreen)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)

                        if depositIncomeInCashflow {
                            FinancesRowDivider()
                            HStack {
                                Image(systemName: "calendar.badge.checkmark")
                                    .foregroundStyle(AppColors.toggleOnGreen)
                                    .font(.system(size: 13))
                                Text(String(format: L("finances.deposit.cashflow_preview"),
                                            String(format: "%.2f", depositMonthlyIncome),
                                            selectedCurrency))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .font(.system(size: 13))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private var additionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.editor.section.additional"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(L("finances.add_account.section.priority"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(L("finances.add_account.section.priority"), selection: $selectedPriority) {
                            ForEach(InvestmentPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    Toggle(L("finances.add_account.favorite"), isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    Toggle(L("finances.add_account.total_impact.include"), isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private var isValid: Bool {
        if isMarketCategory {
            guard !name.isEmpty,
                  !marketSymbol.isEmpty,
                  let quantity = InvestmentMarketInputParser.quantity(from: marketQuantityText) else {
                return false
            }
            return quantity >= 0
        }

        guard !name.isEmpty,
              let amount = parseNumber(amountText) else {
            return false
        }

        return amount > 0
    }

    private func loadAvailableCurrencies() {
        Task {
            await MainActor.run {
                isLoadingCurrencies = true
            }

            await MainActor.run {
                availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: [selectedCurrency])
                isLoadingCurrencies = false
            }
        }
    }

    private func refreshLatestPrice(forceRefresh: Bool) {
        guard let identity = MarketSymbolIdentity(
            marketSymbol: marketSymbol,
            exchange: marketExchange,
            quoteLookupKey: marketQuoteLookupKey,
            assetID: marketAssetID
        ) else {
            return
        }

        let now = Date()
        if forceRefresh,
           let lastMarketRefreshAt,
           now.timeIntervalSince(lastMarketRefreshAt) < marketRefreshCooldown {
            AppLogger.log(.info, category: "Finance", "Skipping editor quote refresh due to cooldown symbol=\(identity.requestedSymbol)")
            return
        }
        lastMarketRefreshAt = now

        Task {
            await MainActor.run {
                isRefreshingPrice = true
                marketErrorMessage = nil
            }

            defer {
                Task { @MainActor in
                    isRefreshingPrice = false
                }
            }

            do {
                let latestQuote = try await marketDataClient.latestQuote(
                    symbol: identity.requestedSymbol,
                    forceRefresh: forceRefresh
                )

                await MainActor.run {
                    guard let latestQuote else {
                        marketErrorMessage = nil
                        return
                    }

                    switch latestQuote.resolutionStatus {
                    case .fresh, .stale:
                        guard let latestPrice = latestQuote.price, latestPrice > 0 else {
                            marketErrorMessage = MarketDataErrorPresentation.message(for: .priceUnavailable)
                            return
                        }

                        lastKnownUnitPrice = latestPrice
                        lastKnownPriceUpdatedAt = latestQuote.updatedAtDate ?? Date()
                        let updatedIdentity = identity.updating(with: latestQuote)
                        marketQuoteLookupKey = updatedIdentity.canonicalSymbol
                        marketMICCode = latestQuote.micCode ?? marketMICCode
                        marketProviderRaw = updatedIdentity.providerSymbol == nil ? marketProviderRaw : "market-backend"
                    case .notFound:
                        marketErrorMessage = MarketDataErrorPresentation.message(for: .notFound)
                        return
                    case .providerError:
                        marketErrorMessage = MarketDataErrorPresentation.message(for: .providerError)
                        return
                    }

                    if purchaseUnitPriceText.isEmpty {
                        purchaseUnitPriceText = String(lastKnownUnitPrice ?? 0)
                    }
                    if let positionTotal {
                        amountText = String(positionTotal)
                    }
                }
            } catch {
                await MainActor.run {
                    marketErrorMessage = MarketDataErrorPresentation.message(
                        for: MarketDataErrorPresentation.category(for: error)
                    )
                }
            }
        }
    }

    private func applySelectedMarketSymbol(_ symbol: TwelveDataSymbol) {
        marketSymbol = symbol.symbol
        marketAssetID = nil
        marketExchange = symbol.exchange
        marketQuoteLookupKey = symbol.canonicalQuoteLookupKey
        marketMICCode = symbol.micCode
        marketCurrency = symbol.currency
        selectedCurrency = symbol.currency ?? selectedCurrency
        marketProviderRaw = "market-backend"

        // В MVP используем тикер как название актива, чтобы не усложнять UX.
        name = symbol.symbol

        refreshLatestPrice(forceRefresh: true)
    }

    private func clearMarketState() {
        marketSymbol = ""
        marketAssetID = nil
        marketExchange = nil
        marketQuoteLookupKey = nil
        marketMICCode = nil
        marketCurrency = nil
        marketQuantityText = ""
        purchaseUnitPriceText = ""
        lastKnownUnitPrice = nil
        lastKnownPriceUpdatedAt = nil
        marketProviderRaw = nil
        marketErrorMessage = nil
    }

    private func normalizeNumber(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
    }

    private func parseNumber(_ text: String) -> Double? {
        AmountInputFormatter.parse(text)
    }

    private func parseMarketQuantity(_ text: String) -> Double? {
        AmountInputFormatter.parse(text, maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits)
    }

    private func formatOptionalPrice(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }

        let number = formatNumberForDisplay(String(value))
        let currency = marketCurrency ?? selectedCurrency
        return "\(number) \(currency)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }

    private func formatNumberForDisplay(_ text: String) -> String {
        AmountInputFormatter.display(text)
    }

    private func formatMarketQuantityForDisplay(_ text: String) -> String {
        AmountInputFormatter.display(text, maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits)
    }

    private func saveInvestment() {
        guard validateEntitlementsForSave() else { return }

        let effectiveAmount: Double
        let marketData: InvestmentMarketData?
        let createCashflowTransaction: Bool
        let effectiveCategory: InvestmentCategory

        if isMarketCategory {
            guard let quantity = InvestmentMarketInputParser.quantity(from: marketQuantityText), quantity >= 0 else {
                return
            }

            effectiveAmount = positionTotal ?? parseNumber(amountText) ?? (viewModel.state.editingInvestment?.amount ?? 0)
            let effectiveCurrency = (marketCurrency?.isEmpty == false) ? marketCurrency! : selectedCurrency
            let lockedCategory = viewModel.state.editingInvestment?.category
            let lockedSymbol = viewModel.state.editingInvestment?.marketSymbol

            marketData = InvestmentMarketData(
                assetID: marketAssetID,
                symbol: isEditingMarketAssetWithLockedIdentity ? lockedSymbol : (marketSymbol.isEmpty ? nil : marketSymbol),
                exchange: marketExchange,
                quoteLookupKey: marketQuoteLookupKey,
                micCode: marketMICCode,
                currency: marketCurrency ?? selectedCurrency,
                quantity: quantity,
                unitPrice: lastKnownUnitPrice,
                purchaseUnitPrice: parseNumber(purchaseUnitPriceText),
                priceUpdatedAt: lastKnownPriceUpdatedAt,
                providerRaw: marketProviderRaw
            )

            selectedCurrency = effectiveCurrency
            if let editing = viewModel.state.editingInvestment {
                let previousQuantity = editing.marketQuantity ?? 0
                createCashflowTransaction = abs(previousQuantity - quantity) > 0.0000001
            } else {
                createCashflowTransaction = false
            }
            effectiveCategory = isEditingMarketAssetWithLockedIdentity ? (lockedCategory ?? selectedCategory) : selectedCategory
        } else {
            guard let parsedAmount = parseNumber(amountText) else {
                return
            }
            effectiveAmount = parsedAmount
            marketData = nil
            createCashflowTransaction = true
            effectiveCategory = selectedCategory
        }

        // Сохраняем deposit-поля перед handle (SwiftData персистит их при modelContext.save внутри handle)
        if isDepositMode, let editing = viewModel.state.editingInvestment {
            editing.depositInterestRate = parseNumber(depositInterestRateText)
            editing.depositStartDate = depositStartDate
            editing.depositEndDate = depositHasEndDate ? depositEndDate : nil
            editing.depositIncomeInCashflow = depositIncomeInCashflow
            editing.depositCapitalizationRaw = depositCapitalization.rawValue
            editing.depositNotifyDaysBefore = depositNotifyDaysBefore
        }
        let depositSyncTarget = isDepositMode ? viewModel.state.editingInvestment : nil

        // При создании нового вклада editingInvestment ещё nil —
        // берём isDeposit из isCreatingDeposit-флага state.
        let effectiveIsDeposit = viewModel.state.editingInvestment?.isDeposit ?? viewModel.state.isCreatingDeposit

        // Собираем deposit-поля для передачи в action (нужно при создании нового вклада)
        let depositData: InvestmentDepositData? = effectiveIsDeposit ? InvestmentDepositData(
            interestRate: parseNumber(depositInterestRateText),
            startDate: depositStartDate,
            endDate: depositHasEndDate ? depositEndDate : nil,
            incomeInCashflow: depositIncomeInCashflow,
            capitalizationRaw: depositCapitalization.rawValue,
            notifyDaysBefore: depositNotifyDaysBefore ?? 0
        ) : nil

        viewModel.handle(.updateInvestment(
            name: name,
            investmentType: selectedInvestmentType,
            category: effectiveCategory,
            amount: effectiveAmount,
            currency: selectedCurrency,
            includeInTotal: includeInTotal,
            priority: selectedPriority,
            isFavorite: isFavorite,
            marketData: marketData,
            createCashflowTransaction: createCashflowTransaction,
            uniqueID: nil,
            isDeposit: effectiveIsDeposit,
            depositData: depositData
        ))

        if let inv = depositSyncTarget {
            viewModel.syncDepositIncome(for: inv)
            viewModel.syncDepositNotification(for: inv)
        }

        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func confirmDeleteInvestment() {
        guard let editingInvestment = viewModel.state.editingInvestment else { return }

        showDeleteConfirmation = false

        if let onDelete {
            onDelete()
            return
        }

        viewModel.handle(.deleteInvestment(editingInvestment))

        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var currentTrackedTickerCount: Int {
        viewModel.state.investments.reduce(into: 0) { partialResult, investment in
            if investment.category == .stocks || investment.category == .crypto {
                partialResult += 1
            }
        }
    }

    private var isCreatingNewTrackedTicker: Bool {
        guard isMarketCategory else { return false }

        if let editing = viewModel.state.editingInvestment {
            return !(editing.category == .stocks || editing.category == .crypto)
        }
        return true
    }

    private func validateEntitlementsForSave() -> Bool {
        if isMarketCategory, !canUseMarketCategory(selectedCategory) {
            paywallMessage = marketCategoryPaywallMessage(for: selectedCategory)
            showPaywallAlert = true
            return false
        }

        guard isCreatingNewTrackedTicker else { return true }

        let canAdd = EntitlementPolicy.canAddTrackedTicker(
            isPro: appState.isPro,
            currentTrackedTickers: currentTrackedTickerCount
        )
        guard canAdd else {
            paywallMessage = LocalizedTextResolver { locale in
                String(
                    format: AppLocalization.string("monetization.ticker.limit.hard_format", locale: locale),
                    locale: locale,
                    EntitlementPolicy.freeTrackedTickerLimit
                )
            }
            showPaywallAlert = true
            return false
        }
        return true
    }

    private func canUseMarketCategory(_ category: InvestmentCategory) -> Bool {
        switch category {
        case .stocks:
            return EntitlementPolicy.canUseFinanceStocks(isPro: appState.isPro)
        case .crypto:
            return EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
        default:
            return true
        }
    }

    private func marketCategoryPaywallMessage(for category: InvestmentCategory) -> LocalizedTextResolver {
        switch category {
        case .stocks:
            return .key("monetization.finance.stocks.pro_only")
        case .crypto:
            return .key("monetization.finance.crypto.pro_only")
        default:
            return .key("monetization.finance.market_assets.pro_only")
        }
    }

    private var deleteConfirmationTitle: String {
        let name = viewModel.state.editingInvestment?.name
            ?? L("finances.dynamics.chart.account_fallback")
        return FinanceDeleteProductCopy.confirmationTitle(for: .investment, name: name)
    }

    private var deleteActionTitle: LocalizedStringResource {
        FinanceDeleteProductCopy.actionTitle(for: .investment)
    }

    private var deleteConfirmationMessageKey: LocalizedStringResource {
        FinanceDeleteProductCopy.confirmationMessage(for: .investment)
    }
}
