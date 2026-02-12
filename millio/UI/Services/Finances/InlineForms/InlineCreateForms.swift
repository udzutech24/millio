//
//  InlineCreateForms.swift
//  millio
//

import SwiftUI

// MARK: - Inline Create Forms

struct InlineCardCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: CardViewModel
    @Binding var name: String
    let onCardDataChanged: (Card) -> Void
    let groupSection: GroupSection
    
    @State private var card: Card
    @State private var creditLimitText: String = ""
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    
    init(
        viewModel: CardViewModel,
        name: Binding<String>,
        onCardDataChanged: @escaping (Card) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self._name = name
        self.onCardDataChanged = onCardDataChanged
        self.groupSection = groupSection()
        _card = State(initialValue: Card(
            name: name.wrappedValue,
            cardNumber: "",
            bank: .other,
            cardType: .debit,
            priority: .normal,
            currency: "RUB",
            balance: 0.0
        ))
    }
    
    var currentCard: Card {
        let result = card
        result.name = name
        if result.cardType == .credit, let limit = Double(creditLimitText.replacingOccurrences(of: ",", with: ".")) {
            result.creditLimit = limit
        }
        return result
    }
    
    var isValid: Bool { !name.isEmpty }
    
    var body: some View {
        VStack(spacing: 18) {
            cardNumberSection
            typeSection
            balanceSection
            organizationSection
            groupSection
            calculationsSection
            prioritySection
        }
        .onAppear { loadAvailableCurrencies() }
        .onChange(of: name) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.cardNumber) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.bankRaw) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.cardTypeRaw) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.currency) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.balance) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: creditLimitText) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.priority) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.isFavorite) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.includeInTotal) { _, _ in onCardDataChanged(currentCard) }
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(
                    allCodes: availableCurrencies,
                    searchText: $currencySearchText,
                    selectedCodes: [],
                    favoriteCodes: [],
                    currentSelection: card.currency,
                    onToggleFavorite: nil,
                    onSelect: { currency in
                        card.currency = currency
                        showCurrencyPicker = false
                    }
                )
                .navigationTitle("Выбор валюты")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { showCurrencyPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var accentColor: Color { AppColors.financesGradient.first ?? AppColors.brandPrimary }
    
    private var cardNumberSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Номер карты")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "number")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 22)
                    
                    Text("Последние 4 цифры")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Spacer()
                    
                    TextField("0000", text: Binding(
                        get: { card.cardNumber },
                        set: { newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count <= 4 { card.cardNumber = filtered }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип")
            FinancesGlassCard {
                Menu {
                    Button {
                        card.cardTypeRaw = CardType.debit.rawValue
                    } label: {
                        Label("Дебетовая", systemImage: "creditcard")
                    }
                    Button {
                        card.cardTypeRaw = CardType.credit.rawValue
                    } label: {
                        Label("Кредитная", systemImage: "banknote")
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text("Тип карты")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Text(card.cardTypeRaw == CardType.debit.rawValue ? "Дебетовая" : "Кредитная")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
            }
        }
        .onChange(of: card.cardTypeRaw) { _, newValue in
            if newValue == CardType.debit.rawValue {
                card.creditLimit = nil
                creditLimitText = ""
            }
        }
    }
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Баланс")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Сумма")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", value: $card.balance, format: .number)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Валюта")
                            .font(.system(size: 16, weight: .medium))
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
                                    Text(card.currency)
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    if card.cardType == .credit {
                        FinancesRowDivider(leadingPadding: 16)
                        
                        HStack(spacing: 12) {
                            Text("Лимит")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: $creditLimitText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                                .onChange(of: creditLimitText) { _, newValue in
                                    if let limit = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                                        card.creditLimit = limit
                                    } else if newValue.isEmpty {
                                        card.creditLimit = nil
                                    }
                                }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Организация")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Text("Банк")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(Bank.allCases, id: \.rawValue) { bank in
                            Button(bank.displayName) { card.bankRaw = bank.rawValue }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(Bank(rawValue: card.bankRaw)?.displayName ?? Bank.other.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var calculationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Учитывать в «Итого»", isOn: $card.includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Определяет, как изменение баланса влияет на общий итог по всем продуктам.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Приоритет")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Избранная", isOn: $card.isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    FinancesRowDivider(leadingPadding: 0)
                    
                    HStack(spacing: 12) {
                        FinancesRadioOption(title: "низкий", isSelected: card.priority == .low) { card.priority = .low }
                        FinancesRadioOption(title: "обычный", isSelected: card.priority == .normal) { card.priority = .normal }
                        FinancesRadioOption(title: "высокий", isSelected: card.priority == .high) { card.priority = .high }
                    }
                    
                    Text("Высокий приоритет — выше в списках.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                }
            }
        }
    }
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(card.currency) { currencies.append(card.currency) }
            availableCurrencies = currencies.sorted()
        }
    }
}

