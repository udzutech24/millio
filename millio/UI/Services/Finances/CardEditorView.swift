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

                Form {
                    Section {
                        TextField("Название карты", text: $card.name)
                            .foregroundStyle(AppColors.textPrimary)

                        TextField("Номер карты (последние 4 цифры, необязательно)", text: Binding(
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

                        Picker("Банк", selection: $card.bankRaw) {
                            ForEach(Bank.allCases, id: \.rawValue) { bank in
                                Text(bank.displayName).tag(bank.rawValue)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)

                        Picker("Тип карты", selection: $card.cardTypeRaw) {
                            ForEach(CardType.allCases, id: \.rawValue) { type in
                                Text(type.displayName).tag(type.rawValue)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .onChange(of: card.cardTypeRaw) { _, newValue in
                            if newValue == CardType.debit.rawValue {
                                card.creditLimit = nil
                                creditLimitText = ""
                            }
                        }
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Section {
                        if isLoadingCurrencies {
                            HStack {
                                Text("Валюта")
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(AppColors.textTertiary)
                            }
                        } else {
                            Picker("Валюта", selection: $card.currency) {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Text(currency).tag(currency)
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }

                        TextField("Баланс", value: $card.balance, format: .number)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)

                        if card.cardType == .credit {
                            TextField("Кредитный лимит", text: $creditLimitText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                                .onChange(of: creditLimitText) { _, newValue in
                                    if let limit = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                                        card.creditLimit = limit
                                    } else if newValue.isEmpty {
                                        card.creditLimit = nil
                                    }
                                }
                        }
                    } header: {
                        Text("Финансы")
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Section {
                        Picker("Приоритет", selection: Binding(
                            get: { card.priority },
                            set: { card.priority = $0 }
                        )) {
                            ForEach(CardPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)

                        Toggle("Избранная", isOn: $card.isFavorite)
                            .foregroundStyle(AppColors.textPrimary)

                        Toggle("Учитывать в общих финансах", isOn: $card.includeInTotal)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Дополнительно")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
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
