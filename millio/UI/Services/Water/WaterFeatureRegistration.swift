//
//  WaterFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Water для backup/restore
struct WaterFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(WaterEntry.self, typeName: "WaterEntry")
        ModelTypeRegistry.shared.register(WaterSettings.self, typeName: "WaterSettings")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(WaterEntryImporter.self)
        ModelTypeRegistry.shared.registerImporter(WaterSettingsImporter.self)
    }
}

// MARK: - Water Entry Importer

struct WaterEntryImporter: ModelImporter {
    static func importType() -> String {
        "WaterEntry"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let amount = data["amount"] as? Int,
              let timestamp = data["timestamp"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        let entry = WaterEntry(
            amount: amount,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
        context.insert(entry)
    }
}

// MARK: - Water Settings Importer

struct WaterSettingsImporter: ModelImporter {
    static func importType() -> String {
        "WaterSettings"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let genderRaw = data["genderRaw"] as? String,
              let height = data["height"] as? Int,
              let weight = data["weight"] as? Int,
              let activityLevelRaw = data["activityLevelRaw"] as? String,
              let targetAmount = data["targetAmount"] as? Int,
              let remindersEnabled = data["remindersEnabled"] as? Bool,
              let reminderInterval = data["reminderInterval"] as? Int else {
            throw AppError.backupCorrupted
        }
        
        let settings = WaterSettings(
            gender: Gender(rawValue: genderRaw) ?? .male,
            height: height,
            weight: weight,
            activityLevel: ActivityLevel(rawValue: activityLevelRaw) ?? .moderate,
            targetAmount: targetAmount,
            remindersEnabled: remindersEnabled,
            reminderInterval: reminderInterval
        )
        context.insert(settings)
    }
}
