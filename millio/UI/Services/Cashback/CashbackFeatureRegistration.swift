//
//  CashbackFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Cashback для backup/restore
struct CashbackFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(Cashback.self, typeName: "Cashback")
        ModelTypeRegistry.shared.register(CashbackCustomCategory.self, typeName: "CashbackCustomCategory")

        ModelTypeRegistry.shared.registerBackupExporter("Cashback") { context in
            let cashbackDescriptor = FetchDescriptor<Cashback>()
            let cashbacks = try context.fetch(cashbackDescriptor)
            
            var exported: [[String: Any]] = []
            exported.reserveCapacity(cashbacks.count)
            
            for cashback in cashbacks {
                let data = try cashback.export()
                var json = try BackupJSON.decodeExportedDict(data, typeName: "Cashback")
                
                json["_type"] = "Cashback"
                exported.append(json)
            }
            
            return exported
        }

        ModelTypeRegistry.shared.registerBackupExporter("CashbackCustomCategory") { context in
            let descriptor = FetchDescriptor<CashbackCustomCategory>()
            let customCategories = try context.fetch(descriptor)

            var exported: [[String: Any]] = []
            exported.reserveCapacity(customCategories.count)

            for category in customCategories {
                let data = try category.export()
                var json = try BackupJSON.decodeExportedDict(data, typeName: "CashbackCustomCategory")
                json["_type"] = "CashbackCustomCategory"
                exported.append(json)
            }

            return exported
        }
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(CashbackImporter.self)
        ModelTypeRegistry.shared.registerImporter(CashbackCustomCategoryImporter.self)
    }
}

// MARK: - Cashback Importer

struct CashbackImporter: ModelImporter {
    static func importType() -> String {
        "Cashback"
    }
    
    static var importPriority: Int { 20 }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String,
              let categoryRaw = data["categoryRaw"] as? String,
              let percentage = data["percentage"] as? Double,
              let cardIDs = data["cardIDs"] as? [String],
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        let monthKey = (data["monthKey"] as? String) ?? Cashback.monthKey(for: Date(timeIntervalSince1970: createdAt))
        
        let cardDescriptor = FetchDescriptor<Card>()
        let cards = (try? context.fetch(cardDescriptor)) ?? []
        let validUniqueIDs = Set(cards.map(\.cardUniqueID))
        guard cardIDs.allSatisfy({ validUniqueIDs.contains($0) }) else {
            throw AppError.backupCorrupted
        }
        
        let cashback = Cashback(
            name: name,
            categoryRaw: categoryRaw,
            percentage: percentage,
            cardIDs: cardIDs,
            monthKey: monthKey
        )
        
        // Восстанавливаем даты
        cashback.createdAt = Date(timeIntervalSince1970: createdAt)
        cashback.updatedAt = Date(timeIntervalSince1970: updatedAt)
        
        context.insert(cashback)
    }
}

struct CashbackCustomCategoryImporter: ModelImporter {
    static func importType() -> String {
        "CashbackCustomCategory"
    }

    static var importPriority: Int { 20 }

    static func `import`(from data: [String : Any], context: ModelContext) throws {
        guard let categoryID = data["categoryID"] as? String,
              let name = data["name"] as? String,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let normalizedName = (data["normalizedName"] as? String) ?? CashbackCustomCategory.normalize(name)

        let category = CashbackCustomCategory(name: name)
        category.categoryID = categoryID
        category.name = name
        category.normalizedName = normalizedName
        category.createdAt = Date(timeIntervalSince1970: createdAt)
        category.updatedAt = Date(timeIntervalSince1970: updatedAt)

        context.insert(category)
    }
}
