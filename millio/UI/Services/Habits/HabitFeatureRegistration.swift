//
//  HabitFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 12.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Habit и HabitEntry для backup/restore
struct HabitFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(Habit.self, typeName: "Habit")
        ModelTypeRegistry.shared.register(HabitEntry.self, typeName: "HabitEntry")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(HabitImporter.self)
        ModelTypeRegistry.shared.registerImporter(HabitEntryImporter.self)
    }
}

// MARK: - Habit Importer

struct HabitImporter: ModelImporter {
    static func importType() -> String {
        "Habit"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String,
              let habitTypeRaw = data["habitTypeRaw"] as? String,
              let costPerUnit = data["costPerUnit"] as? Double,
              let currency = data["currency"] as? String,
              let startDate = data["startDate"] as? TimeInterval,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Проверяем, не существует ли уже привычка с такими же данными
        let existingHabitDescriptor = FetchDescriptor<Habit>(
            predicate: #Predicate<Habit> { habit in
                habit.name == name &&
                habit.habitTypeRaw == habitTypeRaw &&
                habit.costPerUnit == costPerUnit &&
                habit.currency == currency
            }
        )
        
        // Получаем frequency (для обратной совместимости используем daily по умолчанию)
        let frequencyRaw = data["frequencyRaw"] as? String ?? "daily"
        let frequency = HabitFrequency(rawValue: frequencyRaw) ?? .daily
        
        // Если привычка уже существует, обновляем ее данные вместо создания новой
        if let existingHabit = try? context.fetch(existingHabitDescriptor).first {
            existingHabit.isFavorite = data["isFavorite"] as? Bool ?? false
            existingHabit.startDate = Date(timeIntervalSince1970: startDate)
            existingHabit.frequency = frequency
            existingHabit.updatedAt = Date(timeIntervalSince1970: updatedAt)
            
            AppLogger.log(.info, category: "HabitImporter", "Updated existing habit '\(name)' instead of creating duplicate")
            return
        }
        
        // Создаем новую привычку только если она не существует
        let habit = Habit(
            name: name,
            habitType: HabitType(rawValue: habitTypeRaw) ?? .other,
            costPerUnit: costPerUnit,
            frequency: frequency,
            currency: currency,
            startDate: Date(timeIntervalSince1970: startDate),
            isFavorite: data["isFavorite"] as? Bool ?? false
        )
        
        habit.createdAt = Date(timeIntervalSince1970: createdAt)
        habit.updatedAt = Date(timeIntervalSince1970: updatedAt)
        
        context.insert(habit)
    }
}

// MARK: - HabitEntry Importer

struct HabitEntryImporter: ModelImporter {
    static func importType() -> String {
        "HabitEntry"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let habitUniqueID = data["habitUniqueID"] as? String,
              let entryDate = data["entryDate"] as? TimeInterval,
              let savedUnits = data["savedUnits"] as? Double,
              let createdAt = data["createdAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Проверяем, не существует ли уже запись с такими же данными
        // Проверяем, что дата в пределах одного дня (без использования abs)
        let dayStart = entryDate - 86400
        let dayEnd = entryDate + 86400
        let existingEntryDescriptor = FetchDescriptor<HabitEntry>(
            predicate: #Predicate<HabitEntry> { entry in
                entry.habitUniqueID == habitUniqueID &&
                entry.entryDate.timeIntervalSince1970 >= dayStart &&
                entry.entryDate.timeIntervalSince1970 <= dayEnd
            }
        )
        
        // Если запись уже существует, пропускаем
        if let _ = try? context.fetch(existingEntryDescriptor).first {
            AppLogger.log(.info, category: "HabitEntryImporter", "Skipping duplicate entry for habit '\(habitUniqueID)'")
            return
        }
        
        // Создаем новую запись только если она не существует
        let entry = HabitEntry(
            habitUniqueID: habitUniqueID,
            entryDate: Date(timeIntervalSince1970: entryDate),
            savedUnits: savedUnits,
            note: data["note"] as? String
        )
        
        entry.createdAt = Date(timeIntervalSince1970: createdAt)
        
        context.insert(entry)
    }
}
