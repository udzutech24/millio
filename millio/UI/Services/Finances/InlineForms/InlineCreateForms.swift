//
//  InlineCreateForms.swift
//  millio
//

import SwiftUI

// MARK: - Inline Create Forms

struct InlineCardCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: CardViewModel
    let onCardDataChanged: (Card) -> Void
    let groupSection: GroupSection
    
    @State private var card: Card
    @State private var creditLimitText: String = ""
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    init(
        viewModel: CardViewModel,
        onCardDataChanged: @escaping (Card) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self.onCardDataChanged = onCardDataChanged
        self.groupSection = groupSection()
        _card = State(initialValue: Card(
            name: "",
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
        if result.cardType == .credit, let limit = Double(creditLimitText.replacingOccurrences(of: ",", with: ".")) {
            result.creditLimit = limit
        }
        return result
    }
    
    var isValid: Bool { !card.name.isEmpty }
    
    var body: some View {
        VStack(spacing: 18) {
            nameSection
            typeSection
            balanceSection
            organizationSection
            groupSection
            calculationsSection
            prioritySection
        }
        .onAppear { loadAvailableCurrencies() }
        .onChange(of: card.name) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.cardNumber) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.bankRaw) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.cardTypeRaw) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.currency) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.balance) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: creditLimitText) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.priority) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.isFavorite) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.includeInTotal) { _, _ in onCardDataChanged(currentCard) }
    }
    
    private var accentColor: Color { AppColors.financesGradient.first ?? AppColors.brandPrimary }
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Название")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 22)
                        
                        TextField("Например, Тинькофф Black", text: $card.name)
                            .foregroundStyle(AppColors.textPrimary)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
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
    }
    
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Тип продукта")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("Карта")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        FinancesCheckboxOption(
                            title: "дебетовая",
                            isSelected: card.cardTypeRaw == CardType.debit.rawValue,
                            onTap: { card.cardTypeRaw = CardType.debit.rawValue }
                        )
                        
                        FinancesCheckboxOption(
                            title: "кредитная",
                            isSelected: card.cardTypeRaw == CardType.credit.rawValue,
                            onTap: { card.cardTypeRaw = CardType.credit.rawValue }
                        )
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
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
                            Menu {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Button(currency) { card.currency = currency }
                                }
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
                    
                    Toggle("Избранная", isOn: $card.isFavorite)
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
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                VStack(alignment: .leading, spacing: 12) {
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
    let onCreditDataChanged: ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var remainingAmountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var selectedBank: Bank = .other
    @State private var selectedCreditType: CreditType = .consumer
    @State private var isFavorite: Bool = false
    @State private var includeInTotal: Bool = true
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    init(
        viewModel: CreditViewModel,
        onCreditDataChanged: @escaping ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)?) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
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
            FinancesSectionHeader(title: "Название")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 22)
                    
                    TextField("Например, Потребительский кредит", text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            
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
                            Menu {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Button(currency) { selectedCurrency = currency }
                                }
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
            
            groupSection
            
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Учитывать в «Итого»", isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Toggle("В избранном", isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
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
    let onInvestmentDataChanged: ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool)?) -> Void
    let groupSection: GroupSection
    
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
    
    init(
        viewModel: InvestmentViewModel,
        onInvestmentDataChanged: @escaping ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool)?) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self.onInvestmentDataChanged = onInvestmentDataChanged
        self.groupSection = groupSection()
    }
    
    var isValid: Bool { !name.isEmpty && parseNumber(amountText) != nil && parseNumber(amountText)! > 0 }
    
    func getInvestmentData() -> (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool)? {
        guard let amount = parseNumber(amountText) else { return nil }
        return (name, selectedInvestmentType, selectedCategory, amount, selectedCurrency, includeInTotal, selectedPriority, isFavorite)
    }
    
    var body: some View {
        VStack(spacing: 18) {
            FinancesSectionHeader(title: "Название")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 22)
                    
                    TextField("Например, Наличные", text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            
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
                            Menu {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Button(currency) { selectedCurrency = currency }
                                }
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
            
            groupSection
            
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
                    
                    Toggle("В избранном", isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Определяет, как изменение баланса влияет на общий итог по всем продуктам.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            FinancesSectionHeader(title: "Приоритет")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                VStack(alignment: .leading, spacing: 12) {
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
        .onAppear { loadAvailableCurrencies() }
        .onChange(of: name) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedInvestmentType) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedCategory) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: amountText) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedCurrency) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: includeInTotal) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedPriority) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: isFavorite) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
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
