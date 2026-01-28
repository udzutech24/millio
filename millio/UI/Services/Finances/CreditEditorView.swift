//
//  CreditEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 27.01.2026.
//

import SwiftUI

// MARK: - Credit Editor View

struct CreditEditorView: View {
    @ObservedObject var viewModel: CreditViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

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

    init(viewModel: CreditViewModel, onClose: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                Form {
                    Section {
                        TextField("Название кредита", text: $name)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Section {
                        TextField("Сумма кредита", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)

                        TextField("Остаток долга", text: Binding(
                            get: { formatNumberForDisplay(remainingAmountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                remainingAmountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Параметры кредита")
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
                            Picker("Валюта", selection: $selectedCurrency) {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Text(currency).tag(currency)
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }

                        Picker("Банк", selection: $selectedBank) {
                            ForEach(Bank.allCases, id: \.self) { bank in
                                Text(bank.displayName).tag(bank)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)

                        Picker("Тип кредита", selection: $selectedCreditType) {
                            ForEach(CreditType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)

                        Toggle("В избранном", isOn: $isFavorite)
                            .foregroundStyle(AppColors.textPrimary)

                        Toggle("Учитывать в общих финансах", isOn: $includeInTotal)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Дополнительно")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(viewModel.state.editingCredit == nil ? "Новый кредит" : "Редактировать")
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
                        saveCredit()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.creditsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }

                if onDelete != nil, viewModel.state.editingCredit != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Удалить", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog("Удалить счет полностью?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    onDelete?()
                }
                Button("Отмена", role: .cancel) {}
            }
            .onAppear {
                if let editing = viewModel.state.editingCredit {
                    name = editing.name
                    amountText = String(format: "%.2f", editing.amount)
                    remainingAmountText = String(format: "%.2f", editing.remainingAmount)
                    selectedCurrency = editing.currency
                    selectedBank = editing.bank
                    selectedCreditType = editing.creditType
                    isFavorite = editing.isFavorite
                    includeInTotal = editing.includeInTotal
                }

                loadAvailableCurrencies()
            }
        }
    }

    private var isValid: Bool {
        !name.isEmpty &&
        parseNumber(amountText) != nil && parseNumber(amountText)! > 0 &&
        parseNumber(remainingAmountText) != nil && parseNumber(remainingAmountText)! >= 0
    }

    // MARK: - Currency Loading

    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }

            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")

            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) {
                currencies.append(selectedCurrency)
            }
            availableCurrencies = currencies.sorted()
        }
    }

    // MARK: - Number Formatting Helpers

    private func normalizeNumber(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
    }

    private func normalizeDecimal(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: ".")
    }

    private func parseNumber(_ text: String) -> Double? {
        let normalized = normalizeNumber(text)
        return Double(normalized)
    }

    private func parseDecimal(_ text: String) -> Double? {
        let normalized = normalizeDecimal(text)
        return Double(normalized)
    }

    private func formatNumberForDisplay(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        guard let number = parseNumber(text) else {
            return text
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        let normalized = normalizeNumber(text)
        let hasDecimal = normalized.contains(".")
        if !hasDecimal {
            formatter.maximumFractionDigits = 0
        }

        return formatter.string(from: NSNumber(value: number)) ?? text
    }

    private func saveCredit() {
        guard let amount = parseNumber(amountText),
              let remainingAmount = parseNumber(remainingAmountText) else {
            return
        }
        let endDate = resolvedEndDate()
        let monthlyPayment = resolvedMonthlyPayment(for: amount)

        viewModel.handle(.updateCredit(
            name: name,
            amount: amount,
            monthlyPayment: monthlyPayment,
            endDate: endDate,
            remainingAmount: remainingAmount,
            currency: selectedCurrency,
            bank: selectedBank,
            creditType: selectedCreditType,
            isFavorite: isFavorite,
            includeInTotal: includeInTotal
        ))

        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func resolvedEndDate() -> Date {
        if let editing = viewModel.state.editingCredit, let endDate = editing.endDate {
            return endDate
        }
        return Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }

    private func resolvedMonthlyPayment(for amount: Double) -> Double {
        if let editing = viewModel.state.editingCredit {
            return editing.monthlyPayment
        }
        return amount / 12.0
    }
}
