//
//  InvestmentEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 27.01.2026.
//

import SwiftUI

// MARK: - Investment Editor View

struct InvestmentEditorView: View {
    @ObservedObject var viewModel: InvestmentViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

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

    init(viewModel: InvestmentViewModel, onClose: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
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
                        investmentParamsSection
                        additionalSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle(viewModel.state.editingInvestment == nil ? "Новый актив" : "Редактировать")
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
                        saveInvestment()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.investmentsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }

                if onDelete != nil, viewModel.state.editingInvestment != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Удалить", role: .destructive) {
                            onDelete?()
                        }
                    }
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingInvestment {
                    name = editing.name
                    selectedInvestmentType = editing.investmentType
                    selectedCategory = editing.category
                    amountText = String(format: "%.2f", editing.amount)
                    selectedCurrency = editing.currency
                    includeInTotal = editing.includeInTotal
                    selectedPriority = editing.priority
                    isFavorite = editing.isFavorite
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
                    TextField("Название актива", text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var investmentParamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Параметры актива")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Тип актива")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Тип актива", selection: $selectedInvestmentType) {
                            ForEach(InvestmentType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    HStack {
                        Text("Категория")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Категория", selection: $selectedCategory) {
                            ForEach(InvestmentCategory.allCases, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    HStack {
                        Text("Сумма")
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
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: 150)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
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
                        Picker("Приоритет", selection: $selectedPriority) {
                            ForEach(InvestmentPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
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
        parseNumber(amountText) != nil && parseNumber(amountText)! > 0
    }

    private func loadAvailableCurrencies() {
        Task {
            // Устанавливаем состояние загрузки на главном акторе
            await MainActor.run {
                isLoadingCurrencies = true
            }
            
            // Выполняем сетевой вызов вне главного потока
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            
            // Получаем валюты из источника (синхронный метод)
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            
            // Добавляем выбранную валюту, если её нет
            if !currencies.contains(selectedCurrency) {
                currencies.append(selectedCurrency)
            }
            
            // Обновляем состояние на главном акторе
            await MainActor.run {
                availableCurrencies = currencies.sorted()
                isLoadingCurrencies = false
            }
        }
    }

    private func normalizeNumber(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
    }

    private func parseNumber(_ text: String) -> Double? {
        let normalized = normalizeNumber(text)
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

    private func saveInvestment() {
        guard let amount = parseNumber(amountText) else {
            return
        }

        viewModel.handle(.updateInvestment(
            name: name,
            investmentType: selectedInvestmentType,
            category: selectedCategory,
            amount: amount,
            currency: selectedCurrency,
            includeInTotal: includeInTotal,
            priority: selectedPriority,
            isFavorite: isFavorite,
            uniqueID: nil
        ))

        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
