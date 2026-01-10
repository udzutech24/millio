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
        // Создаём словарь для сериализации
        var exportDict: [String: Any] = [:]
        exportDict["version"] = "1.0"
        exportDict["timestamp"] = Date().timeIntervalSince1970
        
        // Экспортируем каждую модель из схемы
        var modelsData: [[String: Any]] = []
        
        // Получаем все модели через известные типы из схемы
        // В реальной реализации это можно расширить через регистрацию типов
        let itemDescriptor = FetchDescriptor<Item>()
        let items = try modelContext.fetch(itemDescriptor)
        
        for item in items {
            if let exportable = item as? Exportable {
                let data = try exportable.export()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var itemDict = json
                    itemDict["_type"] = "Item"
                    modelsData.append(itemDict)
                }
            }
        }
        
        exportDict["models"] = modelsData
        
        return try JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted)
    }
    
    func importAllData(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsData = json["models"] as? [[String: Any]] else {
            throw AppError.backupCorrupted
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
