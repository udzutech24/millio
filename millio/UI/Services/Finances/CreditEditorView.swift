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

                ScrollView {
                    VStack(spacing: 24) {
                        mainInfoSection
                        creditParamsSection
                        additionalSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
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
                            onDelete?()
                        }
                    }
                }
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
    
    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Основная информация")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    TextField("Название кредита", text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var creditParamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Параметры кредита")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Сумма кредита")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let sanitized = AmountInputFormatter.sanitize(newValue)
                                amountText = AmountInputFormatter.display(sanitized)
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
                        Text("Остаток долга")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(remainingAmountText) },
                            set: { newValue in
                                let sanitized = AmountInputFormatter.sanitize(newValue)
                                remainingAmountText = AmountInputFormatter.display(sanitized)
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
    
    private var additionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Дополнительно")
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
                    
                    FinancesRowDivider()
                    
                    HStack {
                        Text("Банк")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Банк", selection: $selectedBank) {
                            ForEach(Bank.allCases, id: \.self) { bank in
                                Text(bank.displayName).tag(bank)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    HStack {
                        Text("Тип кредита")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Тип кредита", selection: $selectedCreditType) {
                            ForEach(CreditType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
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
        !name.isEmpty &&
        parseNumber(amountText) != nil && parseNumber(amountText)! > 0 &&
        parseNumber(remainingAmountText) != nil && parseNumber(remainingAmountText)! >= 0
    }

    // MARK: - Currency Loading

    private func loadAvailableCurrencies() {
        Task {
            let currentSelectedCurrency = await MainActor.run {
                isLoadingCurrencies = true
                return selectedCurrency
            }

            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")

            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(currentSelectedCurrency) {
                currencies.append(currentSelectedCurrency)
            }
            let sortedCurrencies = currencies.sorted()

            await MainActor.run {
                availableCurrencies = sortedCurrencies
                isLoadingCurrencies = false
            }
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
        AmountInputFormatter.parse(text)
    }

    private func parseDecimal(_ text: String) -> Double? {
        let normalized = normalizeDecimal(text)
        return Double(normalized)
    }

    private func formatNumberForDisplay(_ text: String) -> String {
        AmountInputFormatter.display(text)
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
            includeInTotal: includeInTotal,
            uniqueID: nil
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
