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

    @Environment(\.dismiss) private var dismiss

    @State private var balanceText: String = ""
    @State private var creditLimitText: String = ""
    @State private var creditDebtText: String = ""
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false

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
            _balanceText = State(initialValue: AmountInputFormatter.plainString(from: editing.balance))
            _creditLimitText = State(initialValue: editing.creditLimit.map { AmountInputFormatter.plainString(from: $0) } ?? "")
            let editingDebt = max(0, (editing.creditLimit ?? 0) - editing.balance)
            _creditDebtText = State(initialValue: editing.cardType == .credit ? AmountInputFormatter.plainString(from: editingDebt) : "")
            _isNewCard = State(initialValue: false)
        } else {
            _card = State(initialValue: Card(
                name: "",
                cardNumber: "",
                bank: .other,
                cardType: .debit,
                priority: .normal,
                currency: "RUB",
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
            .navigationTitle(isNewCard ? "Новая карта" : "Редактирование")
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
                        Button("Удалить", role: .destructive) {
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
                        creditDebtText = AmountInputFormatter.plainString(from: debt)
                    }
                }
            }
        }
    }
    
    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Основная информация")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    TextField("Название карты", text: $card.name)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    FinancesRowDivider()

                    TextField("Номер карты (последние 4 цифры)", text: Binding(
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
                        Text("Банк")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Банк", selection: $card.bankRaw) {
                            ForEach(Bank.allCases, id: \.rawValue) { bank in
                                Text(bank.displayName).tag(bank.rawValue)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    HStack {
                        Text("Тип карты")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Тип карты", selection: $card.cardTypeRaw) {
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
                                    creditLimitText = AmountInputFormatter.plainString(from: limit)
                                }
                                let debt = max(0, limit - card.balance)
                                creditDebtText = AmountInputFormatter.plainString(from: debt)
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
            FinancesSectionHeader(title: "Финансы")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Валюта")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isLoadingCurrencies {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppColors.textTertiary)
                        } else {
                            Picker("Валюта", selection: $card.currency) {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Text(currency).tag(currency)
                                }
                            }
                            .tint(AppColors.textTertiary)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    if card.cardType == .credit {
                        HStack {
                            Text("Кредитный лимит")
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
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: 150)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        FinancesRowDivider()

                        HStack {
                            Text("Общий долг")
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
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: 150)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        FinancesRowDivider()

                        HStack {
                            Text("Остаток лимита")
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
                            Text("Баланс")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { AmountInputFormatter.display(balanceText) },
                                set: { newValue in
                                    let sanitized = AmountInputFormatter.sanitize(newValue)
                                    balanceText = sanitized
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
            FinancesSectionHeader(title: "Дополнительно")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Приоритет")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Приоритет", selection: Binding(
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

                    Toggle("Избранная", isOn: $card.isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    FinancesRowDivider()

                    if card.cardType == .credit {
                        HStack {
                            Text("Влияние на «Итого»")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text("Уменьшает")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.error.opacity(0.9))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    } else {
                        Toggle("Учитывать в общих", isOn: $card.includeInTotal)
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

            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")

            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(card.currency) {
                currencies.append(card.currency)
            }
            availableCurrencies = currencies.sorted()
        }
    }

    private var creditRemainingLimit: Double {
        let limit = AmountInputFormatter.parse(creditLimitText) ?? 0
        let debt = AmountInputFormatter.parse(creditDebtText) ?? 0
        return max(0, limit - debt)
    }
}
