//
//  CardEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 27.01.2026.
//

import SwiftUI

// MARK: - Card Editor View

struct CardEditorView: View {
    @ObservedObject var viewModel: CardViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @State private var card: Card
    @State private var isNewCard: Bool
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    @Environment(\.dismiss) private var dismiss

    @State private var balanceText: String = ""
    @State private var creditLimitText: String = ""
    @State private var creditDebtText: String = ""
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    @State private var showCryptoProAlert: Bool = false

    init(viewModel: CardViewModel, onClose: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
        if let editing = viewModel.state.editingCard {
            let newCard = Card(
                name: editing.name,
                cardNumber: editing.cardNumber,
                bank: editing.bank,
                cardType: editing.cardType,
                priority: editing.priority,
                currency: editing.currency,
                balance: editing.balance,
                creditLimit: editing.creditLimit,
                expiryDate: editing.expiryDate,
                cardholderName: editing.cardholderName,
                cardColor: editing.cardColor,
                isFavorite: editing.isFavorite,
                includeInTotal: editing.includeInTotal
            )
            newCard.uniqueID = editing.uniqueID
            _card = State(initialValue: newCard)
            _balanceText = State(initialValue: AmountInputFormatter.display(AmountInputFormatter.plainString(from: editing.balance)))
            _creditLimitText = State(initialValue: editing.creditLimit.map {
                AmountInputFormatter.display(AmountInputFormatter.plainString(from: $0))
            } ?? "")
            let editingDebt = max(0, (editing.creditLimit ?? 0) - editing.balance)
            _creditDebtText = State(initialValue: editing.cardType == .credit
                ? AmountInputFormatter.display(AmountInputFormatter.plainString(from: editingDebt))
                : ""
            )
            _isNewCard = State(initialValue: false)
        } else {
            _card = State(initialValue: Card(
                name: "",
                cardNumber: "",
                bank: .other,
                cardType: .debit,
                priority: .normal,
                currency: SettingsManager.shared.primaryCurrencyCode,
                balance: 0.0
            ))
            _balanceText = State(initialValue: "")
            _creditLimitText = State(initialValue: "")
            _creditDebtText = State(initialValue: "")
            _isNewCard = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        mainInfoSection
                        financeSection
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
                isNewCard
                    ? String(localized: "finances.editor.card.new_title")
                    : String(localized: "finances.editor.card.edit_title")
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
                        viewModel.handle(.updateCard(card))
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cardIndexGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(card.name.isEmpty)
                }

                if onDelete != nil, !isNewCard {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized: "finances.common.delete"), role: .destructive) {
                            onDelete?()
                        }
                    }
                }
            }
            .onAppear {
                loadAvailableCurrencies()
                if card.cardType == .credit {
                    card.includeInTotal = true
                    if creditDebtText.isEmpty {
                        let debt = max(0, (AmountInputFormatter.parse(creditLimitText) ?? 0) - card.balance)
                        creditDebtText = AmountInputFormatter.display(
                            AmountInputFormatter.plainString(from: debt)
                        )
                    }
                }
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
                    TextField(String(localized: "finances.editor.card.name_placeholder"), text: $card.name)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    FinancesRowDivider()

                    TextField(String(localized: "finances.editor.card.number_placeholder"), text: Binding(
                        get: { card.cardNumber },
                        set: { newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count <= 4 {
                                card.cardNumber = filtered
                            }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    HStack {
                        Text(String(localized: "finances.add_account.card.type"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(String(localized: "finances.add_account.card.type"), selection: $card.cardTypeRaw) {
                            ForEach(CardType.allCases, id: \.rawValue) { type in
                                Text(type.displayName).tag(type.rawValue)
                            }
                        }
                        .tint(AppColors.textTertiary)
                        .onChange(of: card.cardTypeRaw) { _, newValue in
                            if newValue == CardType.debit.rawValue {
                                card.creditLimit = nil
                                creditLimitText = ""
                                creditDebtText = ""
                            } else {
                                card.includeInTotal = true
                                let limit = AmountInputFormatter.parse(creditLimitText) ?? card.creditLimit ?? 0
                                if creditLimitText.isEmpty {
                                    creditLimitText = AmountInputFormatter.display(
                                        AmountInputFormatter.plainString(from: limit)
                                    )
                                }
                                let debt = max(0, limit - card.balance)
                                creditDebtText = AmountInputFormatter.display(
                                    AmountInputFormatter.plainString(from: debt)
                                )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var financeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.editor.section.finances"))
            FinancesGlassCard {
                VStack(spacing: 0) {
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
                                    Text(card.currency)
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

                    FinancesRowDivider()

                    if card.cardType == .credit {
                        HStack {
                            Text(String(localized: "finances.add_account.card.credit_limit"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { creditLimitText },
                                set: { newValue in
                                    creditLimitText = AmountInputFormatter.display(newValue)
                                    let limit = AmountInputFormatter.parse(creditLimitText) ?? 0
                                    let debt = AmountInputFormatter.parse(creditDebtText) ?? 0
                                    card.creditLimit = creditLimitText.isEmpty ? nil : limit
                                    card.balance = max(0, limit - debt)
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
                            Text(String(localized: "finances.add_account.card.total_debt"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { creditDebtText },
                                set: { newValue in
                                    creditDebtText = AmountInputFormatter.display(newValue)
                                    let limit = AmountInputFormatter.parse(creditLimitText) ?? 0
                                    let debt = AmountInputFormatter.parse(creditDebtText) ?? 0
                                    card.balance = max(0, limit - debt)
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
                            Text(String(localized: "finances.add_account.card.remaining_limit"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text(AmountInputFormatter.display(String(creditRemainingLimit)))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: 150, alignment: .trailing)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    } else {
                        HStack {
                            Text(String(localized: "finances.add_account.field.amount"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { balanceText },
                                set: { newValue in
                                    balanceText = AmountInputFormatter.display(newValue)
                                    card.balance = AmountInputFormatter.parse(balanceText) ?? 0
                                }
                            ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: 150)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                }
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
                        Picker(String(localized: "finances.add_account.section.priority"), selection: Binding(
                            get: { card.priority },
                            set: { card.priority = $0 }
                        )) {
                            ForEach(CardPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    Toggle(String(localized: "finances.add_account.favorite.single"), isOn: $card.isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    FinancesRowDivider()

                    if card.cardType == .credit {
                        HStack {
                            Text(String(localized: "finances.add_account.total_impact.title"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text(String(localized: "finances.add_account.total_impact.decreases"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.error.opacity(0.9))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    } else {
                        Toggle(String(localized: "finances.add_account.total_impact.include"), isOn: $card.includeInTotal)
                            .tint(AppColors.toggleOnGreen)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - Currency Loading

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
