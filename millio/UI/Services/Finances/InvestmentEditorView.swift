//
//  InvestmentEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 27.01.2026.
//

import SwiftUI

// MARK: - Investment Editor View

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
    @State private var showPaywallAlert = false
    @State private var paywallMessage = ""
    @State private var showCryptoProAlert = false

    private let marketDataClient: MarketDataClientProtocol

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
            ? String(localized: "finances.add_account.hint.select_coin_or_pair")
            : String(localized: "finances.add_account.hint.select_ticker")
    }

    private var positionTotal: Double? {
        guard let quantity = parseNumber(marketQuantityText),
              let unitPrice = lastKnownUnitPrice else {
            return nil
        }
        return quantity * unitPrice
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        mainInfoSection
                        investmentParamsSection
                        additionalSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
            }
            .navigationTitle(
                viewModel.state.editingInvestment == nil
                    ? String(localized: "finances.editor.investment.new_title")
                    : String(localized: "finances.editor.investment.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "finances.common.cancel")) {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "finances.common.save")) {
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

                if onDelete != nil, viewModel.state.editingInvestment != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized: "finances.common.delete"), role: .destructive) {
                            onDelete?()
                        }
                    }
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
                    marketExchange = editing.marketExchange
                    marketQuoteLookupKey = editing.marketQuoteLookupKey
                    marketMICCode = editing.marketMICCode
                    marketCurrency = editing.marketCurrency
                    marketQuantityText = editing.marketQuantity.map { String($0) } ?? ""
                    purchaseUnitPriceText = editing.averagePurchaseUnitPrice.map { String($0) } ?? ""
                    lastKnownUnitPrice = editing.lastKnownUnitPrice
                    lastKnownPriceUpdatedAt = editing.lastKnownPriceUpdatedAt
                    marketProviderRaw = editing.marketProviderRaw
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
                    .navigationTitle(String(localized: "finances.add_account.currency_picker.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "finances.common.cancel")) {
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
                titleKey: "Ограничение Free-плана",
                message: paywallMessage,
                onSubscribe: { router.push(.subscription) }
            )
            .premiumUpsellAlert(
                isPresented: $showCryptoProAlert,
                titleKey: "monetization.crypto.pro_title",
                message: String(localized: "monetization.crypto.pro_message"),
                onSubscribe: { router.push(.subscription) }
            )
        }
    }
    
    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.editor.section.main_info"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    TextField(String(localized: "finances.editor.investment.name_placeholder"), text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var investmentParamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.editor.investment.params_section"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "finances.editor.investment.type_label"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(String(localized: "finances.editor.investment.type_label"), selection: $selectedInvestmentType) {
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
                        Text(String(localized: "finances.editor.investment.category_label"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isEditingMarketAssetWithLockedIdentity {
                            Text(selectedCategory.displayName)
                                .foregroundStyle(AppColors.textTertiary)
                        } else {
                            Picker(String(localized: "finances.editor.investment.category_label"), selection: $selectedCategory) {
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
                    get: { formatNumberForDisplay(marketQuantityText) },
                    set: { newValue in
                        let sanitized = AmountInputFormatter.sanitize(newValue)
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
                Text(String(localized: "finances.market.field_unit_price"))
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
                Text(String(localized: "finances.add_account.investment.purchase_price"))
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
                Text(String(localized: "finances.market.field_position_total"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(formatOptionalPrice(positionTotal))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            FinancesRowDivider()

            HStack {
                Text(String(localized: "finances.market.field_quote_currency"))
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
                Text(String(localized: "finances.add_account.field.amount"))
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
                Text(String(localized: "finances.add_account.field.currency"))
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
                Text("\(String(localized: "finances.market.price_updated_prefix")) \(formatDate(lastKnownPriceUpdatedAt))")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                    .padding(.horizontal, 4)
            }
        }
    }
    
    private var additionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.editor.section.additional"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "finances.add_account.section.priority"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(String(localized: "finances.add_account.section.priority"), selection: $selectedPriority) {
                            ForEach(InvestmentPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    Toggle(String(localized: "finances.add_account.favorite"), isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    Toggle(String(localized: "finances.add_account.total_impact.include"), isOn: $includeInTotal)
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
                  let quantity = parseNumber(marketQuantityText) else {
                return false
            }
            return quantity > 0
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
        let lookupKey = marketQuoteLookupKey ?? MarketInstrumentIdentity.canonicalQuoteLookupKey(
            symbol: marketSymbol,
            exchange: marketExchange
        )
        guard !lookupKey.isEmpty else {
            return
        }

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
                    symbol: lookupKey,
                    forceRefresh: forceRefresh
                )

                await MainActor.run {
                    lastKnownUnitPrice = latestQuote?.price
                    lastKnownPriceUpdatedAt = latestQuote?.updatedAtDate ?? (latestQuote == nil ? nil : Date())
                    marketQuoteLookupKey = latestQuote?.canonicalQuoteLookupKey ?? lookupKey
                    marketMICCode = latestQuote?.micCode ?? marketMICCode
                    marketProviderRaw = latestQuote == nil ? nil : "market-backend"
                    if let latestPrice = latestQuote?.price, purchaseUnitPriceText.isEmpty {
                        purchaseUnitPriceText = String(latestPrice)
                    }
                    if let positionTotal {
                        amountText = String(positionTotal)
                    }
                }
            } catch {
                await MainActor.run {
                    marketErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applySelectedMarketSymbol(_ symbol: TwelveDataSymbol) {
        marketSymbol = symbol.symbol
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
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }

    private func formatNumberForDisplay(_ text: String) -> String {
        AmountInputFormatter.display(text)
    }

    private func saveInvestment() {
        guard validateEntitlementsForSave() else { return }

        let effectiveAmount: Double
        let marketData: InvestmentMarketData?
        let createCashflowTransaction: Bool
        let effectiveCategory: InvestmentCategory

        if isMarketCategory {
            guard let quantity = parseNumber(marketQuantityText), quantity > 0 else {
                return
            }

            effectiveAmount = positionTotal ?? parseNumber(amountText) ?? (viewModel.state.editingInvestment?.amount ?? 0)
            let effectiveCurrency = (marketCurrency?.isEmpty == false) ? marketCurrency! : selectedCurrency
            let lockedCategory = viewModel.state.editingInvestment?.category
            let lockedSymbol = viewModel.state.editingInvestment?.marketSymbol

            marketData = InvestmentMarketData(
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
            uniqueID: nil
        ))

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
            paywallMessage = String(
                format: String(localized: "monetization.ticker.limit.hard_format"),
                EntitlementPolicy.freeTrackedTickerLimit
            )
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

    private func marketCategoryPaywallMessage(for category: InvestmentCategory) -> String {
        switch category {
        case .stocks:
            return String(localized: "monetization.finance.stocks.pro_only")
        case .crypto:
            return String(localized: "monetization.finance.crypto.pro_only")
        default:
            return String(localized: "monetization.finance.market_assets.pro_only")
        }
    }
}
