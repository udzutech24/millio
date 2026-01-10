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
        
        // Экспортируем каждую модель из схемы через ModelTypeRegistry
        var modelsData: [[String: Any]] = []
        let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
        
        // Экспортируем каждый зарегистрированный тип
        for (typeName, _) in registeredTypes {
            // Для каждого типа создаем FetchDescriptor и экспортируем экземпляры
            // Это упрощенная реализация - в реальности нужна более сложная логика
            // для работы с разными типами через рефлексию
            
            // Экспортируем Item (базовый тип)
            if typeName == "Item" {
                let itemDescriptor = FetchDescriptor<Item>()
                let items = try modelContext.fetch(itemDescriptor)
                
                for item in items {
                    let data = try item.export()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var itemDict = json
                        itemDict["_type"] = typeName
                        modelsData.append(itemDict)
                    }
                }
            }
            // Здесь можно добавить экспорт других типов по мере их регистрации
        }
        
        // Обновляем metadata с реальным количеством моделей
        let updatedMetadata = BackupMetadata(
            version: metadata.version,
            timestamp: metadata.timestamp,
            schemaVersion: metadata.schemaVersion,
            modelCount: modelsData.count
        )
        
        let exportDict: [String: Any] = [
            "metadata": try metadataToDict(updatedMetadata),
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
        
        // Импорт через зарегистрированные импортеры из ModelTypeRegistry
        for modelData in modelsData {
            guard let typeName = modelData["_type"] as? String else { continue }
            
            // Получаем импортер для типа из реестра
            guard let importerType = ModelTypeRegistry.shared.getImporter(for: typeName) else {
                AppLogger.log(.error, category: "DataRepository", "No importer found for type: \(typeName)")
                continue
            }
            
            // Вызываем статический метод импорта
            try importerType.`import`(from: modelData, context: modelContext)
        }
        
        // Сохраняем все импортированные данные
        try modelContext.save()
    }
    
    func clearAllData() throws {
        // Очищаем все данные через зарегистрированные типы
        let registeredTypes = ModelTypeRegistry.shared.getExportableTypes()
        
        for (typeName, _) in registeredTypes {
            // Очищаем каждый тип
            if typeName == "Item" {
                let itemDescriptor = FetchDescriptor<Item>()
                let items = try modelContext.fetch(itemDescriptor)
                
                for item in items {
                    modelContext.delete(item)
                }
            }
            // Здесь можно добавить очистку других типов по мере их регистрации
        }
        
        try modelContext.save()
    }
}
