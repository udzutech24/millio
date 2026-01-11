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
        
        let card = Card(
            name: name,
            cardNumber: cardNumber,
            bank: Bank(rawValue: bankRaw) ?? .other,
            cardType: CardType(rawValue: cardTypeRaw) ?? .debit,
            currency: currency,
            balance: balance,
            creditLimit: data["creditLimit"] as? Double,
            expiryDate: data["expiryDate"] as? String,
            cardholderName: data["cardholderName"] as? String,
            cardColor: data["cardColor"] as? String,
            isFavorite: data["isFavorite"] as? Bool ?? false
        )
        
        // Восстанавливаем даты
        card.createdAt = Date(timeIntervalSince1970: createdAt)
        card.updatedAt = Date(timeIntervalSince1970: updatedAt)
        
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
