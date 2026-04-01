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
        displayName(for: AppLocalization.currentAppLocale)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .positive: return AppLocalization.string("finances.investment.type.positive", locale: locale)
        case .negative: return AppLocalization.string("finances.investment.type.negative", locale: locale)
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
    case debt = "debt" // Долг
    case crypto = "crypto" // Криптовалюта
    case bonds = "bonds" // Облигации
    case metals = "metals" // Драгоценные металлы
    case other = "other" // Другое
    
    var displayName: String {
        displayName(for: AppLocalization.currentAppLocale)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .car: return AppLocalization.string("finances.investment.category.car", locale: locale)
        case .house: return AppLocalization.string("finances.investment.category.house", locale: locale)
        case .stocks: return AppLocalization.string("finances.investment.category.stocks", locale: locale)
        case .business: return AppLocalization.string("finances.investment.category.business", locale: locale)
        case .debt: return AppLocalization.string("finances.investment.category.debt", locale: locale)
        case .crypto: return AppLocalization.string("finances.investment.category.crypto", locale: locale)
        case .bonds: return AppLocalization.string("finances.investment.category.bonds", locale: locale)
        case .metals: return AppLocalization.string("finances.investment.category.metals", locale: locale)
        case .other: return AppLocalization.string("finances.investment.category.other", locale: locale)
        }
    }
    
    var icon: String {
        switch self {
        case .car: return "car.fill"
        case .house: return "house.fill"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .business: return "building.2.fill"
        case .debt: return "hand.raised.fill"
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

    /// Символ биржевого инструмента (например, AAPL, BTCUSD)
    var marketSymbol: String?

    /// Stable internal asset identity. Holdings should point here, not to provider symbols.
    var assetID: String?

    /// Биржа/площадка котировки (если доступно)
    var marketExchange: String?

    /// Канонический ключ инструмента для quote endpoint провайдера.
    var marketQuoteLookupKey: String?

    /// MIC-код площадки, если доступен из search API.
    var marketMICCode: String?

    /// Валюта котировки инструмента
    var marketCurrency: String?

    /// Количество инструмента в позиции
    var marketQuantity: Double?

    /// Последняя известная цена за единицу
    var lastKnownUnitPrice: Double?

    /// Средняя цена покупки за единицу (cost basis)
    var averagePurchaseUnitPrice: Double?

    /// Суммарная стоимость покупки текущей позиции (cost basis total)
    var totalPurchaseCost: Double?

    /// Дата/время последнего обновления цены
    var lastKnownPriceUpdatedAt: Date?

    /// Сырой идентификатор провайдера market-данных
    var marketProviderRaw: String?

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
    
    /// Дата архивирования (nil = активная инвестиция)
    var archivedAt: Date?

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

    /// Рыночно-оцениваемый актив (акции/криптовалюта)
    var isMarketPriced: Bool {
        category == .stocks || category == .crypto
    }

    /// Итог позиции = количество * цена за единицу
    var positionTotal: Double? {
        guard let quantity = marketQuantity,
              let unitPrice = lastKnownUnitPrice else {
            return nil
        }
        return quantity * unitPrice
    }

    /// Абсолютный прирост позиции относительно суммарной цены покупки.
    var positionGrowthAbsolute: Double? {
        guard let positionTotal,
              let purchaseCost = totalPurchaseCost,
              purchaseCost > 0 else {
            return nil
        }
        return positionTotal - purchaseCost
    }

    /// Прирост позиции в процентах относительно суммарной цены покупки.
    var positionGrowthPercent: Double? {
        guard let growth = positionGrowthAbsolute,
              let purchaseCost = totalPurchaseCost,
              purchaseCost > 0 else {
            return nil
        }
        return (growth / purchaseCost) * 100
    }

    /// Пересчитывает amount на основе рыночной позиции, если есть количество и цена.
    func recalculateAmountFromPosition() {
        if let total = positionTotal {
            amount = total
        }
    }

    /// Применяет операцию покупки и пересчитывает среднюю цену позиции.
    @discardableResult
    func applyBuy(quantity: Double, unitPrice: Double) -> Bool {
        guard quantity > 0, unitPrice >= 0 else {
            return false
        }

        let oldQuantity = marketQuantity ?? 0
        let oldCost = totalPurchaseCost ?? ((averagePurchaseUnitPrice ?? 0) * oldQuantity)
        let newQuantity = oldQuantity + quantity
        let newCost = oldCost + (quantity * unitPrice)

        marketQuantity = newQuantity
        totalPurchaseCost = newCost
        averagePurchaseUnitPrice = newQuantity > 0 ? (newCost / newQuantity) : nil
        lastKnownUnitPrice = unitPrice
        lastKnownPriceUpdatedAt = Date()
        recalculateAmountFromPosition()
        return true
    }

    /// Применяет операцию продажи с сохранением среднего cost basis для остатка.
    @discardableResult
    func applySell(quantity: Double, unitPrice: Double) -> Bool {
        guard quantity > 0, unitPrice >= 0 else {
            return false
        }

        let oldQuantity = marketQuantity ?? 0
        let epsilon = 0.0000001
        guard oldQuantity + epsilon >= quantity else {
            return false
        }

        let oldCost = totalPurchaseCost ?? ((averagePurchaseUnitPrice ?? 0) * oldQuantity)
        let avgCost = oldQuantity > 0 ? (oldCost / oldQuantity) : 0
        let newQuantityRaw = oldQuantity - quantity
        let newQuantity = newQuantityRaw > epsilon ? newQuantityRaw : 0
        let newCostRaw = oldCost - (avgCost * quantity)
        let newCost = max(0, newCostRaw)

        marketQuantity = newQuantity
        if newQuantity > 0 {
            totalPurchaseCost = newCost
            averagePurchaseUnitPrice = newCost / newQuantity
        } else {
            totalPurchaseCost = 0
            averagePurchaseUnitPrice = nil
        }

        lastKnownUnitPrice = unitPrice
        lastKnownPriceUpdatedAt = Date()
        recalculateAmountFromPosition()
        return true
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
        return uniqueID.isEmpty ? legacyInvestmentUniqueID() : uniqueID
    }
    
    /// Убедиться, что uniqueID установлен (миграция для старых данных)
    func ensureUniqueID() {
        if uniqueID.isEmpty {
            uniqueID = legacyInvestmentUniqueID()
        }
    }

    private func legacyInvestmentUniqueID() -> String {
        "\(name)|\(investmentTypeRaw)|\(categoryRaw)|\(amount)|\(currency)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        var dict: [String: Any] = [
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
        
        if let archivedAt = archivedAt {
            dict["archivedAt"] = archivedAt.timeIntervalSince1970
        }

        if let marketSymbol {
            dict["marketSymbol"] = marketSymbol
        }
        if let assetID {
            dict["assetID"] = assetID
        }
        if let marketExchange {
            dict["marketExchange"] = marketExchange
        }
        if let marketQuoteLookupKey {
            dict["marketQuoteLookupKey"] = marketQuoteLookupKey
        }
        if let marketMICCode {
            dict["marketMICCode"] = marketMICCode
        }
        if let marketCurrency {
            dict["marketCurrency"] = marketCurrency
        }
        if let marketQuantity {
            dict["marketQuantity"] = marketQuantity
        }
        if let lastKnownUnitPrice {
            dict["lastKnownUnitPrice"] = lastKnownUnitPrice
        }
        if let averagePurchaseUnitPrice {
            dict["averagePurchaseUnitPrice"] = averagePurchaseUnitPrice
        }
        if let totalPurchaseCost {
            dict["totalPurchaseCost"] = totalPurchaseCost
        }
        if let lastKnownPriceUpdatedAt {
            dict["lastKnownPriceUpdatedAt"] = lastKnownPriceUpdatedAt.timeIntervalSince1970
        }
        if let marketProviderRaw {
            dict["marketProviderRaw"] = marketProviderRaw
        }
        
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
