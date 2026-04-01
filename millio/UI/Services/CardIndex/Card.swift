//
//  Card.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Тип карты
enum CardType: String, Codable, CaseIterable {
    case debit = "debit"
    case credit = "credit"
    
    var displayName: String {
        displayName(for: AppLocalization.currentAppLocale)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .debit: return AppLocalization.string("finances.card.type.debit", locale: locale)
        case .credit: return AppLocalization.string("finances.card.type.credit", locale: locale)
        }
    }
    
    var icon: String {
        switch self {
        case .debit: return "creditcard.fill"
        case .credit: return "creditcard.trianglebadge.exclamationmark.fill"
        }
    }
}

/// Приоритет карты
enum CardPriority: String, Codable, CaseIterable {
    case low = "low" // Низкий
    case normal = "normal" // Обычный
    case high = "high" // Высокий
    
    var displayName: String {
        displayName(for: AppLocalization.currentAppLocale)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .low: return AppLocalization.string("finances.priority.low", locale: locale)
        case .normal: return AppLocalization.string("finances.priority.normal", locale: locale)
        case .high: return AppLocalization.string("finances.priority.high", locale: locale)
        }
    }
    
    /// Порядок сортировки (меньше = выше в списке)
    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

/// Банк
enum Bank: String, Codable, CaseIterable {
    case sberbank = "sberbank"
    case vtb = "vtb"
    case alfa = "alfa"
    case tinkoff = "tinkoff"
    case raiffeisen = "raiffeisen"
    case gazprombank = "gazprombank"
    case otkritie = "otkritie"
    case rosbank = "rosbank"
    case other = "other"
    
    var displayName: String {
        displayName(for: AppLocalization.currentAppLocale)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .sberbank: return AppLocalization.string("finances.bank.sberbank", locale: locale)
        case .vtb: return AppLocalization.string("finances.bank.vtb", locale: locale)
        case .alfa: return AppLocalization.string("finances.bank.alfa", locale: locale)
        case .tinkoff: return AppLocalization.string("finances.bank.tinkoff", locale: locale)
        case .raiffeisen: return AppLocalization.string("finances.bank.raiffeisen", locale: locale)
        case .gazprombank: return AppLocalization.string("finances.bank.gazprombank", locale: locale)
        case .otkritie: return AppLocalization.string("finances.bank.otkritie", locale: locale)
        case .rosbank: return AppLocalization.string("finances.bank.rosbank", locale: locale)
        case .other: return AppLocalization.string("finances.bank.other", locale: locale)
        }
    }
    
    var icon: String {
        switch self {
        case .sberbank: return "building.2.fill"
        case .vtb: return "building.2.fill"
        case .alfa: return "building.2.fill"
        case .tinkoff: return "building.2.fill"
        case .raiffeisen: return "building.2.fill"
        case .gazprombank: return "building.2.fill"
        case .otkritie: return "building.2.fill"
        case .rosbank: return "building.2.fill"
        case .other: return "building.2.fill"
        }
    }
}

/// Банковская карта
@Model
final class Card: Persistable {
    /// Название карты (например, "Основная карта")
    var name: String = ""
    
    /// Номер карты (последние 4 цифры для отображения, поле опционально)
    var cardNumber: String = "" // Храним последние 4 цифры, может быть пустым
    
    /// Полный номер карты (зашифрован, опционально)
    var encryptedFullNumber: Data?
    
    /// Банк
    var bankRaw: String = "other"
    
    /// Тип карты
    var cardTypeRaw: String = "debit"
    
    /// Приоритет карты
    var priorityRaw: String = "normal"
    
    /// Валюта карты
    var currency: String = "RUB" // Код валюты (USD, EUR, RUB и т.д.)
    
    /// Баланс на карте
    var balance: Double = 0.0

    /// Изначальный баланс для истории (не меняется при редактировании)
    var initialBalance: Double = 0.0

    /// Флаг, что initialBalance установлен
    var hasInitialBalance: Bool = false
    
    /// Кредитный лимит (только для кредитных карт)
    var creditLimit: Double?
    
    /// Дата окончания действия (MM/YY)
    var expiryDate: String?
    
    /// CVV (зашифрован, опционально)
    var encryptedCVV: Data?
    
    /// Имя держателя карты
    var cardholderName: String?
    
