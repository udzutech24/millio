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
            schemaVersion: "2.0",
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
            
            // Экспортируем Credit
            if typeName == "Credit" {
                let creditDescriptor = FetchDescriptor<Credit>()
                let credits = try modelContext.fetch(creditDescriptor)
                
                for credit in credits {
                    let data = try credit.export()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var creditDict = json
                        creditDict["_type"] = typeName
                        modelsData.append(creditDict)
                    }
                }
            }
            
            // Экспортируем Investment
            if typeName == "Investment" {
                let investmentDescriptor = FetchDescriptor<Investment>()
                let investments = try modelContext.fetch(investmentDescriptor)
                
                for investment in investments {
                    let data = try investment.export()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var investmentDict = json
                        investmentDict["_type"] = typeName
                        modelsData.append(investmentDict)
                    }
                }
            }
            
            // Экспортируем FinanceGroup
            if typeName == "FinanceGroup" {
                let groupDescriptor = FetchDescriptor<FinanceGroup>()
                let groups = try modelContext.fetch(groupDescriptor)
                
                for group in groups {
                    let data = try group.export()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var groupDict = json
                        groupDict["_type"] = typeName
                        modelsData.append(groupDict)
                    }
                }
            }
            
            // Экспортируем FinanceAccount
            if typeName == "FinanceAccount" {
                let accountDescriptor = FetchDescriptor<FinanceAccount>()
                let accounts = try modelContext.fetch(accountDescriptor)
                
                for account in accounts {
                    let data = try account.export()
                    if var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Добавляем groupUniqueID для восстановления связи
                        if let group = account.group {
                            json["groupUniqueID"] = group.groupUniqueID
                        }
                        json["_type"] = typeName
                        modelsData.append(json)
                    }
                }
            }
            
            // Экспортируем HistoricalRate
            if typeName == "HistoricalRate" {
                let rateDescriptor = FetchDescriptor<HistoricalRate>()
                let rates = try modelContext.fetch(rateDescriptor)
                
                for rate in rates {
                    let data = try rate.export()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var rateDict = json
                        rateDict["_type"] = typeName
                        modelsData.append(rateDict)
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
                    let legacyCardUniqueID = "\(name)|\(cardNumber)|\(bankRaw)|\(cardTypeRaw)|\(currency)|\(createdAt)"
                    let cardUniqueID = (modelData["cardUniqueID"] as? String) ?? legacyCardUniqueID
                    
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
        
        // Импортируем FinanceGroup перед FinanceAccount
        var groupUniqueIDMapping: [String: FinanceGroup] = [:]
        for modelData in modelsData {
            guard let typeName = modelData["_type"] as? String, typeName == "FinanceGroup" else { continue }
            
            guard let importerType = ModelTypeRegistry.shared.getImporter(for: typeName) else {
                AppLogger.log(.error, category: "DataRepository", "No importer found for type: \(typeName)")
                continue
            }
            
            try importerType.`import`(from: modelData, context: modelContext)
            try modelContext.save()
            
            // Сохраняем маппинг groupUniqueID -> группа
            if let name = modelData["name"] as? String,
               let colorHex = modelData["colorHex"] as? String,
               let createdAt = modelData["createdAt"] as? TimeInterval {
                let groupUniqueID = "\(name)|\(colorHex)|\(createdAt)"
                let groupDescriptor = FetchDescriptor<FinanceGroup>(
                    predicate: #Predicate<FinanceGroup> { group in
                        group.name == name && group.colorHex == colorHex
                    }
                )
                if let importedGroup = try? modelContext.fetch(groupDescriptor).first {
                    groupUniqueIDMapping[groupUniqueID] = importedGroup
                }
            }
        }
        
        // Теперь импортируем остальные модели (включая кешбэки, кредиты и FinanceAccount)
        for modelData in modelsData {
            guard let typeName = modelData["_type"] as? String else { continue }
            
            // Карты и FinanceGroup уже импортированы
            if typeName == "Card" || typeName == "FinanceGroup" { continue }
            
            // Если это FinanceAccount, восстанавливаем связь с группой
            if typeName == "FinanceAccount" {
                let accountData = modelData
                if let groupUniqueID = accountData["groupUniqueID"] as? String,
                   let _ = groupUniqueIDMapping[groupUniqueID] {
                    // Связь будет установлена через импортер
                }
                
                guard let importerType = ModelTypeRegistry.shared.getImporter(for: typeName) else {
                    AppLogger.log(.error, category: "DataRepository", "No importer found for type: \(typeName)")
                    continue
                }
                
                try importerType.`import`(from: accountData, context: modelContext)
                
                // Устанавливаем связь с группой после импорта
                if let groupUniqueID = accountData["groupUniqueID"] as? String,
                   let group = groupUniqueIDMapping[groupUniqueID],
                   let accountTypeRaw = accountData["accountTypeRaw"] as? String,
                   let accountID = accountData["accountID"] as? String {
                    let accountDescriptor = FetchDescriptor<FinanceAccount>(
                        predicate: #Predicate<FinanceAccount> { account in
                            account.accountTypeRaw == accountTypeRaw && account.accountID == accountID
                        }
                    )
                    if let importedAccount = try? modelContext.fetch(accountDescriptor).first {
                        importedAccount.group = group
                    }
                }
            } else if typeName == "Cashback" {
                // Если это кешбэк, конвертируем cardUniqueIDs обратно в persistentModelID
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
                // Остальные типы (включая Credit) импортируем как обычно
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
            } else if typeName == "Credit" {
                let creditDescriptor = FetchDescriptor<Credit>()
                let credits = try modelContext.fetch(creditDescriptor)
                for credit in credits {
                    modelContext.delete(credit)
                }
            } else if typeName == "Investment" {
                let investmentDescriptor = FetchDescriptor<Investment>()
                let investments = try modelContext.fetch(investmentDescriptor)
                for investment in investments {
                    modelContext.delete(investment)
                }
            } else if typeName == "FinanceAccount" {
                let accountDescriptor = FetchDescriptor<FinanceAccount>()
                let accounts = try modelContext.fetch(accountDescriptor)
                for account in accounts {
                    modelContext.delete(account)
                }
            } else if typeName == "FinanceGroup" {
                let groupDescriptor = FetchDescriptor<FinanceGroup>()
                let groups = try modelContext.fetch(groupDescriptor)
                for group in groups {
                    modelContext.delete(group)
                }
            } else if typeName == "HistoricalRate" {
                let rateDescriptor = FetchDescriptor<HistoricalRate>()
                let rates = try modelContext.fetch(rateDescriptor)
                for rate in rates {
                    modelContext.delete(rate)
                }
            }
        }
        
        try modelContext.save()
    }
}
