//
//  Debt.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Тип долга
enum DebtType: String, Codable, CaseIterable {
    case owedToMe = "owed_to_me" // Мне должны
    case iOwe = "i_owe" // Я должен
    
    var displayName: String {
        switch self {
        case .owedToMe: return "Мне должны"
        case .iOwe: return "Я должен"
        }
    }
    
    var icon: String {
        switch self {
        case .owedToMe: return "arrow.down.circle.fill"
        case .iOwe: return "arrow.up.circle.fill"
        }
    }
}

/// Приоритет долга
enum DebtPriority: String, Codable, CaseIterable {
    case low = "low" // Низкий
    case normal = "normal" // Обычный
    case high = "high" // Высокий
    
    var displayName: String {
        switch self {
        case .low: return "Низкий"
        case .normal: return "Обычный"
        case .high: return "Высокий"
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

/// Долг
@Model
final class Debt: Persistable {
    /// Название/описание долга
    var name: String = ""
    
    /// Тип долга
    var debtTypeRaw: String = "i_owe"
    
    /// Сумма долга
    var amount: Double = 0.0
    
    /// Валюта
    var currency: String = "RUB"
    
    /// Кому/от кого (имя контакта)
    var contactName: String = ""
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата погашения (опционально)
    var dueDate: Date?
    
    /// Приоритет
    var priorityRaw: String = "normal"
    
    /// Избранный долг
    var isFavorite: Bool = false
    
    /// Выплачен ли долг
    var isPaid: Bool = false
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    var debtType: DebtType {
        get { DebtType(rawValue: debtTypeRaw) ?? .iOwe }
        set { debtTypeRaw = newValue.rawValue }
    }
    
    var priority: DebtPriority {
        get { DebtPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }
    
    /// Просрочен ли долг
    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return Date() > dueDate
    }
    
    init(
        name: String,
        debtType: DebtType = .iOwe,
        amount: Double,
        currency: String = "RUB",
        contactName: String = "",
        dueDate: Date? = nil,
        priority: DebtPriority = .normal,
        isFavorite: Bool = false,
        isPaid: Bool = false
    ) {
        self.name = name
        self.debtTypeRaw = debtType.rawValue
        self.amount = amount
        self.currency = currency
        self.contactName = contactName
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
        self.isFavorite = isFavorite
        self.isPaid = isPaid
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    /// Уникальный идентификатор долга для восстановления связей при restore
    var debtUniqueID: String {
        "\(name)|\(debtTypeRaw)|\(amount)|\(currency)|\(contactName)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "Debt",
            "name": name,
            "debtTypeRaw": debtTypeRaw,
            "amount": amount,
            "currency": currency,
            "contactName": contactName,
            "priorityRaw": priorityRaw,
            "isFavorite": isFavorite,
            "isPaid": isPaid,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "debtUniqueID": debtUniqueID
        ]
        
        if let dueDate = dueDate {
            dict["dueDate"] = dueDate.timeIntervalSince1970
        } else {
            dict["dueDate"] = NSNull()
        }
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["debtTypeRaw"] as? String != nil,
              dict["amount"] as? Double != nil,
              dict["currency"] as? String != nil,
              dict["contactName"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "Debt" &&
        dict["name"] as? String != nil &&
        dict["debtTypeRaw"] as? String != nil &&
        dict["amount"] as? Double != nil &&
        dict["currency"] as? String != nil &&
        dict["contactName"] as? String != nil
    }
}
