//
//  PlannedExpense.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Категория планируемого расхода
enum PlannedExpenseCategory: String, Codable, CaseIterable {
    case insurance = "insurance" // Страховка
    case taxes = "taxes" // Налоги
    case subscription = "subscription" // Подписки
    case utilities = "utilities" // Коммунальные услуги
    case rent = "rent" // Аренда
    case education = "education" // Образование
    case healthcare = "healthcare" // Здравоохранение
    case other = "other" // Другое
    
    var displayName: String {
        switch self {
        case .insurance: return "Страховка"
        case .taxes: return "Налоги"
        case .subscription: return "Подписки"
        case .utilities: return "Коммунальные"
        case .rent: return "Аренда"
        case .education: return "Образование"
        case .healthcare: return "Здравоохранение"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .insurance: return "shield.fill"
        case .taxes: return "doc.text.fill"
        case .subscription: return "star.fill"
        case .utilities: return "bolt.fill"
        case .rent: return "house.fill"
        case .education: return "book.fill"
        case .healthcare: return "cross.case.fill"
        case .other: return "tag.fill"
        }
    }
}

/// Приоритет планируемого расхода
enum PlannedExpensePriority: String, Codable, CaseIterable {
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

/// Планируемый расход
@Model
final class PlannedExpense: Persistable {
    /// Название расхода
    var name: String = ""
    
    /// Сумма расхода
    var amount: Double = 0.0
    
    /// Валюта
    var currency: String = "RUB"
    
    /// Дата планируемого платежа
    var plannedDate: Date = Date()
    
    /// Категория
    var categoryRaw: String = "other"
    
    /// Приоритет
    var priorityRaw: String = "normal"
    
    /// Избранный расход
    var isFavorite: Bool = false
    
    /// Оплачен ли расход
    var isPaid: Bool = false
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    var category: PlannedExpenseCategory {
        get { PlannedExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    
    var priority: PlannedExpensePriority {
        get { PlannedExpensePriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }
    
    /// Просрочен ли планируемый расход
    var isOverdue: Bool {
        return Date() > plannedDate && !isPaid
    }
    
    /// Осталось дней до платежа
    var daysUntilPayment: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let planned = calendar.startOfDay(for: plannedDate)
        let components = calendar.dateComponents([.day], from: today, to: planned)
        return components.day ?? 0
    }
    
    init(
        name: String,
        amount: Double,
        currency: String = "RUB",
        plannedDate: Date,
        category: PlannedExpenseCategory = .other,
        priority: PlannedExpensePriority = .normal,
        isFavorite: Bool = false,
        isPaid: Bool = false
    ) {
        self.name = name
        self.amount = amount
        self.currency = currency
        self.plannedDate = plannedDate
        self.categoryRaw = category.rawValue
        self.priorityRaw = priority.rawValue
        self.isFavorite = isFavorite
        self.isPaid = isPaid
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    /// Уникальный идентификатор планируемого расхода для восстановления связей при restore
    var plannedExpenseUniqueID: String {
        "\(name)|\(amount)|\(currency)|\(plannedDate.timeIntervalSince1970)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "PlannedExpense",
            "name": name,
            "amount": amount,
            "currency": currency,
            "plannedDate": plannedDate.timeIntervalSince1970,
            "categoryRaw": categoryRaw,
            "priorityRaw": priorityRaw,
            "isFavorite": isFavorite,
            "isPaid": isPaid,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "plannedExpenseUniqueID": plannedExpenseUniqueID
        ]
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["amount"] as? Double != nil,
              dict["currency"] as? String != nil,
              dict["plannedDate"] as? TimeInterval != nil,
              dict["categoryRaw"] as? String != nil,
              dict["priorityRaw"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "PlannedExpense" &&
        dict["name"] as? String != nil &&
        dict["amount"] as? Double != nil &&
        dict["currency"] as? String != nil &&
        dict["plannedDate"] as? TimeInterval != nil &&
        dict["categoryRaw"] as? String != nil &&
        dict["priorityRaw"] as? String != nil
    }
}
