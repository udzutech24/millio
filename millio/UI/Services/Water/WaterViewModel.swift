//
//  WaterViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Water State

struct WaterState {
    /// Записи о выпитой воде за сегодня
    var todayEntries: [WaterEntry] = []
    
    /// Общее количество выпитой воды за сегодня (мл)
    var todayAmount: Int = 0
    
    /// Целевое количество воды (мл)
    var targetAmount: Int = 2000
    
    /// Процент выполнения цели
    var progress: Double = 0.0
    
    /// Настройки
    var settings: WaterSettings?
    
    /// Статистика за последние 7 дней
    var weeklyStats: [DailyStat] = []
    
    /// Показывать ли экран настроек
    var showSettings: Bool = false
    
    /// Показывать ли диалог добавления воды
    var showAddWaterDialog: Bool = false
    
    /// Выбранное количество для добавления
    var selectedAmount: Int = 250
    
    /// Toast сообщение
    var toastMessage: String? = nil
    
    /// Показывать ли toast
    var showToast: Bool = false
}

struct DailyStat: Identifiable {
    let id: Date
    let date: Date
    let amount: Int
    let target: Int
}

// MARK: - Water Actions

enum WaterAction {
    case loadData
    case addWater(Int)
    case deleteEntry(WaterEntry)
    case updateSettings(WaterSettings)
    case showSettings
    case hideSettings
    case showAddWaterDialog
    case hideAddWaterDialog
    case selectAmount(Int)
}

// MARK: - Water ViewModel

@MainActor
final class WaterViewModel: ViewModelProtocol {
    @Published var state = WaterState()
    
    let modelContext: ModelContext
    private var settingsQuery: FetchDescriptor<WaterSettings> {
        FetchDescriptor<WaterSettings>()
    }
    private var entriesQuery: FetchDescriptor<WaterEntry> {
        let descriptor = FetchDescriptor<WaterEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return descriptor
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadData()
    }
    
    func handle(_ action: WaterAction) {
        switch action {
        case .loadData:
            loadData()
            
        case .addWater(let amount):
            addWater(amount: amount)
            
        case .deleteEntry(let entry):
            deleteEntry(entry)
            
        case .updateSettings(let settings):
            updateSettings(settings)
            
        case .showSettings:
            state.showSettings = true
            
        case .hideSettings:
            state.showSettings = false
            
        case .showAddWaterDialog:
            state.showAddWaterDialog = true
            
        case .hideAddWaterDialog:
            state.showAddWaterDialog = false
            
        case .selectAmount(let amount):
            state.selectedAmount = amount
        }
    }
    
    // MARK: - Private Methods
    
    private func loadData() {
        // Загружаем настройки
        if let settings = try? modelContext.fetch(settingsQuery).first {
            state.settings = settings
            state.targetAmount = settings.calculateRecommendedAmount()
        } else {
            // Создаем настройки по умолчанию
            let defaultSettings = WaterSettings()
            modelContext.insert(defaultSettings)
            try? modelContext.save()
            state.settings = defaultSettings
            state.targetAmount = defaultSettings.calculateRecommendedAmount()
        }
        
        // Загружаем записи за сегодня
        loadTodayEntries()
        
        // Загружаем статистику за неделю
        loadWeeklyStats()
    }
    
    private func loadTodayEntries() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        // Сначала попробуем загрузить все записи без предиката для отладки
        let allDescriptor = FetchDescriptor<WaterEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        if let allEntries = try? modelContext.fetch(allDescriptor) {
            AppLogger.log(.info, category: "Water", "Total entries in context: \(allEntries.count)")
            for entry in allEntries {
                AppLogger.log(.info, category: "Water", "Entry: \(entry.amount) ml at \(entry.timestamp)")
            }
        }
        
        let descriptor = FetchDescriptor<WaterEntry>(
            predicate: #Predicate<WaterEntry> { entry in
                entry.timestamp >= today && entry.timestamp < tomorrow
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let entries = try modelContext.fetch(descriptor)
            state.todayEntries = entries
            state.todayAmount = entries.reduce(0) { $0 + $1.amount }
            updateProgress()
            AppLogger.log(.info, category: "Water", "Loaded \(entries.count) entries for today, total: \(state.todayAmount) ml")
        } catch {
            AppLogger.log(.error, category: "Water", "Failed to fetch today entries: \(error.localizedDescription)")
        }
    }
    
    private func loadWeeklyStats() {
        let calendar = Calendar.current
        var stats: [DailyStat] = []
        
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else {
                continue
            }
            
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let descriptor = FetchDescriptor<WaterEntry>(
                predicate: #Predicate<WaterEntry> { entry in
                    entry.timestamp >= dayStart && entry.timestamp < dayEnd
                }
            )
            
            let entries = (try? modelContext.fetch(descriptor)) ?? []
            let amount = entries.reduce(0) { $0 + $1.amount }
            let target = state.settings?.calculateRecommendedAmount() ?? 2000
            
            stats.append(DailyStat(id: dayStart, date: dayStart, amount: amount, target: target))
        }
        
        state.weeklyStats = stats.reversed()
    }
    
    private func addWater(amount: Int) {
        guard amount > 0 else {
            AppLogger.log(.error, category: "Water", "Invalid amount: \(amount)")
            return
        }
        
        AppLogger.log(.info, category: "Water", "Adding water: \(amount) ml")
        
        let entry = WaterEntry(amount: amount)
        modelContext.insert(entry)
        
        AppLogger.log(.info, category: "Water", "Entry inserted. ModelContext has changes: \(modelContext.hasChanges)")
        
        do {
            try modelContext.save()
            AppLogger.log(.info, category: "Water", "Water entry saved successfully. ModelContext has changes after save: \(modelContext.hasChanges)")
            
            // Перезагружаем данные сразу
            loadTodayEntries()
            loadWeeklyStats()
            state.showAddWaterDialog = false
        } catch {
            AppLogger.log(.error, category: "Water", "Failed to save water entry: \(error.localizedDescription)")
            // Показываем ошибку пользователю
            state.toastMessage = "Ошибка при сохранении: \(error.localizedDescription)"
            state.showToast = true
        }
    }
    
    private func deleteEntry(_ entry: WaterEntry) {
        modelContext.delete(entry)
        
        do {
            try modelContext.save()
            loadTodayEntries()
            loadWeeklyStats()
        } catch {
            AppLogger.log(.error, category: "Water", "Failed to delete water entry: \(error.localizedDescription)")
        }
    }
    
    private func updateSettings(_ settings: WaterSettings) {
        if let existing = state.settings {
            existing.gender = settings.gender
            existing.height = settings.height
            existing.weight = settings.weight
            existing.activityLevel = settings.activityLevel
            existing.targetAmount = settings.targetAmount
            existing.remindersEnabled = settings.remindersEnabled
            existing.reminderInterval = settings.reminderInterval
        } else {
            modelContext.insert(settings)
            state.settings = settings
        }
        
        do {
            try modelContext.save()
            state.targetAmount = settings.calculateRecommendedAmount()
            updateProgress()
            state.showSettings = false
        } catch {
            AppLogger.log(.error, category: "Water", "Failed to save settings: \(error.localizedDescription)")
        }
    }
    
    private func updateProgress() {
        guard state.targetAmount > 0 else {
            state.progress = 0.0
            return
        }
        state.progress = min(1.0, Double(state.todayAmount) / Double(state.targetAmount))
    }
}
