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

    @State private var creditLimitText: String = ""
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
            _creditLimitText = State(initialValue: editing.creditLimit.map { String(format: "%.2f", $0) } ?? "")
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
            _creditLimitText = State(initialValue: "")
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

                    HStack {
                        Text("Баланс")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", value: $card.balance, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: 150)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    if card.cardType == .credit {
                        FinancesRowDivider()
                        
                        HStack {
                            Text("Кредитный лимит")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: $creditLimitText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: 150)
                                .onChange(of: creditLimitText) { _, newValue in
                                    if let limit = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                                        card.creditLimit = limit
                                    } else if newValue.isEmpty {
                                        card.creditLimit = nil
                                    }
                                }
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

                    Toggle("Учитывать в общих", isOn: $card.includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
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
}
