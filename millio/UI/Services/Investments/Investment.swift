//
//  Investment.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Тип инвестиции
enum InvestmentType: String, Codable, CaseIterable {
    case positive = "positive" // Плюсовая
    case negative = "negative" // Минусовая
    
    var displayName: String {
        switch self {
        case .positive: return "Плюсовая"
        case .negative: return "Минусовая"
        }
    }
    
    var icon: String {
        switch self {
        case .positive: return "arrow.up.circle.fill"
        case .negative: return "arrow.down.circle.fill"
        }
    }
}

/// Категория инвестиции
enum InvestmentCategory: String, Codable, CaseIterable {
    case car = "car" // Машина
    case house = "house" // Дом/Недвижимость
    case stocks = "stocks" // Акции
    case business = "business" // Бизнес
    case crypto = "crypto" // Криптовалюта
    case bonds = "bonds" // Облигации
    case metals = "metals" // Драгоценные металлы
    case other = "other" // Другое
    
    var displayName: String {
        switch self {
        case .car: return "Машина"
        case .house: return "Недвижимость"
        case .stocks: return "Акции"
        case .business: return "Бизнес"
        case .crypto: return "Криптовалюта"
        case .bonds: return "Облигации"
        case .metals: return "Драгоценные металлы"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .car: return "car.fill"
        case .house: return "house.fill"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .business: return "building.2.fill"
        case .crypto: return "bitcoinsign.circle.fill"
        case .bonds: return "doc.text.fill"
        case .metals: return "diamond.fill"
        case .other: return "star.fill"
        }
    }
}

/// Приоритет инвестиции
enum InvestmentPriority: String, Codable, CaseIterable {
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

/// Инвестиция
@Model
final class Investment: Persistable {
    /// Название инвестиции
    var name: String = ""
    
    /// Тип инвестиции
    var investmentTypeRaw: String = "positive"
    
    /// Категория инвестиции
    var categoryRaw: String = "other"
    
    /// Стоимость/сумма инвестиции
    var amount: Double = 0.0

    /// Изначальная сумма для истории (не меняется при редактировании)
    var initialAmount: Double = 0.0

    /// Флаг, что initialAmount установлен
    var hasInitialAmount: Bool = false
    
    /// Валюта
    var currency: String = "RUB"
    
    /// Учитывать в общих финансах
    var includeInTotal: Bool = true
    
    /// Приоритет
    var priorityRaw: String = "normal"
    
    /// Избранная инвестиция
    var isFavorite: Bool = false
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()

    /// Стабильный идентификатор для связей между сущностями
    var uniqueID: String = ""
    
    var investmentType: InvestmentType {
        get { InvestmentType(rawValue: investmentTypeRaw) ?? .positive }
        set { investmentTypeRaw = newValue.rawValue }
    }
    
    var category: InvestmentCategory {
        get { InvestmentCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    
    var priority: InvestmentPriority {
        get { InvestmentPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }
    
    init(
        name: String,
        investmentType: InvestmentType = .positive,
        category: InvestmentCategory = .other,
        amount: Double,
        currency: String = "RUB",
        includeInTotal: Bool = true,
        priority: InvestmentPriority = .normal,
        isFavorite: Bool = false
    ) {
        self.name = name
        self.investmentTypeRaw = investmentType.rawValue
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.initialAmount = amount
        self.hasInitialAmount = true
        self.currency = currency
        self.includeInTotal = includeInTotal
        self.priorityRaw = priority.rawValue
        self.isFavorite = isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
        self.uniqueID = UUID().uuidString
    }
    
    // MARK: - Exportable
    
    /// Уникальный идентификатор инвестиции для восстановления связей при restore
    var investmentUniqueID: String {
        if uniqueID.isEmpty {
            uniqueID = legacyInvestmentUniqueID()
        }
        return uniqueID
    }

    private func legacyInvestmentUniqueID() -> String {
        "\(name)|\(investmentTypeRaw)|\(categoryRaw)|\(amount)|\(currency)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "Investment",
            "name": name,
            "investmentTypeRaw": investmentTypeRaw,
            "categoryRaw": categoryRaw,
            "amount": amount,
            "initialAmount": initialAmount,
            "hasInitialAmount": hasInitialAmount,
            "currency": currency,
            "includeInTotal": includeInTotal,
            "priorityRaw": priorityRaw,
            "isFavorite": isFavorite,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "investmentUniqueID": investmentUniqueID
        ]
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["investmentTypeRaw"] as? String != nil,
              dict["categoryRaw"] as? String != nil,
              dict["amount"] as? Double != nil,
              dict["currency"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "Investment" &&
        dict["name"] as? String != nil &&
        dict["investmentTypeRaw"] as? String != nil &&
        dict["categoryRaw"] as? String != nil &&
        dict["amount"] as? Double != nil &&
        dict["currency"] as? String != nil
    }
}