struct InlineCreditCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: CreditViewModel
    @Binding var name: String
    let onCreditDataChanged: ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var amountText: String = ""
    @State private var remainingAmountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var selectedBank: Bank = .other
    @State private var selectedCreditType: CreditType = .consumer
    @State private var isFavorite: Bool = false
    @State private var includeInTotal: Bool = true
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    
    init(
        viewModel: CreditViewModel,
        name: Binding<String>,
        onCreditDataChanged: @escaping ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)?) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self._name = name
        self.onCreditDataChanged = onCreditDataChanged
        self.groupSection = groupSection()
    }
    
    var isValid: Bool {
        !name.isEmpty &&
        parseNumber(amountText) != nil && parseNumber(amountText)! > 0 &&
        parseNumber(remainingAmountText) != nil && parseNumber(remainingAmountText)! >= 0
    }
    
    func getCreditData() -> (name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)? {
        guard let amount = parseNumber(amountText),
              let remainingAmount = parseNumber(remainingAmountText) else { return nil }
        // Дефолты для упрощенной формы: срок 12 месяцев от текущей даты
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let monthlyPayment = amount / 12.0
        return (name, amount, monthlyPayment, endDate, remainingAmount, selectedCurrency, selectedBank, selectedCreditType, isFavorite, includeInTotal)
    }
    
    var body: some View {
        VStack(spacing: 18) {
            typeSection
            balanceSection
            organizationSection
            groupSection
            calculationsSection
            prioritySection
        }
        .onAppear { loadAvailableCurrencies() }
        .onChange(of: name) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: amountText) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: remainingAmountText) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: selectedCurrency) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: selectedBank) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: selectedCreditType) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: isFavorite) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: includeInTotal) { _, _ in onCreditDataChanged(getCreditData()) }
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(
                    allCodes: availableCurrencies,
                    searchText: $currencySearchText,
                    selectedCodes: [],
                    favoriteCodes: [],
                    currentSelection: selectedCurrency,
                    onToggleFavorite: nil,
                    onSelect: { currency in
                        selectedCurrency = currency
                        showCurrencyPicker = false
                    }
                )
                .navigationTitle("Выбор валюты")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { showCurrencyPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Text("Тип кредита")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(CreditType.allCases, id: \.self) { type in
                            Button(type.displayName) { selectedCreditType = type }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedCreditType.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Баланс")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Сумма")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Остаток")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(remainingAmountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                remainingAmountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Валюта")
                            .font(.system(size: 16, weight: .medium))
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
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Организация")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Text("Банк")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(Bank.allCases, id: \.self) { bank in
                            Button(bank.displayName) { selectedBank = bank }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedBank.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var calculationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Учитывать в «Итого»", isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Определяет, как изменение баланса влияет на общий итог по всем продуктам.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) { currencies.append(selectedCurrency) }
            availableCurrencies = currencies.sorted()
        }
    }
    
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Приоритет")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)) {
                Toggle("В избранном", isOn: $isFavorite)
                    .tint(AppColors.toggleOnGreen)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }

    private func parseNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    private func formatNumberForDisplay(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let number = parseNumber(text) else { return text }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let hasDecimal = normalized.contains(".")
        if !hasDecimal { formatter.maximumFractionDigits = 0 }
        
        return formatter.string(from: NSNumber(value: number)) ?? text
    }
}

