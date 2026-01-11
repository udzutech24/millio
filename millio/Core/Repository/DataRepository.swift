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
            
            // Экспортируем Card
            if typeName == "Card" {
                let cardDescriptor = FetchDescriptor<Card>()
                let cards = try modelContext.fetch(cardDescriptor)
                
                for card in cards {
                    let data = try card.export()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var cardDict = json
                        cardDict["_type"] = typeName
                        modelsData.append(cardDict)
                    }
                }
            }
            
            // Экспортируем Cashback
            if typeName == "Cashback" {
                let cashbackDescriptor = FetchDescriptor<Cashback>()
                let cashbacks = try modelContext.fetch(cashbackDescriptor)
                
                // Создаем маппинг persistentModelID -> cardUniqueID для карт
                let cardDescriptor = FetchDescriptor<Card>()
                let cards = try modelContext.fetch(cardDescriptor)
                var cardIDMapping: [String: String] = [:]
                for card in cards {
                    let cardIDString = String(describing: card.persistentModelID)
                    cardIDMapping[cardIDString] = card.cardUniqueID
                }
                
                for cashback in cashbacks {
                    let data = try cashback.export()
                    if var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Конвертируем cardIDs из persistentModelID в cardUniqueID
                        if let cardIDs = json["cardIDs"] as? [String] {
                            let cardUniqueIDs = cardIDs.compactMap { cardIDMapping[$0] }
                            json["cardIDs"] = cardUniqueIDs
                            // Сохраняем также старые cardIDs для обратной совместимости
                            json["_cardIDs_legacy"] = cardIDs
                        }
                        json["_type"] = typeName
                        modelsData.append(json)
                    }
                }
            }
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
        
        // Сначала импортируем все карты, чтобы создать маппинг cardUniqueID -> новый persistentModelID
        var cardUniqueIDMapping: [String: String] = [:]
        
        // Импорт через зарегистрированные импортеры из ModelTypeRegistry
        for modelData in modelsData {
            guard let typeName = modelData["_type"] as? String else { continue }
            
            // Если это карта, импортируем и сохраняем маппинг
            if typeName == "Card" {
                guard let importerType = ModelTypeRegistry.shared.getImporter(for: typeName) else {
                    AppLogger.log(.error, category: "DataRepository", "No importer found for type: \(typeName)")
                    continue
                }
                
                try importerType.`import`(from: modelData, context: modelContext)
                
                // Сохраняем, чтобы получить новый persistentModelID
                try modelContext.save()
                
                // Находим только что импортированную карту по содержимому (для создания маппинга)
                if let name = modelData["name"] as? String,
                   let cardNumber = modelData["cardNumber"] as? String,
                   let bankRaw = modelData["bankRaw"] as? String,
                   let cardTypeRaw = modelData["cardTypeRaw"] as? String,
                   let currency = modelData["currency"] as? String,
                   let createdAt = modelData["createdAt"] as? TimeInterval {
                    // Создаем cardUniqueID из данных
                    let cardUniqueID = "\(name)|\(cardNumber)|\(bankRaw)|\(cardTypeRaw)|\(currency)|\(createdAt)"
                    
                    // Ищем карту по содержимому (без проверки createdAt, так как комбинация других полей уникальна)
                    let cardDescriptor = FetchDescriptor<Card>(
                        predicate: #Predicate<Card> { card in
                            card.name == name &&
                            card.cardNumber == cardNumber &&
                            card.bankRaw == bankRaw &&
                            card.cardTypeRaw == cardTypeRaw &&
                            card.currency == currency
                        }
                    )
                    if let importedCard = try? modelContext.fetch(cardDescriptor).first {
                        let newCardID = String(describing: importedCard.persistentModelID)
                        cardUniqueIDMapping[cardUniqueID] = newCardID
                    }
                }
            }
        }
        
        // Теперь импортируем остальные модели (включая кешбэки)
        for modelData in modelsData {
            guard let typeName = modelData["_type"] as? String else { continue }
            
            // Карты уже импортированы
            if typeName == "Card" { continue }
            
            // Если это кешбэк, конвертируем cardUniqueIDs обратно в persistentModelID
            if typeName == "Cashback" {
                var cashbackData = modelData
                if var cardIDs = cashbackData["cardIDs"] as? [String] {
                    // Если cardIDs пустые, но есть старые cardIDs (обратная совместимость)
                    if cardIDs.isEmpty, let legacyCardIDs = cashbackData["_cardIDs_legacy"] as? [String] {
                        cardIDs = legacyCardIDs
                    }
                    
                    // Конвертируем cardUniqueIDs в новые persistentModelID
                    let newCardIDs = cardIDs.compactMap { cardUniqueIDMapping[$0] }
                    cashbackData["cardIDs"] = newCardIDs
                }
                
                guard let importerType = ModelTypeRegistry.shared.getImporter(for: typeName) else {
                    AppLogger.log(.error, category: "DataRepository", "No importer found for type: \(typeName)")
                    continue
                }
                
                try importerType.`import`(from: cashbackData, context: modelContext)
            } else {
                // Остальные типы импортируем как обычно
                guard let importerType = ModelTypeRegistry.shared.getImporter(for: typeName) else {
                    AppLogger.log(.error, category: "DataRepository", "No importer found for type: \(typeName)")
                    continue
                }
                
                try importerType.`import`(from: modelData, context: modelContext)
            }
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
            } else if typeName == "Card" {
                let cardDescriptor = FetchDescriptor<Card>()
                let cards = try modelContext.fetch(cardDescriptor)
                for card in cards {
                    modelContext.delete(card)
                }
            } else if typeName == "Cashback" {
                let cashbackDescriptor = FetchDescriptor<Cashback>()
                let cashbacks = try modelContext.fetch(cashbackDescriptor)
                for cashback in cashbacks {
                    modelContext.delete(cashback)
                }
            }
        }
        
        try modelContext.save()
    }
}
