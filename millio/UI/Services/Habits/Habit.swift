//
//  Habit.swift
//  millio
//
//  Created by Александр Сидоркин on 12.01.2026.
//

import Foundation
import SwiftData

/// Тип привычки
enum HabitType: String, Codable, CaseIterable {
    case smoking = "smoking" // Курение
    case alcohol = "alcohol" // Алкоголь
    case gambling = "gambling" // Казино/азартные игры
    case coffee = "coffee" // Кофе навынос
    case subscription = "subscription" // Подписки
    case fastFood = "fast_food" // Фастфуд
    case other = "other" // Другое
    
    var displayName: String {
        switch self {
        case .smoking: return "Курение"
        case .alcohol: return "Алкоголь"
        case .gambling: return "Казино"
        case .coffee: return "Кофе"
        case .subscription: return "Подписки"
        case .fastFood: return "Фастфуд"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .smoking: return "flame.fill"
        case .alcohol: return "wineglass.fill"
        case .gambling: return "dice.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .subscription: return "play.rectangle.fill"
        case .fastFood: return "takeoutbag.and.cup.and.straw.fill"
        case .other: return "star.fill"
        }
    }
}

/// Частота потребления привычки
enum HabitFrequency: String, Codable, CaseIterable {
    case daily = "daily" // В день
    case weekly = "weekly" // В неделю
    case monthly = "monthly" // В месяц
    case yearly = "yearly" // В год
    
    var displayName: String {
        switch self {
        case .daily: return "В день"
        case .weekly: return "В неделю"
        case .monthly: return "В месяц"
        case .yearly: return "В год"
        }
    }
    
    /// Количество единиц в день для расчета
    var unitsPerDay: Double {
        switch self {
        case .daily: return 1.0
        case .weekly: return 1.0 / 7.0
        case .monthly: return 1.0 / 30.0
        case .yearly: return 1.0 / 365.0
        }
    }
}

/// Привычка
@Model
final class Habit: Persistable {
    /// Название привычки
    var name: String = ""
    
    /// Тип привычки
    var habitTypeRaw: String = "other"
    
    /// Стоимость одной единицы (пачка, бутылка, подписка и т.д.)
    var costPerUnit: Double = 0.0
    
    /// Частота потребления
    var frequencyRaw: String = "daily"
    
    /// Валюта
    var currency: String = "RUB"
    
    /// Дата начала отслеживания
    var startDate: Date = Date()
    
    /// Избранная привычка
    var isFavorite: Bool = false
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    var habitType: HabitType {
        get { HabitType(rawValue: habitTypeRaw) ?? .other }
        set { habitTypeRaw = newValue.rawValue }
    }
    
    var frequency: HabitFrequency {
        get { HabitFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }
    
    /// Общая экономия (вычисляется из записей)
    var totalSavings: Double {
        // Будет вычисляться через HabitManager
        0.0
    }
    
    init(
        name: String,
        habitType: HabitType = .other,
        costPerUnit: Double,
        frequency: HabitFrequency = .daily,
        currency: String = "RUB",
        startDate: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.name = name
        self.habitTypeRaw = habitType.rawValue
        self.costPerUnit = costPerUnit
        self.frequencyRaw = frequency.rawValue
        self.currency = currency
        self.startDate = startDate
        self.isFavorite = isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    /// Уникальный идентификатор привычки для восстановления связей при restore
    var habitUniqueID: String {
        "\(name)|\(habitTypeRaw)|\(costPerUnit)|\(frequencyRaw)|\(currency)|\(startDate.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "Habit",
            "name": name,
            "habitTypeRaw": habitTypeRaw,
            "costPerUnit": costPerUnit,
            "frequencyRaw": frequencyRaw,
            "currency": currency,
            "startDate": startDate.timeIntervalSince1970,
            "isFavorite": isFavorite,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "habitUniqueID": habitUniqueID
        ]
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["habitTypeRaw"] as? String != nil,
              dict["costPerUnit"] as? Double != nil,
              dict["currency"] as? String != nil,
              dict["startDate"] as? TimeInterval != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "Habit" &&
        dict["name"] as? String != nil &&
        dict["habitTypeRaw"] as? String != nil &&
        dict["costPerUnit"] as? Double != nil &&
        dict["currency"] as? String != nil &&
        dict["startDate"] as? TimeInterval != nil
    }
}
