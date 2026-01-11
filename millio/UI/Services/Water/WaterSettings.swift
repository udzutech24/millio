//
//  WaterSettings.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Настройки для расчета нормы воды
enum Gender: String, Codable, CaseIterable {
    case male = "male"
    case female = "female"
    
    var displayName: String {
        switch self {
        case .male: return "Мужской"
        case .female: return "Женский"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable {
    case low = "low"
    case moderate = "moderate"
    case high = "high"
    case veryHigh = "veryHigh"
    
    var displayName: String {
        switch self {
        case .low: return "Низкая"
        case .moderate: return "Умеренная"
        case .high: return "Высокая"
        case .veryHigh: return "Очень высокая"
        }
    }
    
    var multiplier: Double {
        switch self {
        case .low: return 1.0
        case .moderate: return 1.2
        case .high: return 1.4
        case .veryHigh: return 1.6
        }
    }
}

/// Настройки трекера воды
@Model
final class WaterSettings: Persistable {
    /// Пол пользователя
    var genderRaw: String
    
    /// Рост в сантиметрах
    var height: Int
    
    /// Вес в килограммах
    var weight: Int
    
    /// Уровень физической активности
    var activityLevelRaw: String
    
    /// Целевое количество воды в миллилитрах (0 = автоматический расчет)
    var targetAmount: Int
    
    /// Включены ли напоминания
    var remindersEnabled: Bool
    
    /// Интервал напоминаний в минутах
    var reminderInterval: Int
    
    var gender: Gender {
        get {
            Gender(rawValue: genderRaw) ?? .male
        }
        set {
            genderRaw = newValue.rawValue
        }
    }
    
    var activityLevel: ActivityLevel {
        get {
            ActivityLevel(rawValue: activityLevelRaw) ?? .moderate
        }
        set {
            activityLevelRaw = newValue.rawValue
        }
    }
    
    init(
        gender: Gender = .male,
        height: Int = 175,
        weight: Int = 70,
        activityLevel: ActivityLevel = .moderate,
        targetAmount: Int = 0,
        remindersEnabled: Bool = false,
        reminderInterval: Int = 120
    ) {
        self.genderRaw = gender.rawValue
        self.height = height
        self.weight = weight
        self.activityLevelRaw = activityLevel.rawValue
        self.targetAmount = targetAmount
        self.remindersEnabled = remindersEnabled
        self.reminderInterval = reminderInterval
    }
    
    /// Рассчитывает рекомендуемую норму воды в миллилитрах
    func calculateRecommendedAmount() -> Int {
        if targetAmount > 0 {
            return targetAmount
        }
        
        // Формула: базовый расчет + активность
        // Базовый расчет: вес * 30 мл (для мужчин) или вес * 25 мл (для женщин)
        let baseMultiplier = gender == .male ? 30.0 : 25.0
        let baseAmount = Double(weight) * baseMultiplier
        
        // Учитываем активность
        let activityMultiplier = activityLevel.multiplier
        let recommended = baseAmount * activityMultiplier
        
        // Округляем до 100 мл
        return Int((recommended / 100.0).rounded()) * 100
    }
    
    // MARK: - Exportable
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "WaterSettings",
            "genderRaw": genderRaw,
            "height": height,
            "weight": weight,
            "activityLevelRaw": activityLevelRaw,
            "targetAmount": targetAmount,
            "remindersEnabled": remindersEnabled,
            "reminderInterval": reminderInterval
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["genderRaw"] as? String != nil,
              dict["height"] as? Int != nil,
              dict["weight"] as? Int != nil,
              dict["activityLevelRaw"] as? String != nil,
              dict["targetAmount"] as? Int != nil,
              dict["remindersEnabled"] as? Bool != nil,
              dict["reminderInterval"] as? Int != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
}