struct InlineInvestmentCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: InvestmentViewModel
    @Binding var name: String
    let onInvestmentDataChanged: ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var selectedInvestmentType: InvestmentType = .positive
    @State private var selectedCategory: InvestmentCategory = .other
    @State private var amountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var includeInTotal: Bool = true
    @State private var selectedPriority: InvestmentPriority = .normal
    @State private var isFavorite: Bool = false
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    @State private var marketSymbol: String = ""
    @State private var marketExchange: String?
    @State private var marketCurrency: String?
    @State private var marketQuantityText: String = ""
    @State private var lastKnownUnitPrice: Double?
    @State private var lastKnownPriceUpdatedAt: Date?
    @State private var marketProviderRaw: String?
    @State private var showMarketSearchSheet: Bool = false
    @State private var isRefreshingPrice: Bool = false
    @State private var marketErrorMessage: String?
    
    private let marketDataClient: MarketDataClientProtocol
    
    init(
        viewModel: InvestmentViewModel,
        name: Binding<String>,
        onInvestmentDataChanged: @escaping ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?) -> Void,
        marketDataClient: MarketDataClientProtocol = TwelveDataClient.shared,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self._name = name
        self.onInvestmentDataChanged = onInvestmentDataChanged
        self.marketDataClient = marketDataClient
        self.groupSection = groupSection()
    }
    
    private var isMarketCategory: Bool {
        selectedCategory == .stocks || selectedCategory == .crypto
    }
    
    private var marketFilter: MarketSymbolFilter {
        selectedCategory == .crypto ? .crypto : .stocks
    }
    
    private var positionTotal: Double? {
        guard let quantity = parseNumber(marketQuantityText),
              let unitPrice = lastKnownUnitPrice else {
            return nil
        }
        return quantity * unitPrice
    }
    
    var isValid: Bool {
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
    
    func getInvestmentData() -> (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)? {
        if isMarketCategory {
            guard let quantity = parseNumber(marketQuantityText),
                  quantity > 0 else {
                return nil
            }
            
            let effectiveAmount = positionTotal ?? parseNumber(amountText) ?? 0.0
            let effectiveCurrency = (marketCurrency?.isEmpty == false) ? marketCurrency! : selectedCurrency
            let marketData = InvestmentMarketData(
                symbol: marketSymbol.isEmpty ? nil : marketSymbol,
                exchange: marketExchange,
                currency: marketCurrency ?? selectedCurrency,
                quantity: quantity,
                unitPrice: lastKnownUnitPrice,
                priceUpdatedAt: lastKnownPriceUpdatedAt,
                providerRaw: marketProviderRaw
            )
            
            return (
                name,
                selectedInvestmentType,
                selectedCategory,
                effectiveAmount,
                effectiveCurrency,
                includeInTotal,
                selectedPriority,
                isFavorite,
                marketData,
                false
            )
        }
        
        guard let amount = parseNumber(amountText) else {
            return nil
        }
        
        return (
            name,
            selectedInvestmentType,
            selectedCategory,
            amount,
            selectedCurrency,
            includeInTotal,
            selectedPriority,
            isFavorite,
            nil,
            true
        )
    }
    
    var body: some View {
        VStack(spacing: 18) {
            if isMarketCategory {
                marketInstrumentSection
                marketPositionSection
            } else {
                balanceSection
            }
            organizationSection
            groupSection
            calculationsSection
            prioritySection
        }
        .onAppear { loadAvailableCurrencies() }
        .onChange(of: name) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: amountText) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedCurrency) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedCategory) { _, newValue in
            if !(newValue == .stocks || newValue == .crypto) {
                clearMarketState()
            }
            onInvestmentDataChanged(getInvestmentData())
        }
        .onChange(of: selectedPriority) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedInvestmentType) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: isFavorite) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: includeInTotal) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: marketQuantityText) { _, _ in
            if let total = positionTotal {
                amountText = String(total)
            }
            onInvestmentDataChanged(getInvestmentData())
        }
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencyPickerView(
                    allCodes: availableCurrencies,
                    searchText: $currencySearchText,
                    selectedCodes: [],
                    favoriteCodes: [],
                    currentSelection: selectedCurrency,
                    onToggleFavorite: nil,
                    onSelect: { currency in
                        selectedCurrency = currency
                        showCurrencyPicker = false
                    }
                )
                .navigationTitle("Выбор валюты")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { showCurrencyPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMarketSearchSheet) {
            MarketSymbolSearchSheet(filter: marketFilter) { symbol in
                applySelectedMarketSymbol(symbol)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
    
    private var marketInstrumentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.market.section_symbol"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(marketInstrumentTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(marketSymbol.isEmpty ? "—" : marketSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Button {
                            showMarketSearchSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                Text(marketSearchButtonTitle)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
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
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var marketPositionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.market.section_position"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(marketQuantityTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(marketQuantityText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                marketQuantityText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text(String(localized: "finances.market.field_unit_price"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isRefreshingPrice {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppColors.textTertiary)
                        } else {
                            Text(formatOptionalPrice(lastKnownUnitPrice))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        Button {
                            refreshLatestPrice(forceRefresh: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .disabled(marketSymbol.isEmpty || isRefreshingPrice)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text(String(localized: "finances.market.field_position_total"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(formatOptionalPrice(positionTotal))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
            
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
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Баланс")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Сумма")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Валюта")
                            .font(.system(size: 16, weight: .medium))
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
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Организация")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Категория")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Menu {
                            ForEach(InvestmentCategory.allCases, id: \.self) { category in
                                Button(category.displayName) { selectedCategory = category }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedCategory.displayName)
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var calculationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Учитывать в «Итого»", isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    HStack(spacing: 12) {
                        FinancesCheckboxOption(
                            title: "увеличивает",
                            isSelected: selectedInvestmentType == .positive,
                            onTap: { selectedInvestmentType = .positive }
                        )
                        FinancesCheckboxOption(
                            title: "уменьшает",
                            isSelected: selectedInvestmentType == .negative,
                            onTap: { selectedInvestmentType = .negative }
                        )
                    }
                    
                    Text("Определяет, как изменение баланса влияет на общий итог по всем продуктам.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Приоритет")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("В избранном", isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    FinancesRowDivider(leadingPadding: 0)
                    
                    HStack(spacing: 12) {
                        FinancesRadioOption(title: "низкий", isSelected: selectedPriority == .low) { selectedPriority = .low }
                        FinancesRadioOption(title: "обычный", isSelected: selectedPriority == .normal) { selectedPriority = .normal }
                        FinancesRadioOption(title: "высокий", isSelected: selectedPriority == .high) { selectedPriority = .high }
                    }
                    
                    Text("Высокий приоритет — выше в списках.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                }
            }
        }
    }
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) { currencies.append(selectedCurrency) }
            availableCurrencies = currencies.sorted()
        }
    }
    
    private func parseNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
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
                    if let positionTotal {
                        amountText = String(positionTotal)
                    }
                    onInvestmentDataChanged(getInvestmentData())
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
        
        // В MVP используем тикер как название актива для единообразия.
        name = symbol.symbol
        
        refreshLatestPrice(forceRefresh: true)
        onInvestmentDataChanged(getInvestmentData())
    }
    
    private func clearMarketState() {
        marketSymbol = ""
        marketExchange = nil
        marketCurrency = nil
        marketQuantityText = ""
        lastKnownUnitPrice = nil
        lastKnownPriceUpdatedAt = nil
        marketProviderRaw = nil
        marketErrorMessage = nil
    }
    
    private func formatOptionalPrice(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }
        return "\(formatNumberForDisplay(String(value))) \(marketCurrency ?? selectedCurrency)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatNumberForDisplay(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let number = parseNumber(text) else { return text }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let hasDecimal = normalized.contains(".")
        if !hasDecimal { formatter.maximumFractionDigits = 0 }
        
        return formatter.string(from: NSNumber(value: number)) ?? text
    }
}
