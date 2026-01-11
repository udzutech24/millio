//
//  HabitManager.swift
//  millio
//
//  Created by Александр Сидоркин on 12.01.2026.
//

import Foundation
import SwiftData

/// Глобальный менеджер для доступа к привычкам из других сервисов
@MainActor
final class HabitManager {
    static let shared = HabitManager()
    
    private var modelContext: ModelContext?
    
    private init() {}
    
    /// Инициализация с ModelContext
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Получить все привычки
    func getAllHabits() -> [Habit] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Habit>()
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        
        return habits.sorted { habit1, habit2 in
            if habit1.isFavorite != habit2.isFavorite {
                return habit1.isFavorite
            }
            return habit1.updatedAt > habit2.updatedAt
        }
    }
    
    /// Получить избранные привычки
    func getFavoriteHabits() -> [Habit] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate<Habit> { $0.isFavorite == true }
        )
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        
        return habits.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    /// Получить записи для привычки
    func getEntries(for habit: Habit) -> [HabitEntry] {
        guard let modelContext = modelContext else { return [] }
        
        // Извлекаем habitUniqueID до создания предиката
        let habitID = habit.habitUniqueID
        
        let descriptor = FetchDescriptor<HabitEntry>(
            predicate: #Predicate<HabitEntry> { entry in
                entry.habitUniqueID == habitID
            },
            sortBy: [SortDescriptor(\.entryDate, order: .reverse)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Получить записи за период
    func getEntries(for habit: Habit, from startDate: Date, to endDate: Date) -> [HabitEntry] {
        guard let modelContext = modelContext else { return [] }
        
        // Извлекаем значения до создания предиката
        let habitID = habit.habitUniqueID
        let startTimestamp = startDate.timeIntervalSince1970
        let endTimestamp = endDate.timeIntervalSince1970
        
        let descriptor = FetchDescriptor<HabitEntry>(
            predicate: #Predicate<HabitEntry> { entry in
                entry.habitUniqueID == habitID &&
                entry.entryDate.timeIntervalSince1970 >= startTimestamp &&
                entry.entryDate.timeIntervalSince1970 <= endTimestamp
            },
            sortBy: [SortDescriptor(\.entryDate, order: .reverse)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Вычислить общую экономию для привычки
    /// Считает автоматически на основе даты начала и частоты потребления
    func calculateTotalSavings(for habit: Habit) -> Double {
        // Сначала считаем из ручных записей (если есть)
        let entries = getEntries(for: habit)
        let manualUnits = entries.reduce(0.0) { $0 + $1.savedUnits }
        
        // Затем считаем автоматическую экономию на основе частоты
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: habit.startDate)
        
        // Если дата начала в будущем, экономии нет
        guard startDay <= today else {
            return manualUnits * habit.costPerUnit
        }
        
        // Считаем количество прошедших дней
        let daysPassed = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        
        // Считаем количество сэкономленных единиц на основе частоты
        let autoUnits = Double(daysPassed) * habit.frequency.unitsPerDay
        
        // Общая экономия = (ручные записи + автоматическая) * стоимость
        return (manualUnits + autoUnits) * habit.costPerUnit
    }
    
    /// Вычислить экономию за период
    func calculateSavings(for habit: Habit, from startDate: Date, to endDate: Date) -> Double {
        // Сначала считаем из ручных записей за период
        let entries = getEntries(for: habit, from: startDate, to: endDate)
        let manualUnits = entries.reduce(0.0) { $0 + $1.savedUnits }
        
        // Затем считаем автоматическую экономию за период
        let calendar = Calendar.current
        let periodStart = calendar.startOfDay(for: max(startDate, habit.startDate))
        let periodEnd = calendar.startOfDay(for: min(endDate, Date()))
        
        guard periodStart <= periodEnd else {
            return manualUnits * habit.costPerUnit
        }
        
        let daysInPeriod = calendar.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 0
        let autoUnits = Double(daysInPeriod) * habit.frequency.unitsPerDay
        
        return (manualUnits + autoUnits) * habit.costPerUnit
    }
    
    /// Вычислить экономию за сегодня
    func calculateTodaySavings(for habit: Habit) -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return calculateSavings(for: habit, from: today, to: tomorrow)
    }
    
    /// Вычислить экономию за неделю
    func calculateWeekSavings(for habit: Habit) -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        return calculateSavings(for: habit, from: weekAgo, to: today)
    }
    
    /// Вычислить экономию за месяц
    func calculateMonthSavings(for habit: Habit) -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: today)!
        
        return calculateSavings(for: habit, from: monthAgo, to: today)
    }
    
    /// Получить общую экономию по всем привычкам
    func getTotalSavings() -> Double {
        getAllHabits().reduce(0.0) { $0 + calculateTotalSavings(for: $1) }
    }
    
    /// Получить общую экономию по валюте
    func getTotalSavings(currency: String) -> Double {
        getAllHabits()
            .filter { $0.currency == currency }
            .reduce(0.0) { $0 + calculateTotalSavings(for: $1) }
    }
}
