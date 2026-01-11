//
//  InvestmentsView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

struct InvestmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: InvestmentViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                InvestmentsContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = InvestmentViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Internal Content View

private struct InvestmentsContentViewInternal: View {
    @ObservedObject var viewModel: InvestmentViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Статистика
                    statsSection
                    
                    // Список инвестиций
                    investmentsListSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Инвестиции")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.handle(.addInvestment)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showInvestmentEditor },
            set: { if !$0 { viewModel.handle(.hideInvestmentEditor) } }
        )) {
            InvestmentEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showDisplayCurrencySheet },
            set: { if !$0 { viewModel.handle(.hideDisplayCurrencySheet) } }
        )) {
            DisplayCurrencySheet(viewModel: viewModel)
        }
        .task {
            // Загружаем курсы при появлении экрана
            await viewModel.refreshRates()
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            // Общий баланс
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Всего инвестиций")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("\(viewModel.state.investments.count)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Баланс")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Button {
                            viewModel.handle(.showDisplayCurrencySheet)
                        } label: {
                            HStack(spacing: 4) {
                                Text(viewModel.state.displayCurrency)
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.investmentsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.balance))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.investmentsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    
                    if viewModel.state.isLoadingRates {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(AppColors.textTertiary)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.investmentsGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
            
            // Детализация
            HStack(spacing: 12) {
                // Плюсовые
                VStack(alignment: .leading, spacing: 4) {
                    Text("Плюсовые")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalPositive))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.investmentsGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                }
                
                // Минусовые
                VStack(alignment: .leading, spacing: 4) {
                    Text("Минусовые")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalNegative))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppColors.error)
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.investmentsGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                }
            }
        }
    }
    
    // MARK: - Investments List
    
    private var investmentsListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Инвестиции")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !viewModel.state.filteredInvestments.isEmpty {
                    Text("\(viewModel.state.filteredInvestments.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            if viewModel.state.filteredInvestments.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text(viewModel.state.investments.isEmpty ? "Нет инвестиций" : "Ничего не найдено")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    if viewModel.state.investments.isEmpty {
                        Text("Добавьте первую инвестицию")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.state.filteredInvestments) { investment in
                        InvestmentRow(investment: investment) {
                            viewModel.handle(.editInvestment(investment))
                        } onDelete: {
                            viewModel.handle(.deleteInvestment(investment))
                        } onToggleFavorite: {
                            viewModel.handle(.toggleFavorite(investment))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }
}

// MARK: - Investment Row

private struct InvestmentRow: View {
    let investment: Investment
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Основная область (кликабельна)
                Button(action: onEdit) {
                    HStack(spacing: 12) {
                        // Иконка категории
                        Image(systemName: investment.category.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.investmentsGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                        
                        // Информация об инвестиции
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(investment.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                if investment.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.investmentsGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            
                            HStack(spacing: 4) {
                                Text(investment.category.displayName)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(1)
                                
                                Text("•")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.textTertiary)
                                
                                Text(investment.investmentType.displayName)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AppColors.textTertiary)
                                    .lineLimit(1)
                                
                                if !investment.includeInTotal {
                                    Text("• Не учитывается")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                        }
                        
                        Spacer(minLength: 8)
                        
                        // Финансовая информация
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(formatBalance(investment.amount)) \(investment.currency)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(
                                    investment.investmentType == .positive ? AppColors.textPrimary : AppColors.error
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // Кнопки действий
                VStack(spacing: 8) {
                    // Кнопка избранного
                    Button {
                        onToggleFavorite()
                    } label: {
                        Image(systemName: investment.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                investment.isFavorite ?
                                LinearGradient(
                                    colors: AppColors.investmentsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: [AppColors.textTertiary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    
                    // Кнопка удаления
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.error)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Удалить инвестицию?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                        Button("Удалить", role: .destructive) {
                            onDelete()
                        }
                        Button("Отмена", role: .cancel) {}
                    } message: {
                        Text("Инвестиция \"\(investment.name)\" будет удалена без возможности восстановления.")
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: AppColors.investmentsGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                }
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }
}

// MARK: - Investment Editor View

private struct InvestmentEditorView: View {
    @ObservedObject var viewModel: InvestmentViewModel
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        TextField("Название инвестиции", text: $name)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Picker("Тип инвестиции", selection: $selectedInvestmentType) {
                            ForEach(InvestmentType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
                        Picker("Категория", selection: $selectedCategory) {
                            ForEach(InvestmentCategory.allCases, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Сумма", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        
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
                    } header: {
                        Text("Параметры инвестиции")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Toggle("Учитывать в общих финансах", isOn: $includeInTotal)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Picker("Приоритет", selection: $selectedPriority) {
                            ForEach(InvestmentPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
                        Toggle("В избранном", isOn: $isFavorite)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Дополнительно")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(viewModel.state.editingInvestment == nil ? "Новая инвестиция" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
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
    
    private var isValid: Bool {
        !name.isEmpty &&
        parseNumber(amountText) != nil && parseNumber(amountText)! > 0
    }
    
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
            isFavorite: isFavorite
        ))
        
        dismiss()
    }
}

// MARK: - Display Currency Sheet

private struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: InvestmentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var availableCurrencies: [String] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if isLoading {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                } else {
                    List {
                        ForEach(availableCurrencies, id: \.self) { currency in
                            Button {
                                viewModel.handle(.setDisplayCurrency(currency))
                                dismiss()
                            } label: {
                                HStack {
                                    Text(currency)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    if viewModel.state.displayCurrency == currency {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.investmentsGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.investmentsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            .task {
                await loadAvailableCurrencies()
            }
        }
    }
    
    private func loadAvailableCurrencies() async {
        isLoading = true
        defer { isLoading = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        
        let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
        let fromInvestments = Set(viewModel.state.investments.map { $0.currency })
        availableCurrencies = Array(fromRateSource.union(fromInvestments)).sorted()
    }
}
