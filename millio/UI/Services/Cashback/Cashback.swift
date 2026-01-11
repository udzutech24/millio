//
//  Cashback.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Категория кешбэка
enum CashbackCategory: String, Codable, CaseIterable {
    case gasStation = "gas_station"
    case supermarket = "supermarket"
    case restaurant = "restaurant"
    case pharmacy = "pharmacy"
    case transport = "transport"
    case entertainment = "entertainment"
    case online = "online"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .gasStation: return "Заправки"
        case .supermarket: return "Супермаркеты"
        case .restaurant: return "Рестораны"
        case .pharmacy: return "Аптеки"
        case .transport: return "Транспорт"
        case .entertainment: return "Развлечения"
        case .online: return "Онлайн"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .gasStation: return "fuelpump.fill"
        case .supermarket: return "cart.fill"
        case .restaurant: return "fork.knife"
        case .pharmacy: return "cross.case.fill"
        case .transport: return "car.fill"
        case .entertainment: return "gamecontroller.fill"
        case .online: return "globe"
        case .other: return "tag.fill"
        }
    }
}

/// Кешбэк
@Model
final class Cashback: Persistable {
    /// Название кешбэка
    var name: String = ""
    
    /// Категория кешбэка
    var categoryRaw: String = "other"
    
    /// Процент кешбэка (0.0 - 100.0)
    var percentage: Double = 0.0
    
    /// ID привязанных карт - массив для поддержки нескольких карт
    var cardIDs: [String] = []
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    var category: CashbackCategory {
        get { CashbackCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    
    /// Форматированный процент для отображения
    var formattedPercentage: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: percentage)) ?? "0")%"
    }
    
    init(
        name: String,
        category: CashbackCategory = .other,
        percentage: Double = 0.0,
        cardIDs: [String] = []
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.percentage = percentage
        self.cardIDs = cardIDs
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    func export() throws -> Data {
        // Конвертируем persistentModelID в cardUniqueID для восстановления связей при restore
        // Для этого нужно получить карты из ModelContext
        // Но так как мы не имеем доступа к ModelContext здесь, сохраняем как есть
        // и конвертируем в DataRepository при экспорте
        let dict: [String: Any] = [
            "type": "Cashback",
            "name": name,
            "categoryRaw": categoryRaw,
            "percentage": percentage,
            "cardIDs": cardIDs, // Это persistentModelID, конвертируем в cardUniqueID в DataRepository
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["categoryRaw"] as? String != nil,
              dict["percentage"] as? Double != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
}
