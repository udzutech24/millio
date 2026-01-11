//
//  PlannedExpensesView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

struct PlannedExpensesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PlannedExpenseViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                PlannedExpensesContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = PlannedExpenseViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Internal Content View

private struct PlannedExpensesContentViewInternal: View {
    @ObservedObject var viewModel: PlannedExpenseViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Статистика
                    statsSection
                    
                    // Список расходов
                    expensesListSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Планирование")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.handle(.addExpense)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showExpenseEditor },
            set: { if !$0 { viewModel.handle(.hideExpenseEditor) } }
        )) {
            PlannedExpenseEditorView(viewModel: viewModel)
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
            // Общая сумма неоплаченных расходов
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Всего расходов")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("\(viewModel.state.expenses.count)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Неоплачено")
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
                                    colors: AppColors.plannedExpensesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalUnpaid))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.plannedExpensesGradient,
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
                                    colors: AppColors.plannedExpensesGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
            
            // Детализация
            if viewModel.state.overdueCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.error)
                    
                    Text("Просрочено: \(viewModel.state.overdueCount)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.error)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppColors.error, lineWidth: 1.5)
                        }
                }
            }
        }
    }
    
    // MARK: - Expenses List
    
    private var expensesListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Расходы")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !viewModel.state.filteredExpenses.isEmpty {
                    Text("\(viewModel.state.filteredExpenses.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            if viewModel.state.filteredExpenses.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text(viewModel.state.expenses.isEmpty ? "Нет расходов" : "Ничего не найдено")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    if viewModel.state.expenses.isEmpty {
                        Text("Добавьте первый планируемый расход")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.state.filteredExpenses) { expense in
                        PlannedExpenseRow(expense: expense) {
                            viewModel.handle(.editExpense(expense))
                        } onDelete: {
                            viewModel.handle(.deleteExpense(expense))
                        } onToggleFavorite: {
                            viewModel.handle(.toggleFavorite(expense))
                        } onTogglePaid: {
                            viewModel.handle(.togglePaid(expense))
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

// MARK: - Planned Expense Row

private struct PlannedExpenseRow: View {
    let expense: PlannedExpense
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    let onTogglePaid: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Основная область (кликабельна)
                Button(action: onEdit) {
                    HStack(spacing: 12) {
                        // Иконка категории
                        Image(systemName: expense.category.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.plannedExpensesGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                        
                        // Информация о расходе
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(expense.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                if expense.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.plannedExpensesGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            
                            Text(expense.category.displayName)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                            
                            HStack(spacing: 4) {
                                Text(formatDate(expense.plannedDate))
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(AppColors.textTertiary)
                                
                                if expense.isOverdue {
                                    Text("• Просрочен")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppColors.error)
                                } else if expense.daysUntilPayment >= 0 {
                                    Text("• Через \(expense.daysUntilPayment) дн.")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                        }
                        
                        Spacer(minLength: 8)
                        
                        // Финансовая информация
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(formatBalance(expense.amount)) \(expense.currency)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            
                            if expense.isPaid {
                                Text("Оплачено")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                
                // Кнопки действий
                VStack(spacing: 8) {
                    // Кнопка избранного
                    Button {
                        onToggleFavorite()
                    } label: {
                        Image(systemName: expense.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                expense.isFavorite ?
                                LinearGradient(
                                    colors: AppColors.plannedExpensesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: [AppColors.textTertiary, AppColors.textTertiary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    
                    // Кнопка оплаты
                    Button {
                        onTogglePaid()
                    } label: {
                        Image(systemName: expense.isPaid ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                expense.isPaid ?
                                LinearGradient(
                                    colors: AppColors.plannedExpensesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: [AppColors.textTertiary, AppColors.textTertiary],
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
                }
            }
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.plannedExpensesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: expense.isFavorite ? 1.5 : 0
                            )
                    }
            }
        }
        .confirmationDialog("Удалить расход?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                onDelete()
            }
            Button("Отмена", role: .cancel) {}
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
    }
}

// MARK: - Planned Expense Editor View

private struct PlannedExpenseEditorView: View {
    @ObservedObject var viewModel: PlannedExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var plannedDate: Date = Date()
    @State private var selectedCategory: PlannedExpenseCategory = .other
    @State private var selectedPriority: PlannedExpensePriority = .normal
    @State private var isFavorite: Bool = false
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        TextField("Название расхода", text: $name)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
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
                        
                        DatePicker("Дата платежа", selection: $plannedDate, displayedComponents: .date)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Picker("Категория", selection: $selectedCategory) {
                            ForEach(PlannedExpenseCategory.allCases, id: \.self) { category in
                                HStack {
                                    Image(systemName: category.icon)
                                    Text(category.displayName)
                                }
                                .tag(category)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Параметры расхода")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Picker("Приоритет", selection: $selectedPriority) {
                            ForEach(PlannedExpensePriority.allCases, id: \.self) { priority in
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
            .navigationTitle(viewModel.state.editingExpense == nil ? "Новый расход" : "Редактировать")
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
                        saveExpense()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.plannedExpensesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingExpense {
                    name = editing.name
                    amountText = String(format: "%.2f", editing.amount)
                    selectedCurrency = editing.currency
                    plannedDate = editing.plannedDate
                    selectedCategory = editing.category
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
    
    private func saveExpense() {
        guard let amount = parseNumber(amountText) else {
            return
        }
        
        viewModel.handle(.updateExpense(
            name: name,
            amount: amount,
            currency: selectedCurrency,
            plannedDate: plannedDate,
            category: selectedCategory,
            priority: selectedPriority,
            isFavorite: isFavorite
        ))
        
        dismiss()
    }
}

// MARK: - Display Currency Sheet

private struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: PlannedExpenseViewModel
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
                                                    colors: AppColors.plannedExpensesGradient,
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
                            colors: AppColors.plannedExpensesGradient,
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
        let fromExpenses = Set(viewModel.state.expenses.map { $0.currency })
        availableCurrencies = Array(fromRateSource.union(fromExpenses)).sorted()
    }
}
