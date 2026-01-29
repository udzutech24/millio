//
//  CardFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Card для backup/restore
struct CardFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(Card.self, typeName: "Card")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(CardImporter.self)
    }
}

// MARK: - Card Importer

struct CardImporter: ModelImporter {
    static func importType() -> String {
        "Card"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String,
              let cardNumber = data["cardNumber"] as? String,
              let bankRaw = data["bankRaw"] as? String,
              let cardTypeRaw = data["cardTypeRaw"] as? String,
              let currency = data["currency"] as? String,
              let balance = data["balance"] as? Double,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Проверяем, не существует ли уже карта с такими же данными (по cardUniqueID)
        // Используем комбинацию полей без createdAt для проверки, так как createdAt может немного отличаться
        let existingCardDescriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { card in
                card.name == name &&
                card.cardNumber == cardNumber &&
                card.bankRaw == bankRaw &&
                card.cardTypeRaw == cardTypeRaw &&
                card.currency == currency
            }
        )
        
        // Получаем priority (для обратной совместимости используем normal по умолчанию)
        let priorityRaw = data["priorityRaw"] as? String ?? "normal"
        let priority = CardPriority(rawValue: priorityRaw) ?? .normal
        
        // Если карта уже существует, обновляем её данные вместо создания новой
        if let existingCard = try? context.fetch(existingCardDescriptor).first {
            // Обновляем существующую карту
            if let uniqueID = data["cardUniqueID"] as? String, !uniqueID.isEmpty {
                existingCard.uniqueID = uniqueID
            } else if existingCard.uniqueID.isEmpty {
                // Устанавливаем uniqueID из legacy значений на основе замороженных данных из backup
                existingCard.uniqueID = "\(name)|\(cardNumber)|\(bankRaw)|\(cardTypeRaw)|\(currency)|\(createdAt)"
            }
            if let initialBalance = data["initialBalance"] as? Double {
                existingCard.initialBalance = initialBalance
                existingCard.hasInitialBalance = data["hasInitialBalance"] as? Bool ?? true
            }
            existingCard.balance = balance
            existingCard.priority = priority
            existingCard.creditLimit = data["creditLimit"] as? Double
            existingCard.expiryDate = data["expiryDate"] as? String
            existingCard.cardholderName = data["cardholderName"] as? String
            existingCard.cardColor = data["cardColor"] as? String
            existingCard.isFavorite = data["isFavorite"] as? Bool ?? false
            existingCard.includeInTotal = data["includeInTotal"] as? Bool ?? true
            existingCard.updatedAt = Date(timeIntervalSince1970: updatedAt)
            if let archivedAt = data["archivedAt"] as? TimeInterval {
                existingCard.archivedAt = Date(timeIntervalSince1970: archivedAt)
            }
            
            // Обновляем зашифрованные данные, если есть
            if let encryptedFullNumberStr = data["encryptedFullNumber"] as? String,
               let encryptedFullNumber = Data(base64Encoded: encryptedFullNumberStr) {
                existingCard.encryptedFullNumber = encryptedFullNumber
            }
            if let encryptedCVVStr = data["encryptedCVV"] as? String,
               let encryptedCVV = Data(base64Encoded: encryptedCVVStr) {
                existingCard.encryptedCVV = encryptedCVV
            }
            
            AppLogger.log(.info, category: "CardImporter", "Updated existing card '\(name)' instead of creating duplicate")
            return
        }
        
        // Создаем новую карту только если она не существует
        let card = Card(
            name: name,
            cardNumber: cardNumber,
            bank: Bank(rawValue: bankRaw) ?? .other,
            cardType: CardType(rawValue: cardTypeRaw) ?? .debit,
            priority: priority,
            currency: currency,
            balance: balance,
            creditLimit: data["creditLimit"] as? Double,
            expiryDate: data["expiryDate"] as? String,
            cardholderName: data["cardholderName"] as? String,
            cardColor: data["cardColor"] as? String,
            isFavorite: data["isFavorite"] as? Bool ?? false,
            includeInTotal: data["includeInTotal"] as? Bool ?? true
        )
        
        // Восстанавливаем даты
        card.createdAt = Date(timeIntervalSince1970: createdAt)
        card.updatedAt = Date(timeIntervalSince1970: updatedAt)
        if let archivedAt = data["archivedAt"] as? TimeInterval {
            card.archivedAt = Date(timeIntervalSince1970: archivedAt)
        }
        if let initialBalance = data["initialBalance"] as? Double {
            card.initialBalance = initialBalance
            card.hasInitialBalance = data["hasInitialBalance"] as? Bool ?? true
        } else {
            card.initialBalance = balance
            card.hasInitialBalance = true
        }
        if let uniqueID = data["cardUniqueID"] as? String, !uniqueID.isEmpty {
            card.uniqueID = uniqueID
        } else {
            // Устанавливаем uniqueID из legacy значений на основе замороженных данных из backup
            card.uniqueID = "\(name)|\(cardNumber)|\(bankRaw)|\(cardTypeRaw)|\(currency)|\(createdAt)"
        }
        
        // Восстанавливаем зашифрованные данные, если есть
        if let encryptedFullNumberStr = data["encryptedFullNumber"] as? String,
           let encryptedFullNumber = Data(base64Encoded: encryptedFullNumberStr) {
            card.encryptedFullNumber = encryptedFullNumber
        }
        if let encryptedCVVStr = data["encryptedCVV"] as? String,
           let encryptedCVV = Data(base64Encoded: encryptedCVVStr) {
            card.encryptedCVV = encryptedCVV
        }
        
        context.insert(card)
    }
}
