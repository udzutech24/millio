//
//  DebtsView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

struct DebtsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DebtViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                DebtsContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = DebtViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Internal Content View

private struct DebtsContentViewInternal: View {
    @ObservedObject var viewModel: DebtViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Статистика
                    statsSection
                    
                    // Список долгов
                    debtsListSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Долги")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.handle(.addDebt)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showDebtEditor },
            set: { if !$0 { viewModel.handle(.hideDebtEditor) } }
        )) {
            DebtEditorView(viewModel: viewModel)
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
                    Text("Всего долгов")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("\(viewModel.state.debts.count)")
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
                                    colors: AppColors.debtsGradient,
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
                                    colors: AppColors.debtsGradient,
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
                                    colors: AppColors.debtsGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
            
            // Детализация
            HStack(spacing: 12) {
                // Мне должны
                VStack(alignment: .leading, spacing: 4) {
                    Text("Мне должны")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalOwedToMe))
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
                                        colors: AppColors.debtsGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                }
                
                // Я должен
                VStack(alignment: .leading, spacing: 4) {
                    Text("Я должен")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalIOwe))
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
                                        colors: AppColors.debtsGradient,
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
    
    // MARK: - Debts List
    
    private var debtsListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Долги")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !viewModel.state.filteredDebts.isEmpty {
                    Text("\(viewModel.state.filteredDebts.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            if viewModel.state.filteredDebts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text(viewModel.state.debts.isEmpty ? "Нет долгов" : "Ничего не найдено")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    if viewModel.state.debts.isEmpty {
                        Text("Добавьте первый долг")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.state.filteredDebts) { debt in
                        DebtRow(debt: debt) {
                            viewModel.handle(.editDebt(debt))
                        } onDelete: {
                            viewModel.handle(.deleteDebt(debt))
                        } onToggleFavorite: {
                            viewModel.handle(.toggleFavorite(debt))
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

// MARK: - Debt Row

private struct DebtRow: View {
    let debt: Debt
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
                        // Иконка типа долга
                        Image(systemName: debt.debtType.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.debtsGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                        
                        // Информация о долге
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(debt.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                if debt.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.debtsGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            
                            if !debt.contactName.isEmpty {
                                Text(debt.contactName)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            
                            HStack(spacing: 4) {
                                Text(debt.debtType.displayName)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(AppColors.textTertiary)
                                
                                if debt.isOverdue {
                                    Text("• Просрочен")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppColors.error)
                                }
                            }
                        }
                        
                        Spacer(minLength: 8)
                        
                        // Финансовая информация
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(formatBalance(debt.amount)) \(debt.currency)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(
                                    debt.debtType == .owedToMe ? AppColors.textPrimary : AppColors.error
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            
                            if let dueDate = debt.dueDate {
                                Text(formatDate(dueDate))
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(
                                        debt.isOverdue ? AppColors.error : AppColors.textTertiary
                                    )
                            }
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
                        Image(systemName: debt.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                debt.isFavorite ?
                                LinearGradient(
                                    colors: AppColors.debtsGradient,
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
                    .confirmationDialog("Удалить долг?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                        Button("Удалить", role: .destructive) {
                            onDelete()
                        }
                        Button("Отмена", role: .cancel) {}
                    } message: {
                        Text("Долг \"\(debt.name)\" будет удален без возможности восстановления.")
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
                                colors: AppColors.debtsGradient,
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Debt Editor View

private struct DebtEditorView: View {
    @ObservedObject var viewModel: DebtViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedDebtType: DebtType = .iOwe
    @State private var amountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var contactName: String = ""
    @State private var dueDate: Date? = nil
    @State private var hasDueDate: Bool = false
    @State private var selectedPriority: DebtPriority = .normal
    @State private var isFavorite: Bool = false
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        TextField("Название долга", text: $name)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Picker("Тип долга", selection: $selectedDebtType) {
                            ForEach(DebtType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
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
                        
                        TextField("Кому/от кого", text: $contactName)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Toggle("Установить дату погашения", isOn: $hasDueDate)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        if hasDueDate {
                            DatePicker("Дата погашения", selection: Binding(
                                get: { dueDate ?? Date() },
                                set: { dueDate = $0 }
                            ), displayedComponents: .date)
                            .foregroundStyle(AppColors.textPrimary)
                        }
                    } header: {
                        Text("Параметры долга")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Picker("Приоритет", selection: $selectedPriority) {
                            ForEach(DebtPriority.allCases, id: \.self) { priority in
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
            .navigationTitle(viewModel.state.editingDebt == nil ? "Новый долг" : "Редактировать")
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
                        saveDebt()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.debtsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingDebt {
                    name = editing.name
                    selectedDebtType = editing.debtType
                    amountText = String(format: "%.2f", editing.amount)
                    selectedCurrency = editing.currency
                    contactName = editing.contactName
                    hasDueDate = editing.dueDate != nil
                    dueDate = editing.dueDate
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
    
    private func saveDebt() {
        guard let amount = parseNumber(amountText) else {
            return
        }
        
        viewModel.handle(.updateDebt(
            name: name,
            debtType: selectedDebtType,
            amount: amount,
            currency: selectedCurrency,
            contactName: contactName,
            dueDate: hasDueDate ? dueDate : nil,
            priority: selectedPriority,
            isFavorite: isFavorite
        ))
        
        dismiss()
    }
}

// MARK: - Display Currency Sheet

private struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: DebtViewModel
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
                                                    colors: AppColors.debtsGradient,
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
                            colors: AppColors.debtsGradient,
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
        let fromDebts = Set(viewModel.state.debts.map { $0.currency })
        availableCurrencies = Array(fromRateSource.union(fromDebts)).sorted()
    }
}
