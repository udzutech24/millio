//
//  InlineCreateForms.swift
//  millio
//

import SwiftUI

// MARK: - Inline Create Forms

struct InlineCardCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: CardViewModel
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Binding var name: String
    let allowsTypeSwitching: Bool
    let selectedProductType: FinanceAccountType
    let selectedInvestmentCategory: InvestmentCategory
    let onProductTypeSelected: (FinanceAccountType) -> Void
    let onProductTitleSelected: (String) -> Void
    let onInvestmentPresetSelected: (FinanceAddAccountInvestmentPreset) -> Void
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
    @State private var didPrefillFromEditing: Bool = false
    @State private var showCryptoProAlert: Bool = false
    
    init(
        viewModel: CardViewModel,
        name: Binding<String>,
        allowsTypeSwitching: Bool = true,
        selectedProductType: FinanceAccountType,
        selectedInvestmentCategory: InvestmentCategory,
        onProductTypeSelected: @escaping (FinanceAccountType) -> Void,
        onProductTitleSelected: @escaping (String) -> Void,
        onInvestmentPresetSelected: @escaping (FinanceAddAccountInvestmentPreset) -> Void,
        onInvestmentCategorySelected: @escaping (InvestmentCategory) -> Void,
        onCardDataChanged: @escaping (Card) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self._name = name
        self.allowsTypeSwitching = allowsTypeSwitching
        self.selectedProductType = selectedProductType
        self.selectedInvestmentCategory = selectedInvestmentCategory
        self.onProductTypeSelected = onProductTypeSelected
        self.onProductTitleSelected = onProductTitleSelected
        self.onInvestmentPresetSelected = onInvestmentPresetSelected
        self.onInvestmentCategorySelected = onInvestmentCategorySelected
        self.onCardDataChanged = onCardDataChanged
        self.groupSection = groupSection()
        _card = State(initialValue: Card(
            name: name.wrappedValue,
            cardNumber: "",
            bank: .other,
            cardType: .debit,
            priority: .normal,
            currency: SettingsManager.shared.primaryCurrencyCode,
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
            populateCardFromEditingIfNeeded()
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
                let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
                let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
                CurrencyPickerView(
                    allCodes: availableCurrencies,
                    searchText: $currencySearchText,
                    selectedCodes: favoriteCodes,
                    favoriteCodes: Set(favoriteCodes),
                    currentSelection: card.currency,
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
                        card.currency = currency
                        showCurrencyPicker = false
                    }
                )
                .navigationTitle(String(localized: "finances.add_account.currency_picker.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "finances.common.cancel")) { showCurrencyPicker = false }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .premiumUpsellAlert(
            isPresented: $showCryptoProAlert,
            titleKey: "monetization.crypto.pro_title",
            message: String(localized: "monetization.crypto.pro_message"),
            onSubscribe: { router.push(.subscription) }
        )
    }
    
    private var accentColor: Color { AppColors.financesGradient.first ?? AppColors.brandPrimary }

    private func populateCardFromEditingIfNeeded() {
        guard !didPrefillFromEditing, let editingCard = viewModel.state.editingCard else {
            return
        }
        didPrefillFromEditing = true

        name = editingCard.name

        let draft = Card(
            name: editingCard.name,
            cardNumber: editingCard.cardNumber,
            bank: editingCard.bank,
            cardType: editingCard.cardType,
            priority: editingCard.priority,
            currency: editingCard.currency,
            balance: editingCard.balance,
            creditLimit: editingCard.creditLimit,
            expiryDate: editingCard.expiryDate,
            cardholderName: editingCard.cardholderName,
            cardColor: editingCard.cardColor,
            isFavorite: editingCard.isFavorite,
            includeInTotal: editingCard.includeInTotal
        )
        if !editingCard.uniqueID.isEmpty {
            draft.uniqueID = editingCard.uniqueID
        }
        card = draft

        if draft.cardType == .credit {
            let limit = draft.creditLimit ?? 0
            let debt = max(0, limit - draft.balance)
            creditLimitText = AmountInputFormatter.display(AmountInputFormatter.sanitize(String(limit)))
            creditDebtText = AmountInputFormatter.display(AmountInputFormatter.sanitize(String(debt)))
        } else {
            let sanitizedBalance = AmountInputFormatter.sanitize(String(draft.balance))
            balanceText = sanitizedBalance
            balanceDisplayText = AmountInputFormatter.display(sanitizedBalance)
        }

        onCardDataChanged(currentCard)
    }
    
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.type"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Menu {
                        Button {
                            onProductTitleSelected(FinanceAccountType.card.displayName)
                            onInvestmentPresetSelected(.asset)
                            onProductTypeSelected(.card)
                        } label: {
                            Label(FinanceAccountType.card.displayName, systemImage: FinanceAccountType.card.icon)
                        }
                        Button {
                            onProductTitleSelected(String(localized: "finances.add_account.product.account"))
                            onInvestmentPresetSelected(.account)
                            onInvestmentCategorySelected(.other)
                            onProductTypeSelected(.investment)
                        } label: {
                            Label(String(localized: "finances.add_account.product.account"), systemImage: "building.columns.fill")
                        }

                        Button {
                            onProductTitleSelected(FinanceAccountType.credit.displayName)
                            onInvestmentPresetSelected(.asset)
                            onProductTypeSelected(.credit)
                        } label: {
                            Label(FinanceAccountType.credit.displayName, systemImage: FinanceAccountType.credit.icon)
                        }
                        Button {
                            onProductTitleSelected(String(localized: "finances.account.type.investment"))
                            onInvestmentPresetSelected(.asset)
                            onInvestmentCategorySelected(.other)
                            onProductTypeSelected(.investment)
                        } label: {
                            Label(String(localized: "finances.account.type.investment"), systemImage: FinanceAccountType.investment.icon)
                        }

                        ForEach(visibleInvestmentCategories, id: \.self) { category in
                            Button {
                                onProductTitleSelected(category.displayName)
                                onInvestmentPresetSelected(.category)
                                onInvestmentCategorySelected(category)
                                onProductTypeSelected(.investment)
                            } label: {
                                Label(category.displayName, systemImage: category.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(localized: "finances.add_account.product.type"))
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
                                if allowsTypeSwitching {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .disabled(!allowsTypeSwitching)

                    FinancesRowDivider(leadingPadding: 16)

                    Menu {
                        Button {
                            card.cardTypeRaw = CardType.debit.rawValue
                        } label: {
                            Label(CardType.debit.displayName, systemImage: "creditcard")
                        }
                        Button {
                            card.cardTypeRaw = CardType.credit.rawValue
                        } label: {
                            Label(CardType.credit.displayName, systemImage: "banknote")
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(localized: "finances.add_account.card.type"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()

                            HStack(spacing: 6) {
                                Text(card.cardTypeRaw == CardType.debit.rawValue ? CardType.debit.displayName : CardType.credit.displayName)
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.balance"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    if card.cardType == .credit {
                        HStack(spacing: 12) {
                            Text(String(localized: "finances.add_account.card.credit_limit"))
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
                            Text(String(localized: "finances.add_account.card.total_debt"))
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
                            Text(String(localized: "finances.add_account.card.remaining_limit"))
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
                            Text(String(localized: "finances.add_account.field.amount"))
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
                        Text(String(localized: "finances.add_account.field.currency"))
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.calculations"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    if card.cardType == .credit {
                        HStack(spacing: 10) {
                            Text(String(localized: "finances.add_account.total_impact.title"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text(String(localized: "finances.add_account.total_impact.decreases"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.error.opacity(0.9))
                        }
                    } else {
                        Toggle(String(localized: "finances.add_account.total_impact.include"), isOn: $card.includeInTotal)
                            .tint(AppColors.toggleOnGreen)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    
                    Text(String(localized: "finances.add_account.total_impact.description"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)

                    if card.cardType == .credit {
                        Text(String(localized: "finances.add_account.total_impact.credit_note"))
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.priority"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(String(localized: "finances.add_account.favorite.single"), isOn: $card.isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    FinancesRowDivider(leadingPadding: 0)
                    
                    HStack(spacing: 12) {
                        FinancesRadioOption(title: String(localized: "finances.priority.low"), isSelected: card.priority == .low) { card.priority = .low }
                        FinancesRadioOption(title: String(localized: "finances.priority.normal"), isSelected: card.priority == .normal) { card.priority = .normal }
                        FinancesRadioOption(title: String(localized: "finances.priority.high"), isSelected: card.priority == .high) { card.priority = .high }
                    }
                    
                    Text(String(localized: "finances.add_account.priority.hint"))
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

            availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: [card.currency])
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
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Binding var name: String
    let onCreditDataChanged: ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, paymentMode: CreditPaymentMode, paymentDayOfMonth: Int?, nextPaymentDate: Date?, reminderEnabled: Bool, reminderDaysBefore: Int?, reminderTime: Date?, includeInTotal: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var amountText: String = ""
    @State private var amountDisplayText: String = ""
    @State private var remainingAmountText: String = ""
    @State private var remainingAmountDisplayText: String = ""
    @State private var monthlyPaymentText: String = ""
    @State private var monthlyPaymentDisplayText: String = ""
    @State private var selectedCurrency: String = SettingsManager.shared.primaryCurrencyCode
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
    @State private var didPrefillFromEditing: Bool = false
    @State private var showCryptoProAlert: Bool = false
    
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
            populateCreditFromEditingIfNeeded()
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
                        Button(String(localized: "finances.common.cancel")) { showCurrencyPicker = false }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .premiumUpsellAlert(
            isPresented: $showCryptoProAlert,
            titleKey: "monetization.crypto.pro_title",
            message: String(localized: "monetization.crypto.pro_message"),
            onSubscribe: { router.push(.subscription) }
        )
    }

    private func populateCreditFromEditingIfNeeded() {
        guard !didPrefillFromEditing, let editingCredit = viewModel.state.editingCredit else {
            return
        }
        didPrefillFromEditing = true

        name = editingCredit.name
        amountText = AmountInputFormatter.sanitize(String(editingCredit.amount))
        amountDisplayText = formatNumberForDisplay(amountText)
        remainingAmountText = AmountInputFormatter.sanitize(String(editingCredit.remainingAmount))
        remainingAmountDisplayText = formatNumberForDisplay(remainingAmountText)
        monthlyPaymentText = AmountInputFormatter.sanitize(String(editingCredit.monthlyPayment))
        monthlyPaymentDisplayText = formatNumberForDisplay(monthlyPaymentText)
        selectedCurrency = editingCredit.currency
        isFavorite = editingCredit.isFavorite
        paymentMode = editingCredit.paymentMode
        if let day = editingCredit.paymentDayOfMonth {
            paymentDayOfMonth = max(1, min(31, day))
        }
        if let date = editingCredit.nextPaymentDate {
            nextPaymentDate = date
        }
        reminderEnabled = editingCredit.reminderEnabled
        if let daysBefore = editingCredit.reminderDaysBefore {
            reminderDaysBeforeText = String(daysBefore)
            reminderDaysBeforeDisplayText = String(daysBefore)
        }
        if let time = editingCredit.reminderTime {
            reminderTime = time
        }

        emitCreditDataChange()
    }
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.balance"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(String(localized: "finances.add_account.credit.amount"))
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
                        Text(String(localized: "finances.add_account.credit.remaining_debt"))
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
                        Text(String(localized: "finances.add_account.field.currency"))
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.credit.payment.section"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(String(localized: "finances.add_account.credit.monthly_payment"))
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
                        Text(String(localized: "finances.add_account.credit.payment_mode"))
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
                            Text(String(localized: "finances.add_account.credit.payment_day"))
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
                            String(localized: "finances.add_account.credit.next_payment_date"),
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.credit.reminder.section"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Toggle(String(localized: "finances.add_account.credit.reminder.toggle"), isOn: $reminderEnabled)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    if reminderEnabled {
                        FinancesRowDivider(leadingPadding: 16)

                        HStack(spacing: 12) {
                            Text(String(localized: "finances.add_account.credit.reminder.days_before"))
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
                            String(localized: "finances.add_account.credit.reminder.time"),
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.calculations"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text(String(localized: "finances.add_account.total_impact.title"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(String(localized: "finances.add_account.total_impact.decreases"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.error.opacity(0.9))
                    }
                    
                    Text(String(localized: "finances.add_account.total_impact.description"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(String(localized: "finances.add_account.total_impact.credit_remaining_note"))
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

            availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: [selectedCurrency])
        }
    }
    
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.priority"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)) {
                Toggle(String(localized: "finances.add_account.favorite"), isOn: $isFavorite)
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
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Binding var name: String
    @Binding var selectedCategory: InvestmentCategory
    let onInvestmentDataChanged: ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var selectedInvestmentType: InvestmentType = .positive
    @State private var amountText: String = ""
    @State private var amountDisplayText: String = ""
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
    @State private var marketQuantityDisplayText: String = ""
    @State private var purchaseUnitPriceText: String = ""
    @State private var lastKnownUnitPrice: Double?
    @State private var lastKnownPriceUpdatedAt: Date?
    @State private var marketProviderRaw: String?
    @State private var showMarketSearchSheet: Bool = false
    @State private var isRefreshingPrice: Bool = false
    @State private var marketErrorMessage: String?
    @State private var didPrefillFromEditing: Bool = false
    @State private var showCryptoProAlert: Bool = false
    
    private let marketDataClient: MarketDataClientProtocol
    
    init(
        viewModel: InvestmentViewModel,
        name: Binding<String>,
        selectedCategory: Binding<InvestmentCategory>,
        onInvestmentDataChanged: @escaping ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?) -> Void,
        marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared,
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
        guard let quantity = parseMarketQuantity(marketQuantityText),
              let unitPrice = lastKnownUnitPrice else {
            return nil
        }
        return quantity * unitPrice
    }
    
    var isValid: Bool {
        if isMarketCategory {
            guard !name.isEmpty,
                  !marketSymbol.isEmpty,
                  let quantity = parseMarketQuantity(marketQuantityText) else {
                return false
            }
            return quantity >= 0
        }
        return !name.isEmpty
    }
    
    func getInvestmentData() -> (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)? {
        if isMarketCategory {
            guard let quantity = parseMarketQuantity(marketQuantityText),
                  quantity >= 0 else {
                return nil
            }
            
            let effectiveAmount = positionTotal ?? parseNumber(amountText) ?? 0.0
            let effectiveCurrency = (marketCurrency?.isEmpty == false) ? marketCurrency! : selectedCurrency
            let marketData = InvestmentMarketData(
                symbol: marketSymbol.isEmpty ? nil : marketSymbol,
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
            prefillFromEditingIfNeeded()
            loadAvailableCurrencies()
            if amountDisplayText.isEmpty {
                amountDisplayText = formatNumberForDisplay(amountText)
            }
            if marketQuantityDisplayText.isEmpty {
                marketQuantityDisplayText = formatMarketQuantityForDisplay(marketQuantityText)
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
        .onChange(of: selectedCategory) { oldValue, newValue in
            if !(newValue == .stocks || newValue == .crypto) {
                clearMarketState()
            }
            if MarketSearchFlowPolicy.shouldAutoOpenSearch(
                previousCategory: oldValue,
                newCategory: newValue,
                marketSymbol: marketSymbol,
                isEditingLockedIdentity: false
            ) {
                DispatchQueue.main.async {
                    showMarketSearchSheet = true
                }
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
            let sanitized = AmountInputFormatter.sanitize(
                newValue,
                maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits
            )
            let formatted = formatMarketQuantityForDisplay(sanitized)
            if newValue != formatted {
                marketQuantityDisplayText = formatted
            }
            marketQuantityText = sanitized
        }
        .onChange(of: purchaseUnitPriceText) { _, _ in
            onInvestmentDataChanged(getInvestmentData())
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
                        Button(String(localized: "finances.common.cancel")) { showCurrencyPicker = false }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .premiumUpsellAlert(
            isPresented: $showCryptoProAlert,
            titleKey: "monetization.crypto.pro_title",
            message: String(localized: "monetization.crypto.pro_message"),
            onSubscribe: { router.push(.subscription) }
        )
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

    private var needsMarketSymbolSelection: Bool {
        isMarketCategory && marketSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var marketSymbolHintText: String {
        selectedCategory == .crypto
            ? String(localized: "finances.add_account.hint.select_coin_or_pair")
            : String(localized: "finances.add_account.hint.select_ticker")
    }
    
    private var marketInstrumentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.market.section_symbol"))
            FinancesGlassCard(
                accentColor: needsMarketSymbolSelection
                    ? Color(red: 0.18, green: 0.95, blue: 0.45)
                    : nil
            ) {
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
                            .foregroundStyle(
                                needsMarketSymbolSelection
                                    ? AnyShapeStyle(Color(red: 0.18, green: 0.95, blue: 0.45))
                                    : AnyShapeStyle(
                                        LinearGradient(
                                            colors: AppColors.financesGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }

                        if needsMarketSymbolSelection {
                            Text(marketSymbolHintText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(red: 0.18, green: 0.95, blue: 0.45))
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
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
                        Text(String(localized: "finances.add_account.investment.purchase_price"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(purchaseUnitPriceText) },
                            set: { newValue in
                                purchaseUnitPriceText = AmountInputFormatter.sanitize(newValue)
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.balance"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(String(localized: "finances.add_account.field.amount"))
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
                        Text(String(localized: "finances.add_account.field.currency"))
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.calculations"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(String(localized: "finances.add_account.total_impact.include"), isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    HStack(spacing: 12) {
                        FinancesCheckboxOption(
                            title: String(localized: "finances.add_account.total_impact.increases"),
                            isSelected: selectedInvestmentType == .positive,
                            onTap: { selectedInvestmentType = .positive }
                        )
                        FinancesCheckboxOption(
                            title: String(localized: "finances.add_account.total_impact.decreases"),
                            isSelected: selectedInvestmentType == .negative,
                            onTap: { selectedInvestmentType = .negative }
                        )
                    }
                    
                    Text(String(localized: "finances.add_account.total_impact.description"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)

                    if selectedCategory == .debt {
                        Text(String(localized: "finances.add_account.total_impact.debt_note"))
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.priority"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(String(localized: "finances.add_account.favorite"), isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    FinancesRowDivider(leadingPadding: 0)
                    
                    HStack(spacing: 12) {
                        FinancesRadioOption(title: String(localized: "finances.priority.low"), isSelected: selectedPriority == .low) { selectedPriority = .low }
                        FinancesRadioOption(title: String(localized: "finances.priority.normal"), isSelected: selectedPriority == .normal) { selectedPriority = .normal }
                        FinancesRadioOption(title: String(localized: "finances.priority.high"), isSelected: selectedPriority == .high) { selectedPriority = .high }
                    }
                    
                    Text(String(localized: "finances.add_account.priority.hint"))
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

            availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: [selectedCurrency])
        }
    }

    private func prefillFromEditingIfNeeded() {
        guard !didPrefillFromEditing, let editing = viewModel.state.editingInvestment else {
            return
        }

        selectedInvestmentType = editing.investmentType
        selectedCategory = editing.category
        amountText = String(editing.amount)
        amountDisplayText = formatNumberForDisplay(amountText)
        selectedCurrency = editing.currency
        includeInTotal = editing.includeInTotal
        selectedPriority = editing.priority
        isFavorite = editing.isFavorite
        marketSymbol = editing.marketSymbol ?? ""
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
        marketQuantityDisplayText = formatMarketQuantityForDisplay(marketQuantityText)
        purchaseUnitPriceText = editing.averagePurchaseUnitPrice.map { "\($0)" } ?? ""
        lastKnownUnitPrice = editing.lastKnownUnitPrice
        lastKnownPriceUpdatedAt = editing.lastKnownPriceUpdatedAt
        marketProviderRaw = editing.marketProviderRaw
        didPrefillFromEditing = true
        onInvestmentDataChanged(getInvestmentData())
    }
    
    private func parseNumber(_ text: String) -> Double? {
        AmountInputFormatter.parse(text)
    }

    private func parseMarketQuantity(_ text: String) -> Double? {
        AmountInputFormatter.parse(text, maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits)
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
                        marketQuoteLookupKey = latestQuote.canonicalQuoteLookupKey
                        marketMICCode = latestQuote.micCode ?? marketMICCode
                        marketProviderRaw = latestQuote.providerSymbol == nil ? marketProviderRaw : "market-backend"
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
                    onInvestmentDataChanged(getInvestmentData())
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
        marketExchange = symbol.exchange
        marketQuoteLookupKey = symbol.canonicalQuoteLookupKey
        marketMICCode = symbol.micCode
        marketCurrency = symbol.currency
        selectedCurrency = symbol.currency ?? selectedCurrency
        marketProviderRaw = "market-backend"
        
        // В MVP используем тикер как название актива для единообразия.
        name = symbol.symbol
        
        refreshLatestPrice(forceRefresh: true)
        onInvestmentDataChanged(getInvestmentData())
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

    private func formatMarketQuantityForDisplay(_ text: String) -> String {
        AmountInputFormatter.display(text, maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits)
    }
}
