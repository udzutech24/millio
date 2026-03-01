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

    @State private var name: String = ""
    @State private var selectedInvestmentType: InvestmentType = .positive
    @State private var selectedCategory: InvestmentCategory = .other
    @State private var amountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var includeInTotal: Bool = true
    @State private var selectedPriority: InvestmentPriority = .normal
    @State private var isFavorite: Bool = false
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false

    @State private var marketSymbol: String = ""
    @State private var marketExchange: String?
    @State private var marketCurrency: String?
    @State private var marketQuantityText: String = ""
    @State private var purchaseUnitPriceText: String = ""
    @State private var lastKnownUnitPrice: Double?
    @State private var lastKnownPriceUpdatedAt: Date?
    @State private var marketProviderRaw: String?
    @State private var showMarketSearchSheet: Bool = false
    @State private var isRefreshingPrice: Bool = false
    @State private var marketErrorMessage: String?

    private let marketDataClient: MarketDataClientProtocol

    init(
        viewModel: InvestmentViewModel,
        marketDataClient: MarketDataClientProtocol = TwelveDataClient.shared,
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
            .navigationTitle(viewModel.state.editingInvestment == nil ? "Новый актив" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
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
                        Button("Удалить", role: .destructive) {
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
                    marketCurrency = editing.marketCurrency
                    marketQuantityText = editing.marketQuantity.map { String($0) } ?? ""
                    purchaseUnitPriceText = editing.averagePurchaseUnitPrice.map { String($0) } ?? ""
                    lastKnownUnitPrice = editing.lastKnownUnitPrice
                    lastKnownPriceUpdatedAt = editing.lastKnownPriceUpdatedAt
                    marketProviderRaw = editing.marketProviderRaw
                }

                loadAvailableCurrencies()
            }
            .onChange(of: selectedCategory) { _, newValue in
                if !(newValue == .stocks || newValue == .crypto) {
                    clearMarketState()
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
        }
    }
    
    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Основная информация")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    TextField("Название актива", text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var investmentParamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Параметры актива")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Тип актива")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Тип актива", selection: $selectedInvestmentType) {
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
                        Text("Категория")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isEditingMarketAssetWithLockedIdentity {
                            Text(selectedCategory.displayName)
                                .foregroundStyle(AppColors.textTertiary)
                        } else {
                            Picker("Категория", selection: $selectedCategory) {
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
                        showMarketSearchSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text(marketSearchButtonTitle)
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.investmentsGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
                Text("Цена покупки")
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
                Text("Сумма")
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
                Text("Валюта")
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if isLoadingCurrencies {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppColors.textTertiary)
                } else {
                    Picker("Валюта", selection: $selectedCurrency) {
                        ForEach(availableCurrencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                    .tint(AppColors.textTertiary)
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
            FinancesSectionHeader(title: "Дополнительно")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Приоритет")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Приоритет", selection: $selectedPriority) {
                            ForEach(InvestmentPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    Toggle("В избранном", isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    Toggle("Учитывать в общих", isOn: $includeInTotal)
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

            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")

            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)

            if !currencies.contains(selectedCurrency) {
                currencies.append(selectedCurrency)
            }

            await MainActor.run {
                availableCurrencies = currencies.sorted()
                isLoadingCurrencies = false
            }
        }
    }

    private func refreshLatestPrice(forceRefresh: Bool) {
        guard !marketSymbol.isEmpty else {
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
                let latestPrice = try await marketDataClient.latestPrice(
                    symbol: marketSymbol,
                    forceRefresh: forceRefresh
                )

                await MainActor.run {
                    lastKnownUnitPrice = latestPrice
                    lastKnownPriceUpdatedAt = latestPrice == nil ? nil : Date()
                    marketProviderRaw = latestPrice == nil ? nil : "twelvedata"
                    if let latestPrice, purchaseUnitPriceText.isEmpty {
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
        marketCurrency = symbol.currency
        selectedCurrency = symbol.currency ?? selectedCurrency
        marketProviderRaw = "twelvedata"

        // В MVP используем тикер как название актива, чтобы не усложнять UX.
        name = symbol.symbol

        refreshLatestPrice(forceRefresh: true)
    }

    private func clearMarketState() {
        marketSymbol = ""
        marketExchange = nil
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
}
