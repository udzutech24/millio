//
//  DataRepository.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

protocol DataRepositoryProtocol {
    func exportAllData() throws -> Data
    func importAllData(_ data: Data) throws
    func clearAllData() throws
}

final class DataRepository: DataRepositoryProtocol {
    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    
    init(modelContext: ModelContext, modelContainer: ModelContainer) {
        self.modelContext = modelContext
        self.modelContainer = modelContainer
    }
    
    func exportAllData() throws -> Data {
        let metadata = BackupMetadata(
            version: .current,
            timestamp: Date(),
            schemaVersion: "1.0",
            modelCount: 0
        )
        
        // Экспортируем каждую модель из схемы
        var modelsData: [[String: Any]] = []
        
        // Экспортируем Item (базовый тип)
        // TODO: Использовать ModelTypeRegistry для экспорта всех зарегистрированных типов
        let itemDescriptor = FetchDescriptor<Item>()
        let items = try modelContext.fetch(itemDescriptor)
        
        for item in items {
            // Item уже Persistable, который включает Exportable, поэтому проверка не нужна
            let data = try item.export()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var itemDict = json
                itemDict["_type"] = "Item"
                modelsData.append(itemDict)
            }
        }
        
        // TODO: Экспорт других зарегистрированных типов через рефлексию
        // Это требует более сложной реализации с использованием ModelContainer.schema
        
        let exportDict: [String: Any] = [
            "metadata": try metadataToDict(metadata),
            "models": modelsData
        ]
        
        return try JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted)
    }
    
    private func metadataToDict(_ metadata: BackupMetadata) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    
    func importAllData(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsData = json["models"] as? [[String: Any]] else {
            throw AppError.backupCorrupted
        }
        
        // Проверяем версию backup
        if let metadataDict = json["metadata"] as? [String: Any] {
            let decoder = JSONDecoder()
            if let metadataData = try? JSONSerialization.data(withJSONObject: metadataDict),
               let metadata = try? decoder.decode(BackupMetadata.self, from: metadataData) {
                // Проверяем совместимость версий
                if !metadata.version.isCompatible(with: .current) {
                    throw AppError.incompatibleSchemaVersion
                }
            }
        }
        
        // Импорт будет реализован через конкретные типы моделей
        // Ядро не знает конкретные типы, поэтому это делегируется фичам
        // В реальной реализации фичи должны зарегистрировать свои импортеры
        for modelData in modelsData {
            guard let type = modelData["_type"] as? String else { continue }
            
            // Пример импорта для Item
            if type == "Item" {
                // Парсинг и создание Item через ModelContext
                // Это упрощённая реализация
            }
        }
    }
    
    func clearAllData() throws {
        // Очищаем все данные через известные типы
        let itemDescriptor = FetchDescriptor<Item>()
        let items = try modelContext.fetch(itemDescriptor)
        
        for item in items {
            modelContext.delete(item)
        }
        
        try modelContext.save()
    }
}
