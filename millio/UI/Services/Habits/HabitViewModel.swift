//
//  HabitViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 12.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Habit State

struct HabitState {
    /// Все привычки
    var habits: [Habit] = []
    
    /// Показывать ли экран добавления/редактирования
    var showHabitEditor: Bool = false
    
    /// Редактируемая привычка (nil = новая привычка)
    var editingHabit: Habit? = nil
    
    /// Показывать ли sheet выбора валюты для отображения общей экономии
    var showDisplayCurrencySheet: Bool = false
    
    /// Валюта для отображения общей экономии
    var displayCurrency: String = "RUB"
    
    /// Общая экономия по всем привычкам (в выбранной валюте)
    var totalSavings: Double = 0.0
    
    /// Экономия по валютам (оригинальные значения)
    var savingsByCurrency: [String: Double] = [:]
    
    /// Флаг загрузки курсов
    var isLoadingRates: Bool = false
}

// MARK: - Habit Actions

enum HabitAction {
    case loadHabits
    case addHabit
    case editHabit(Habit)
    case deleteHabit(Habit)
    case toggleFavorite(Habit)
    case updateHabit(
        name: String,
        habitType: HabitType,
        costPerUnit: Double,
        frequency: HabitFrequency,
        currency: String,
        startDate: Date,
        isFavorite: Bool
    )
    case showHabitEditor
    case hideHabitEditor
    case showDisplayCurrencySheet
    case hideDisplayCurrencySheet
    case setDisplayCurrency(String)
    case addEntry(habit: Habit, date: Date, savedUnits: Double, note: String?)
    case deleteEntry(HabitEntry)
    case refreshRates
}

// MARK: - Habit ViewModel

@MainActor
final class HabitViewModel: ViewModelProtocol {
    @Published var state = HabitState()
    
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        HabitManager.shared.setup(modelContext: modelContext)
        handle(.loadHabits)
    }
    
    func handle(_ action: HabitAction) {
        switch action {
        case .loadHabits:
            loadHabits()
            
        case .addHabit:
            state.editingHabit = nil
            state.showHabitEditor = true
            
        case .editHabit(let habit):
            state.editingHabit = habit
            state.showHabitEditor = true
            
        case .deleteHabit(let habit):
            deleteHabit(habit)
            
        case .toggleFavorite(let habit):
            toggleFavorite(habit)
            
        case .updateHabit(let name, let habitType, let costPerUnit, let frequency, let currency, let startDate, let isFavorite):
            updateHabit(
                name: name,
                habitType: habitType,
                costPerUnit: costPerUnit,
                frequency: frequency,
                currency: currency,
                startDate: startDate,
                isFavorite: isFavorite
            )
            
        case .showHabitEditor:
            state.showHabitEditor = true
            
        case .hideHabitEditor:
            state.showHabitEditor = false
            state.editingHabit = nil
            
        case .showDisplayCurrencySheet:
            state.showDisplayCurrencySheet = true
            
        case .hideDisplayCurrencySheet:
            state.showDisplayCurrencySheet = false
            
        case .setDisplayCurrency(let currency):
            state.displayCurrency = currency
            calculateStats()
            
        case .addEntry(let habit, let date, let savedUnits, let note):
            addEntry(habit: habit, date: date, savedUnits: savedUnits, note: note)
            
        case .deleteEntry(let entry):
            deleteEntry(entry)
            
        case .refreshRates:
            Task {
                await refreshRates()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadHabits() {
        let descriptor = FetchDescriptor<Habit>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let habits = try? modelContext.fetch(descriptor) {
            state.habits = habits
            calculateStats()
        }
    }
    
    private func calculateStats() {
        // Считаем экономию по валютам
        var savingsByCurrency: [String: Double] = [:]
        
        for habit in state.habits {
            let savings = HabitManager.shared.calculateTotalSavings(for: habit)
            savingsByCurrency[habit.currency, default: 0] += savings
        }
        
        state.savingsByCurrency = savingsByCurrency
        
        // Конвертируем в выбранную валюту
        Task {
            await calculateTotalSavings()
        }
    }
    
    private func calculateTotalSavings() async {
        guard !state.savingsByCurrency.isEmpty else {
            state.totalSavings = 0.0
            return
        }
        
        var total: Double = 0.0
        
        for (currency, amount) in state.savingsByCurrency {
            if currency == state.displayCurrency {
                total += amount
            } else {
                // Конвертируем через CurrencyRateService
                if let rate = await CurrencyRateService.shared.getRate(from: currency, to: state.displayCurrency) {
                    total += amount * rate
                } else {
                    // Если курс не найден, просто добавляем оригинальную сумму
                    total += amount
                }
            }
        }
        
        state.totalSavings = total
    }
    
    func refreshRates() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        
        // Обновляем курсы
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        
        // Пересчитываем статистику
        await calculateTotalSavings()
    }
    
    private func updateHabit(
        name: String,
        habitType: HabitType,
        costPerUnit: Double,
        frequency: HabitFrequency,
        currency: String,
        startDate: Date,
        isFavorite: Bool
    ) {
        if let existing = state.editingHabit {
            // Обновляем существующую привычку
            existing.name = name
            existing.habitType = habitType
            existing.costPerUnit = costPerUnit
            existing.frequency = frequency
            existing.currency = currency
            existing.startDate = startDate
            existing.isFavorite = isFavorite
            existing.updatedAt = Date()
        } else {
            // Создаем новую привычку
            let newHabit = Habit(
                name: name,
                habitType: habitType,
                costPerUnit: costPerUnit,
                frequency: frequency,
                currency: currency,
                startDate: startDate,
                isFavorite: isFavorite
            )
            modelContext.insert(newHabit)
        }
        
        do {
            try modelContext.save()
            loadHabits()
            state.showHabitEditor = false
            state.editingHabit = nil
        } catch {
            AppLogger.log(.error, category: "Habit", "Failed to save habit: \(error.localizedDescription)")
        }
    }
    
    private func deleteHabit(_ habit: Habit) {
        // Удаляем все записи привычки
        let entries = HabitManager.shared.getEntries(for: habit)
        for entry in entries {
            modelContext.delete(entry)
        }
        
        // Удаляем саму привычку
        modelContext.delete(habit)
        
        do {
            try modelContext.save()
            loadHabits()
        } catch {
            AppLogger.log(.error, category: "Habit", "Failed to delete habit: \(error.localizedDescription)")
        }
    }
    
    private func toggleFavorite(_ habit: Habit) {
        habit.isFavorite.toggle()
        habit.updatedAt = Date()
        
        do {
            try modelContext.save()
            loadHabits()
        } catch {
            AppLogger.log(.error, category: "Habit", "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    private func addEntry(habit: Habit, date: Date, savedUnits: Double, note: String?) {
        let entry = HabitEntry(
            habitUniqueID: habit.habitUniqueID,
            entryDate: date,
            savedUnits: savedUnits,
            note: note
        )
        
        modelContext.insert(entry)
        
        do {
            try modelContext.save()
            calculateStats()
        } catch {
            AppLogger.log(.error, category: "Habit", "Failed to save entry: \(error.localizedDescription)")
        }
    }
    
    private func deleteEntry(_ entry: HabitEntry) {
        modelContext.delete(entry)
        
        do {
            try modelContext.save()
            calculateStats()
        } catch {
            AppLogger.log(.error, category: "Habit", "Failed to delete entry: \(error.localizedDescription)")
        }
    }
}
