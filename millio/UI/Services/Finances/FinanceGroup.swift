//
//  FinanceGroup.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData
import SwiftUI

/// Группа финансовых счетов
@Model
final class FinanceGroup: Persistable {
    /// Название группы
    var name: String = ""
    
    /// Цвет группы (hex строка, например "#FF5733")
    var colorHex: String = "#FFFFFF"
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    /// Порядок сортировки
    var order: Int = 0

    /// Включен ли для счетов внутри группы ручной порядок
    var usesManualAccountOrdering: Bool = false
    
    /// Избранная группа
    var isFavorite: Bool = false
    
    /// Приоритет группы
    var priorityRaw: String = "normal"
    
    /// Валюта отображения суммы группы (nil = использовать общую валюту)
    var displayCurrency: String? = nil
    
    var priority: GroupPriority {
        get { GroupPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }
    
    /// Связанные счета
    @Relationship(deleteRule: .nullify) var accounts: [FinanceAccount]? = nil
    
    var color: Color {
        Color(hex: colorHex)
    }
    
    init(name: String, colorHex: String = "#FFFFFF", order: Int = 0, isFavorite: Bool = false, priority: GroupPriority = .normal) {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = Date()
        self.updatedAt = Date()
        self.order = order
        self.isFavorite = isFavorite
        self.priorityRaw = priority.rawValue
    }
    
    // MARK: - Exportable
    
    var groupUniqueID: String {
        "\(name)|\(colorHex)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "FinanceGroup",
            "name": name,
            "colorHex": colorHex,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "order": order,
            "usesManualAccountOrdering": usesManualAccountOrdering,
            "isFavorite": isFavorite,
            "priorityRaw": priorityRaw,
            "groupUniqueID": groupUniqueID
        ]
        if let displayCurrency = displayCurrency {
            dict["displayCurrency"] = displayCurrency
        }
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["colorHex"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "FinanceGroup" &&
        dict["name"] as? String != nil &&
        dict["colorHex"] as? String != nil
    }
}

// MARK: - Color Extension

extension Color {
    func toHex() -> String {
        let uic = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uic.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let rgb: Int = (Int)(red*255)<<16 | (Int)(green*255)<<8 | (Int)(blue*255)<<0
        
        return String(format: "#%06x", rgb)
    }
}
