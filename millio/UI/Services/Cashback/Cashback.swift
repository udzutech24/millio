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

/// Пользовательская категория кешбэка
@Model
final class CashbackCustomCategory: Persistable {
    /// Уникальный идентификатор категории
    var categoryID: String = UUID().uuidString

    /// Отображаемое имя
    var name: String = ""

    /// Нормализованное имя для дедупликации
    var normalizedName: String = ""

    /// Дата создания
    var createdAt: Date = Date()

    /// Дата обновления
    var updatedAt: Date = Date()

    init(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryID = UUID().uuidString
        self.name = trimmed
        self.normalizedName = CashbackCustomCategory.normalize(trimmed)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "CashbackCustomCategory",
            "categoryID": categoryID,
            "name": name,
            "normalizedName": normalizedName,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["categoryID"] as? String != nil,
              dict["name"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}

/// Унифицированная категория для UI (системная или пользовательская)
struct CashbackCategoryOption: Identifiable, Hashable {
    /// Стабильный raw-ключ для хранения в Cashback.categoryRaw
    let rawValue: String
    let displayName: String
    let icon: String
    let isCustom: Bool

    var id: String { rawValue }
}

/// Кешбэк
@Model
final class Cashback: Persistable {
    static let customCategoryPrefix = "custom:"

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

    /// Категория является пользовательской
    var isCustomCategory: Bool {
        categoryRaw.hasPrefix(Self.customCategoryPrefix)
    }

    /// Отображаемое имя категории (системное или пользовательское)
    var displayCategoryName: String {
        if let systemCategory = CashbackCategory(rawValue: categoryRaw) {
            return systemCategory.displayName
        }
        if isCustomCategory, !name.isEmpty {
            return name
        }
        return CashbackCategory.other.displayName
    }

    /// Отображаемая иконка категории (для пользовательской используем общий тег)
    var displayCategoryIcon: String {
        CashbackCategory(rawValue: categoryRaw)?.icon ?? "tag.fill"
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

    init(
        name: String,
        categoryRaw: String,
        percentage: Double = 0.0,
        cardIDs: [String] = []
    ) {
        self.name = name
        self.categoryRaw = categoryRaw
        self.percentage = percentage
        self.cardIDs = cardIDs
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "Cashback",
            "name": name,
            "categoryRaw": categoryRaw,
            "percentage": percentage,
            "cardIDs": cardIDs,
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
