//
//  InlineCreateForms.swift
//  millio
//

import SwiftUI

// MARK: - Inline Create Forms

struct InlineCardCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: CardViewModel
    @Binding var name: String
    let selectedProductType: FinanceAccountType
    let selectedInvestmentCategory: InvestmentCategory
    let onProductTypeSelected: (FinanceAccountType) -> Void
    let onProductTitleSelected: (String) -> Void
    let onInvestmentCategorySelected: (InvestmentCategory) -> Void
    let onCardDataChanged: (Card) -> Void
    let groupSection: GroupSection
    
    @State private var card: Card
    @State private var balanceText: String = ""
    @State private var balanceDisplayText: String = ""
    @State private var creditLimitText: String = ""
    @State private var creditDebtText: String = ""
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    
    init(
        viewModel: CardViewModel,
        name: Binding<String>,
        selectedProductType: FinanceAccountType,
        selectedInvestmentCategory: InvestmentCategory,
        onProductTypeSelected: @escaping (FinanceAccountType) -> Void,
        onProductTitleSelected: @escaping (String) -> Void,
        onInvestmentCategorySelected: @escaping (InvestmentCategory) -> Void,
        onCardDataChanged: @escaping (Card) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self._name = name
        self.selectedProductType = selectedProductType
        self.selectedInvestmentCategory = selectedInvestmentCategory
        self.onProductTypeSelected = onProductTypeSelected
        self.onProductTitleSelected = onProductTitleSelected
        self.onInvestmentCategorySelected = onInvestmentCategorySelected
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
        _balanceText = State(initialValue: "")
        _balanceDisplayText = State(initialValue: "")
    }
    
    var currentCard: Card {
        let result = card
        result.name = name
        if result.cardType == .credit {
            let limit = AmountInputFormatter.parse(creditLimitText) ?? 0
            let debt = AmountInputFormatter.parse(creditDebtText) ?? 0
            result.creditLimit = creditLimitText.isEmpty ? nil : limit
            result.balance = max(0, limit - debt)
            result.includeInTotal = true
        } else {
            if let balance = AmountInputFormatter.parse(balanceText) {
                result.balance = balance
            }
            result.creditLimit = nil
        }
        return result
    }
    
    var isValid: Bool { !name.isEmpty }
    
    var body: some View {
        VStack(spacing: 18) {
            typeSection
            balanceSection
            groupSection
            calculationsSection
            prioritySection
        }
        .onAppear {
            loadAvailableCurrencies()
            if balanceDisplayText.isEmpty {
                balanceDisplayText = AmountInputFormatter.display(balanceText)
            }
        }
        .onChange(of: name) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.cardTypeRaw) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.currency) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: balanceText) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: balanceDisplayText) { _, newValue in
            let sanitized = AmountInputFormatter.sanitize(newValue)
            let formatted = AmountInputFormatter.display(sanitized)
            if newValue != formatted {
                balanceDisplayText = formatted
            }
            balanceText = sanitized
            card.balance = AmountInputFormatter.parse(sanitized) ?? 0
        }
        .onChange(of: creditLimitText) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: creditDebtText) { _, _ in onCardDataChanged(currentCard) }
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var accentColor: Color { AppColors.financesGradient.first ?? AppColors.brandPrimary }
    
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Menu {
                        Button {
                            onProductTitleSelected(FinanceAccountType.card.displayName)
                            onProductTypeSelected(.card)
                        } label: {
                            Label(FinanceAccountType.card.displayName, systemImage: FinanceAccountType.card.icon)
                        }
                        Button {
                            onProductTitleSelected("Счет")
                            onInvestmentCategorySelected(.other)
                            onProductTypeSelected(.investment)
                        } label: {
                            Label("Счет", systemImage: "building.columns.fill")
                        }

                        Button {
                            onProductTitleSelected(FinanceAccountType.credit.displayName)
                            onProductTypeSelected(.credit)
                        } label: {
                            Label(FinanceAccountType.credit.displayName, systemImage: FinanceAccountType.credit.icon)
                        }
                        Button {
                            onProductTitleSelected("Актив")
                            onInvestmentCategorySelected(.other)
                            onProductTypeSelected(.investment)
                        } label: {
                            Label("Актив", systemImage: FinanceAccountType.investment.icon)
                        }

                        ForEach(visibleInvestmentCategories, id: \.self) { category in
                            Button {
                                onProductTitleSelected(category.displayName)
                                onInvestmentCategorySelected(category)
                                onProductTypeSelected(.investment)
                            } label: {
                                Label(category.displayName, systemImage: category.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("Тип продукта")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()

                            HStack(spacing: 6) {
                                Text(selectedProductTypeDisplayName)
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

                    FinancesRowDivider(leadingPadding: 16)

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
        }
        .onChange(of: card.cardTypeRaw) { _, newValue in
            if newValue == CardType.debit.rawValue {
                card.creditLimit = nil
                creditLimitText = ""
                creditDebtText = ""
            } else {
                card.includeInTotal = true
                let limit = AmountInputFormatter.parse(creditLimitText) ?? card.creditLimit ?? 0
                if creditLimitText.isEmpty {
                    creditLimitText = AmountInputFormatter.plainString(from: limit)
                }
                let debt = max(0, limit - card.balance)
                creditDebtText = AmountInputFormatter.plainString(from: debt)
            }
        }
    }

    private var selectedProductTypeDisplayName: String {
        guard selectedProductType == .investment else {
            return selectedProductType.displayName
        }
        return selectedInvestmentCategory.displayName
    }

    private var visibleInvestmentCategories: [InvestmentCategory] {
        [.house, .stocks, .business, .debt, .crypto, .other]
    }
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Баланс")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    if card.cardType == .credit {
                        HStack(spacing: 12) {
                            Text("Кредитный лимит")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { AmountInputFormatter.display(creditLimitText) },
                                set: { newValue in
                                    let sanitized = AmountInputFormatter.sanitize(newValue)
                                    creditLimitText = sanitized
                                    let limit = AmountInputFormatter.parse(creditLimitText) ?? 0
                                    let debt = AmountInputFormatter.parse(creditDebtText) ?? 0
                                    card.creditLimit = creditLimitText.isEmpty ? nil : limit
                                    card.balance = max(0, limit - debt)
                                }
                            ))
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)

                        FinancesRowDivider(leadingPadding: 16)
                        
                        HStack(spacing: 12) {
                            Text("Общий долг")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { AmountInputFormatter.display(creditDebtText) },
                                set: { newValue in
                                    let sanitized = AmountInputFormatter.sanitize(newValue)
                                    creditDebtText = sanitized
                                    let limit = AmountInputFormatter.parse(creditLimitText) ?? 0
                                    let debt = AmountInputFormatter.parse(creditDebtText) ?? 0
                                    card.balance = max(0, limit - debt)
                                }
                            ))
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)

                        FinancesRowDivider(leadingPadding: 16)

                        HStack(spacing: 12) {
                            Text("Остаток лимита")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text(AmountInputFormatter.display(String(creditRemainingLimit)))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    } else {
                        HStack(spacing: 12) {
                            Text("Сумма")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: $balanceDisplayText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }

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
                }
            }
        }
    }
    
    private var calculationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    if card.cardType == .credit {
                        HStack(spacing: 10) {
                            Text("Влияние на «Итого»")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text("Уменьшает")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.error.opacity(0.9))
                        }
                    } else {
                        Toggle("Учитывать в «Итого»", isOn: $card.includeInTotal)
                            .tint(AppColors.toggleOnGreen)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    
                    Text("Определяет, как изменение баланса влияет на общий итог по всем продуктам.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)

                    if card.cardType == .credit {
                        Text("Для учета в «Итого» используется поле «Общий долг».")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.error.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    private var creditRemainingLimit: Double {
        let limit = AmountInputFormatter.parse(creditLimitText) ?? 0
        let debt = AmountInputFormatter.parse(creditDebtText) ?? 0
        return max(0, limit - debt)
    }
}

struct InlineCreditCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: CreditViewModel
    @Binding var name: String
    let onCreditDataChanged: ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, paymentMode: CreditPaymentMode, paymentDayOfMonth: Int?, nextPaymentDate: Date?, reminderEnabled: Bool, reminderDaysBefore: Int?, reminderTime: Date?, includeInTotal: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var amountText: String = ""
    @State private var amountDisplayText: String = ""
    @State private var remainingAmountText: String = ""
    @State private var remainingAmountDisplayText: String = ""
    @State private var monthlyPaymentText: String = ""
    @State private var monthlyPaymentDisplayText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var isFavorite: Bool = false
    @State private var paymentMode: CreditPaymentMode = .dayOfMonth
    @State private var paymentDayOfMonth: Int = max(1, min(31, Calendar.current.component(.day, from: Date())))
    @State private var nextPaymentDate: Date = Date()
    @State private var reminderEnabled: Bool = false
    @State private var reminderDaysBeforeText: String = ""
    @State private var reminderDaysBeforeDisplayText: String = ""
    @State private var reminderTime: Date = InlineCreditCreateForm.defaultReminderTime()
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    
    init(
        viewModel: CreditViewModel,
        name: Binding<String>,
        onCreditDataChanged: @escaping ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, paymentMode: CreditPaymentMode, paymentDayOfMonth: Int?, nextPaymentDate: Date?, reminderEnabled: Bool, reminderDaysBefore: Int?, reminderTime: Date?, includeInTotal: Bool)?) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self._name = name
        self.onCreditDataChanged = onCreditDataChanged
        self.groupSection = groupSection()
    }
    
    var isValid: Bool {
        !name.isEmpty
    }
    
    func getCreditData() -> (name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, paymentMode: CreditPaymentMode, paymentDayOfMonth: Int?, nextPaymentDate: Date?, reminderEnabled: Bool, reminderDaysBefore: Int?, reminderTime: Date?, includeInTotal: Bool)? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let amount = parseNumber(amountText) ?? 0
        let remainingAmount = parseNumber(remainingAmountText) ?? 0
        let monthlyPayment = parseNumber(monthlyPaymentText) ?? (amount / 12.0)
        // Дефолты для упрощенной формы: срок 12 месяцев от текущей даты
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let dayOfMonth = paymentMode == .dayOfMonth ? paymentDayOfMonth : nil
        let paymentDate = paymentMode == .nextDate ? nextPaymentDate : nil
        let reminderDaysBefore = parseReminderDays(reminderDaysBeforeText)
        return (
            name,
            amount,
            monthlyPayment,
            endDate,
            remainingAmount,
            selectedCurrency,
            .other,
            .consumer,
            isFavorite,
            paymentMode,
            dayOfMonth,
            paymentDate,
            reminderEnabled,
            reminderEnabled ? reminderDaysBefore : nil,
            reminderEnabled ? reminderTime : nil,
            true
        )
    }
    
    var body: some View {
        VStack(spacing: 18) {
            balanceSection
            paymentSection
            reminderSection
            groupSection
            calculationsSection
            prioritySection
        }
        .onAppear {
            loadAvailableCurrencies()
            if amountDisplayText.isEmpty {
                amountDisplayText = formatNumberForDisplay(amountText)
            }
            if remainingAmountDisplayText.isEmpty {
                remainingAmountDisplayText = formatNumberForDisplay(remainingAmountText)
            }
            if monthlyPaymentDisplayText.isEmpty {
                monthlyPaymentDisplayText = formatNumberForDisplay(monthlyPaymentText)
            }
        }
        .onChange(of: name) { _, _ in emitCreditDataChange() }
        .onChange(of: amountDisplayText) { _, newValue in
            handleAmountDisplayChange(newValue)
        }
        .onChange(of: remainingAmountDisplayText) { _, newValue in
            handleRemainingAmountDisplayChange(newValue)
        }
        .onChange(of: monthlyPaymentDisplayText) { _, newValue in
            handleMonthlyPaymentDisplayChange(newValue)
        }
        .onChange(of: selectedCurrency) { _, _ in emitCreditDataChange() }
        .onChange(of: isFavorite) { _, _ in emitCreditDataChange() }
        .onChange(of: paymentMode) { _, newMode in
            if newMode == .dayOfMonth {
                nextPaymentDate = Date()
            }
            if newMode == .nextDate {
                paymentDayOfMonth = max(1, min(31, paymentDayOfMonth))
            }
            emitCreditDataChange()
        }
        .onChange(of: paymentDayOfMonth) { _, _ in emitCreditDataChange() }
        .onChange(of: nextPaymentDate) { _, _ in emitCreditDataChange() }
        .onChange(of: reminderEnabled) { _, enabled in
            if !enabled {
                reminderDaysBeforeText = ""
                reminderDaysBeforeDisplayText = ""
            }
            emitCreditDataChange()
        }
        .onChange(of: reminderDaysBeforeDisplayText) { _, newValue in
            let digits = String(newValue.filter(\.isNumber))
            if newValue != digits {
                reminderDaysBeforeDisplayText = digits
            }
            reminderDaysBeforeText = digits
            emitCreditDataChange()
        }
        .onChange(of: reminderTime) { _, _ in emitCreditDataChange() }
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Баланс")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Сумма кредита")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: $amountDisplayText)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Остаток долга")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: $remainingAmountDisplayText)
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

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Платеж")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Платёж в месяц")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: $monthlyPaymentDisplayText)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)

                    FinancesRowDivider(leadingPadding: 16)

                    HStack(spacing: 12) {
                        Text("Режим даты платежа")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Menu {
                            ForEach(CreditPaymentMode.allCases, id: \.self) { mode in
                                Button(mode.displayName) {
                                    paymentMode = mode
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(paymentMode.displayName)
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)

                    FinancesRowDivider(leadingPadding: 16)

                    if paymentMode == .dayOfMonth {
                        HStack(spacing: 12) {
                            Text("День месяца")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Menu {
                                ForEach(1...31, id: \.self) { day in
                                    Button("\(day)") {
                                        paymentDayOfMonth = day
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\(paymentDayOfMonth)")
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    } else {
                        DatePicker(
                            "Следующая дата",
                            selection: $nextPaymentDate,
                            displayedComponents: .date
                        )
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Напоминание")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Toggle("Напоминать о платеже", isOn: $reminderEnabled)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    if reminderEnabled {
                        FinancesRowDivider(leadingPadding: 16)

                        HStack(spacing: 12) {
                            Text("За N дней")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: $reminderDaysBeforeDisplayText)
                                .keyboardType(.numberPad)
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)

                        FinancesRowDivider(leadingPadding: 16)

                        DatePicker(
                            "Время уведомления",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    private var calculationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text("Влияние на «Итого»")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("Уменьшает")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.error.opacity(0.9))
                    }
                    
                    Text("Определяет, как изменение баланса влияет на общий итог по всем продуктам.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Для учета в «Итого» используется поле «Остаток долга».")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.error.opacity(0.8))
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
        AmountInputFormatter.parse(text)
    }

    private func parseReminderDays(_ text: String) -> Int? {
        guard !text.isEmpty, let value = Int(text) else { return nil }
        return max(0, value)
    }

    private func emitCreditDataChange() {
        onCreditDataChanged(getCreditData())
    }

    private func handleAmountDisplayChange(_ newValue: String) {
        let sanitized = AmountInputFormatter.sanitize(newValue)
        let formatted = formatNumberForDisplay(sanitized)
        if newValue != formatted {
            amountDisplayText = formatted
        }
        amountText = sanitized
        emitCreditDataChange()
    }

    private func handleRemainingAmountDisplayChange(_ newValue: String) {
        let sanitized = AmountInputFormatter.sanitize(newValue)
        let formatted = formatNumberForDisplay(sanitized)
        if newValue != formatted {
            remainingAmountDisplayText = formatted
        }
        remainingAmountText = sanitized
        emitCreditDataChange()
    }

    private func handleMonthlyPaymentDisplayChange(_ newValue: String) {
        let sanitized = AmountInputFormatter.sanitize(newValue)
        let formatted = formatNumberForDisplay(sanitized)
        if newValue != formatted {
            monthlyPaymentDisplayText = formatted
        }
        monthlyPaymentText = sanitized
        emitCreditDataChange()
    }
    
    private func formatNumberForDisplay(_ text: String) -> String {
        AmountInputFormatter.display(text)
    }

    private static func defaultReminderTime() -> Date {
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}

struct InlineInvestmentCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: InvestmentViewModel
    @Binding var name: String
    @Binding var selectedCategory: InvestmentCategory
    let onInvestmentDataChanged: ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var selectedInvestmentType: InvestmentType = .positive
    @State private var amountText: String = ""
    @State private var amountDisplayText: String = ""
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
    @State private var marketQuantityDisplayText: String = ""
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
        selectedCategory: Binding<InvestmentCategory>,
        onInvestmentDataChanged: @escaping ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?) -> Void,
        marketDataClient: MarketDataClientProtocol = TwelveDataClient.shared,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self._name = name
        self._selectedCategory = selectedCategory
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
        return !name.isEmpty
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
        
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let amount = parseNumber(amountText) ?? 0
        
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
            groupSection
            calculationsSection
            prioritySection
        }
        .onAppear {
            loadAvailableCurrencies()
            if amountDisplayText.isEmpty {
                amountDisplayText = formatNumberForDisplay(amountText)
            }
            if marketQuantityDisplayText.isEmpty {
                marketQuantityDisplayText = formatNumberForDisplay(marketQuantityText)
            }
        }
        .onChange(of: name) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: amountText) { _, newValue in
            let formatted = formatNumberForDisplay(newValue)
            if amountDisplayText != formatted {
                amountDisplayText = formatted
            }
            onInvestmentDataChanged(getInvestmentData())
        }
        .onChange(of: amountDisplayText) { _, newValue in
            let sanitized = AmountInputFormatter.sanitize(newValue)
            let formatted = formatNumberForDisplay(sanitized)
            if newValue != formatted {
                amountDisplayText = formatted
            }
            amountText = sanitized
        }
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
        .onChange(of: marketQuantityDisplayText) { _, newValue in
            let sanitized = AmountInputFormatter.sanitize(newValue)
            let formatted = formatNumberForDisplay(sanitized)
            if newValue != formatted {
                marketQuantityDisplayText = formatted
            }
            marketQuantityText = sanitized
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMarketSearchSheet) {
            MarketSymbolSearchSheet(filter: marketFilter) { symbol in
                applySelectedMarketSymbol(symbol)
            }
            .presentationDetents([.large])
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
                        TextField("0", text: $marketQuantityDisplayText)
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
                        TextField("0", text: $amountDisplayText)
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

                    if selectedCategory == .debt {
                        Text("Для долгов: если вам должны — выбирайте «Увеличивает», если вы должны — «Уменьшает».")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        AmountInputFormatter.parse(text)
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
        AmountInputFormatter.display(text)
    }
}
