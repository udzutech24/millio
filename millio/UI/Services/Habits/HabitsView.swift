//
//  HabitsView.swift
//  millio
//
//  Created by Александр Сидоркин on 12.01.2026.
//

import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HabitViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                HabitsContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HabitViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Internal Content View

private struct HabitsContentViewInternal: View {
    @ObservedObject var viewModel: HabitViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Статистика
                    statsSection
                    
                    // Список привычек
                    habitsListSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Привычки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.handle(.addHabit)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showHabitEditor },
            set: { if !$0 { viewModel.handle(.hideHabitEditor) } }
        )) {
            HabitEditorViewInternal(viewModel: viewModel)
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
            // Общая экономия
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Всего привычек")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("\(viewModel.state.habits.count)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Общая экономия")
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
                                    colors: AppColors.habitsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                    }
                    
                    if viewModel.state.isLoadingRates {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(AppColors.textTertiary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatBalance(viewModel.state.totalSavings))
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.habitsGradient,
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
                                    colors: AppColors.habitsGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
        }
    }
    
    // MARK: - Habits List
    
    private var habitsListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Привычки")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !viewModel.state.habits.isEmpty {
                    Text("\(viewModel.state.habits.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            if viewModel.state.habits.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("Нет привычек")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    Text("Добавьте первую привычку, чтобы начать отслеживать экономию")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 40)
            } else {
                ForEach(viewModel.state.habits) { habit in
                    HabitRow(
                        habit: habit,
                        viewModel: viewModel
                    )
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

// MARK: - Habit Row

private struct HabitRow: View {
    let habit: Habit
    @ObservedObject var viewModel: HabitViewModel
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Основная область привычки (кликабельна)
                Button(action: {
                    viewModel.handle(.editHabit(habit))
                }) {
                    HStack(spacing: 16) {
                        // Иконка типа привычки
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: AppColors.habitsGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: habit.habitType.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        // Информация о привычке
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(habit.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                
                                if habit.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.habitsGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                // Общая экономия
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Сэкономлено:")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppColors.textTertiary)
                                    
                                    Text("\(formatBalance(HabitManager.shared.calculateTotalSavings(for: habit))) \(habit.currency)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                }
                                
                                // Стоимость за единицу
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Стоимость за единицу:")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppColors.textTertiary)
                                    
                                    Text("\(formatBalance(habit.costPerUnit)) \(habit.currency)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                // Кнопки действий
                VStack(spacing: 8) {
                    Button {
                        viewModel.handle(.toggleFavorite(habit))
                    } label: {
                        Image(systemName: habit.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                habit.isFavorite ?
                                LinearGradient(
                                    colors: AppColors.habitsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: [AppColors.textTertiary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(AppColors.error)
                    }
                    .confirmationDialog("Удалить привычку?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                        Button("Удалить", role: .destructive) {
                            viewModel.handle(.deleteHabit(habit))
                        }
                        Button("Отмена", role: .cancel) {}
                    } message: {
                        Text("Привычка \"\(habit.name)\" будет удалена без возможности восстановления.")
                    }
                }
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.habitsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    }
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

// MARK: - Display Currency Sheet

private struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: HabitViewModel
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
                                                    colors: AppColors.habitsGradient,
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
                            colors: AppColors.habitsGradient,
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
        
        // Загружаем курсы, чтобы получить актуальный список валют
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        
        // Получаем валюты из текущего источника курсов
        let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
        // Добавляем валюты из привычек пользователя
        let fromHabits = Set(viewModel.state.habits.map { $0.currency })
        // Объединяем и сортируем
        availableCurrencies = Array(fromRateSource.union(fromHabits)).sorted()
    }
}

// MARK: - Habit Editor View

private struct HabitEditorViewInternal: View {
    @ObservedObject var viewModel: HabitViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedHabitType: HabitType = .other
    @State private var costPerUnitText: String = ""
    @State private var selectedFrequency: HabitFrequency = .daily
    @State private var selectedCurrency: String = "RUB"
    @State private var startDate: Date = Date()
    @State private var isFavorite: Bool = false
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        TextField("Название привычки", text: $name)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Picker("Тип привычки", selection: $selectedHabitType) {
                            ForEach(HabitType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Стоимость за единицу", text: Binding(
                            get: { formatNumberForDisplay(costPerUnitText) },
                            set: { newValue in
                                // Нормализуем: убираем пробелы и заменяем запятую на точку
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                costPerUnitText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        
                        Picker("Частота потребления", selection: $selectedFrequency) {
                            ForEach(HabitFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.displayName).tag(frequency)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
                        DatePicker("Дата начала", selection: $startDate, displayedComponents: .date)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Параметры привычки")
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
                        
                        Toggle("В избранном", isOn: $isFavorite)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Дополнительно")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(viewModel.state.editingHabit == nil ? "Новая привычка" : "Редактировать")
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
                        saveHabit()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.habitsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingHabit {
                    name = editing.name
                    selectedHabitType = editing.habitType
                    costPerUnitText = String(format: "%.2f", editing.costPerUnit)
                    selectedFrequency = editing.frequency
                    selectedCurrency = editing.currency
                    startDate = editing.startDate
                    isFavorite = editing.isFavorite
                }
                
                // Загружаем доступные валюты
                loadAvailableCurrencies()
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        parseNumber(costPerUnitText) != nil && parseNumber(costPerUnitText)! > 0
    }
    
    // MARK: - Currency Loading
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            // Загружаем курсы, чтобы получить актуальный список валют
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            
            // Получаем валюты из текущего источника курсов
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            // Добавляем валюту текущей привычки, если она есть
            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) {
                currencies.append(selectedCurrency)
            }
            // Сортируем
            availableCurrencies = currencies.sorted()
        }
    }
    
    // MARK: - Number Formatting Helpers
    
    /// Нормализует число: убирает пробелы и заменяет запятую на точку
    private func normalizeNumber(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
    }
    
    /// Парсит число из строки (обрабатывает запятую и пробелы)
    private func parseNumber(_ text: String) -> Double? {
        let normalized = normalizeNumber(text)
        return Double(normalized)
    }
    
    /// Форматирует число для отображения с пробелами между тысячами
    private func formatNumberForDisplay(_ text: String) -> String {
        // Если текст пустой, возвращаем как есть
        guard !text.isEmpty else { return text }
        
        // Парсим число
        guard let number = parseNumber(text) else {
            // Если не число, возвращаем как есть (может быть в процессе ввода)
            return text
        }
        
        // Форматируем с пробелами между тысячами
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        // Определяем, есть ли десятичная часть
        let normalized = normalizeNumber(text)
        let hasDecimal = normalized.contains(".")
        if !hasDecimal {
            formatter.maximumFractionDigits = 0
        }
        
        return formatter.string(from: NSNumber(value: number)) ?? text
    }
    
    private func saveHabit() {
        guard let costPerUnit = parseNumber(costPerUnitText) else {
            return
        }
        
        viewModel.handle(.updateHabit(
            name: name,
            habitType: selectedHabitType,
            costPerUnit: costPerUnit,
            frequency: selectedFrequency,
            currency: selectedCurrency,
            startDate: startDate,
            isFavorite: isFavorite
        ))
        
        dismiss()
    }
}

#Preview {
    NavigationStack {
        HabitsView()
    }
}