    /// Цвет карты (для визуализации)
    var cardColor: String? // Hex цвет или название
    
    /// Избранная карта
    var isFavorite: Bool = false
    
    /// Учитывать в общих финансах
    var includeInTotal: Bool = true
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    /// Дата архивирования (nil = активная карта)
    var archivedAt: Date?

    /// Стабильный идентификатор для связей между сущностями
    var uniqueID: String = ""
    
    var bank: Bank {
        get { Bank(rawValue: bankRaw) ?? .other }
        set { bankRaw = newValue.rawValue }
    }
    
    var cardType: CardType {
        get { CardType(rawValue: cardTypeRaw) ?? .debit }
        set { cardTypeRaw = newValue.rawValue }
    }
    
    var priority: CardPriority {
        get { CardPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }
    
    /// Маскированный номер карты для отображения (только последние 4 цифры)
    var maskedNumber: String {
        String(cardNumber.suffix(4))
    }
    
    /// Форматированный баланс
    var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }
    
    /// Долг по кредитной карте (лимит - баланс)
    var debt: Double {
        guard cardType == .credit, let limit = creditLimit else {
            return 0.0
        }
        return max(0, limit - balance)
    }
    
    /// Доступный кредитный лимит (лимит - использовано)
    var availableCredit: Double {
        guard cardType == .credit, let limit = creditLimit else {
            return 0.0
        }
        return max(0, limit - balance)
    }
    
    init(
        name: String,
        cardNumber: String,
        bank: Bank = .other,
        cardType: CardType = .debit,
        priority: CardPriority = .normal,
        currency: String = "RUB",
        balance: Double = 0.0,
        creditLimit: Double? = nil,
        expiryDate: String? = nil,
        cardholderName: String? = nil,
        cardColor: String? = nil,
        isFavorite: Bool = false,
        includeInTotal: Bool = true
    ) {
        self.name = name
        self.cardNumber = cardNumber
        self.bankRaw = bank.rawValue
        self.cardTypeRaw = cardType.rawValue
        self.priorityRaw = priority.rawValue
        self.currency = currency
        self.balance = balance
        self.initialBalance = balance
        self.hasInitialBalance = true
        self.creditLimit = creditLimit
        self.expiryDate = expiryDate
        self.cardholderName = cardholderName
        self.cardColor = cardColor
        self.isFavorite = isFavorite
        self.includeInTotal = includeInTotal
        self.createdAt = Date()
        self.updatedAt = Date()
        self.uniqueID = UUID().uuidString
    }
    
    // MARK: - Exportable
    
    /// Уникальный идентификатор карты для восстановления связей при restore
    var cardUniqueID: String {
        uniqueID.isEmpty ? legacyCardUniqueID() : uniqueID
    }

    private func legacyCardUniqueID() -> String {
        "\(name)|\(cardNumber)|\(bankRaw)|\(cardTypeRaw)|\(currency)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "Card",
            "name": name,
            "cardNumber": cardNumber,
            "bankRaw": bankRaw,
            "cardTypeRaw": cardTypeRaw,
            "priorityRaw": priorityRaw,
            "currency": currency,
            "balance": balance,
            "initialBalance": initialBalance,
            "hasInitialBalance": hasInitialBalance,
            "creditLimit": creditLimit ?? NSNull(),
            "expiryDate": expiryDate ?? NSNull(),
            "cardholderName": cardholderName ?? NSNull(),
            "cardColor": cardColor ?? NSNull(),
            "isFavorite": isFavorite,
            "includeInTotal": includeInTotal,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "cardUniqueID": cardUniqueID // Сохраняем уникальный ID для восстановления связей
        ]
        
        if let archivedAt = archivedAt {
            dict["archivedAt"] = archivedAt.timeIntervalSince1970
        }
        
        // Экспортируем зашифрованные данные, если есть
        if let encryptedFullNumber = encryptedFullNumber {
            dict["encryptedFullNumber"] = encryptedFullNumber.base64EncodedString()
        }
        if let encryptedCVV = encryptedCVV {
            dict["encryptedCVV"] = encryptedCVV.base64EncodedString()
        }
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["cardNumber"] as? String != nil,
              dict["bankRaw"] as? String != nil,
              dict["cardTypeRaw"] as? String != nil,
              dict["currency"] as? String != nil,
              dict["balance"] as? Double != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
}
