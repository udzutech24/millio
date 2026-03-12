//
//  CashflowTransaction.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

// MARK: - Transaction Type

enum CashflowTransactionType: String, Codable, CaseIterable {
    case income = "income"      // Доход
    case expense = "expense"    // Расход
    case transfer = "transfer"  // Перевод
    case balanceAdjustment = "balance_adjustment"  // Ручное изменение баланса
    case cardBalanceAdjustment = "card_balance_adjustment" // Корректировка баланса карты
    case creditDebtAdjustment = "credit_debt_adjustment"   // Корректировка долга

    static var allCases: [CashflowTransactionType] {
        // Пользовательские типы для ручного создания операций
        [.income, .expense, .transfer]
    }

    var displayName: String {
        switch self {
        case .income: return String(localized: "Income")
        case .expense: return String(localized: "Expense")
        case .transfer: return String(localized: "Transfer")
        case .balanceAdjustment: return String(localized: "Asset value adjustment")
        case .cardBalanceAdjustment: return String(localized: "Account balance adjustment")
        case .creditDebtAdjustment: return String(localized: "Debt adjustment")
        }
    }
    
    var icon: String {
        switch self {
        case .income: return "arrow.down.circle.fill"
        case .expense: return "arrow.up.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        case .balanceAdjustment: return "pencil.circle.fill"
        case .cardBalanceAdjustment: return "creditcard.circle.fill"
        case .creditDebtAdjustment: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Recurrence Rule

enum CashflowRecurrenceRule: String, Codable, CaseIterable {
    case none = "none"
    case monthly = "monthly"

    var displayName: String {
        switch self {
        case .none: return String(localized: "Do not repeat")
        case .monthly: return String(localized: "Monthly")
        }
    }
}

// MARK: - Income Category

enum IncomeCategory: String, Codable, CaseIterable {
    case salary = "salary"           // Зарплата
    case freelance = "freelance"     // Фриланс
    case business = "business"       // Бизнес
    case investment = "investment"   // Инвестиции
    case rental = "rental"           // Аренда
    case gift = "gift"               // Подарок
    case bonus = "bonus"             // Премия
    case other = "other"             // Другое
    
    var displayName: String {
        switch self {
        case .salary: return String(localized: "Salary")
        case .freelance: return String(localized: "Freelance")
        case .business: return String(localized: "Business")
        case .investment: return String(localized: "Investments")
        case .rental: return String(localized: "Rental")
        case .gift: return String(localized: "Gift")
        case .bonus: return String(localized: "Bonus")
        case .other: return String(localized: "Other")
        }
    }
    
    var icon: String {
        switch self {
        case .salary: return "💼"
        case .freelance: return "🧑‍💻"
        case .business: return "🏢"
        case .investment: return "📈"
        case .rental: return "🏠"
        case .gift: return "🎁"
        case .bonus: return "⭐️"
        case .other: return "🧩"
        }
    }
}

// MARK: - Expense Category

enum ExpenseCategory: String, Codable, CaseIterable {
    case groceries = "groceries"     // Продукты
    case cafe = "cafe"               // Кафе
    case transport = "transport"     // Транспорт
    case shopping = "shopping"       // Покупки
    case entertainment = "entertainment" // Развлечения
    case bills = "bills"             // Счета
    case health = "health"            // Здоровье
    case education = "education"     // Образование
    case other = "other"             // Другое
    
    var displayName: String {
        switch self {
        case .groceries: return String(localized: "Groceries")
        case .cafe: return String(localized: "Cafe")
        case .transport: return String(localized: "Transport")
        case .shopping: return String(localized: "Shopping")
        case .entertainment: return String(localized: "Entertainment")
        case .bills: return String(localized: "Bills")
        case .health: return String(localized: "Health")
        case .education: return String(localized: "Education")
        case .other: return String(localized: "Other")
        }
    }
    
    var icon: String {
        switch self {
        case .groceries: return "🛒"
        case .cafe: return "☕️"
        case .transport: return "🚕"
        case .shopping: return "🛍️"
        case .entertainment: return "🎮"
        case .bills: return "🧾"
        case .health: return "💊"
        case .education: return "📚"
        case .other: return "🧩"
        }
    }
}

// MARK: - Custom Category

enum CashflowCategoryKind: String, Codable, CaseIterable {
    case income = "income"
    case expense = "expense"
}

@Model
final class CashflowSystemCategoryOverride: Persistable {
    var overrideID: String = UUID().uuidString
    var kindRaw: String = CashflowCategoryKind.expense.rawValue
    var categoryRaw: String = ""
    var name: String = ""
    var normalizedName: String = ""
    var icon: String = CashflowCustomCategory.defaultIcon
    var isHidden: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: CashflowCategoryKind {
        get { CashflowCategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(
        kind: CashflowCategoryKind,
        categoryRaw: String,
        name: String,
        icon: String,
        isHidden: Bool = false
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.overrideID = UUID().uuidString
        self.kindRaw = kind.rawValue
        self.categoryRaw = categoryRaw
        self.name = trimmedName
        self.normalizedName = CashflowCustomCategory.normalize(trimmedName)
        self.icon = CashflowCustomCategory.normalizeIcon(icon)
        self.isHidden = isHidden
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "CashflowSystemCategoryOverride",
            "overrideID": overrideID,
            "kindRaw": kindRaw,
            "categoryRaw": categoryRaw,
            "name": name,
            "normalizedName": normalizedName,
            "icon": icon,
            "isHidden": isHidden,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["overrideID"] as? String != nil,
              dict["kindRaw"] as? String != nil,
              dict["categoryRaw"] as? String != nil,
              dict["name"] as? String != nil,
              dict["icon"] as? String != nil,
              dict["isHidden"] as? Bool != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}

@Model
final class CashflowCustomCategory: Persistable {
    static let defaultIcon = "🧩"
    static let allowedSFSymbolIcons: [String] = [
        "tag.fill",
        "cart.fill",
        "cup.and.saucer.fill",
        "fuelpump.fill",
        "fork.knife",
        "cross.case.fill",
        "car.fill",
        "gamecontroller.fill",
        "globe",
        "house.fill",
        "figure.walk",
        "gift.fill",
        "airplane",
        "iphone",
        "bolt.fill",
        "heart.fill",
        "basket.fill",
        "takeoutbag.and.cup.and.straw.fill",
        "wineglass.fill",
        "fork.knife.circle.fill",
        "birthday.cake.fill",
        "popcorn.fill",
        "ticket.fill",
        "film.fill",
        "tv.fill",
        "music.note",
        "music.mic",
        "headphones",
        "book.fill",
        "graduationcap.fill",
        "gamecontroller",
        "soccerball",
        "dumbbell.fill",
        "figure.run",
        "tent.fill",
        "beach.umbrella.fill",
        "mountain.2.fill",
        "camera.fill",
        "photo.fill",
        "paintpalette.fill",
        "theatermasks.fill",
        "stethoscope",
        "pills.fill",
        "bandage.fill",
        "cross.vial.fill",
        "pawprint.fill",
        "dog.fill",
        "cat.fill",
        "leaf.fill",
        "tree.fill",
        "car.2.fill",
        "bus.fill",
        "tram.fill",
        "ferry.fill",
        "bicycle",
        "scooter",
        "airplane.departure",
        "bed.double.fill",
        "shippingbox.fill",
        "cube.box.fill",
        "bag.fill",
        "creditcard.fill",
        "banknote.fill",
        "building.columns.fill",
        "dollarsign.circle.fill",
        "eurosign.circle.fill",
        "rublesign.circle.fill",
        "chart.line.uptrend.xyaxis",
        "briefcase.fill",
        "building.2.fill",
        "desktopcomputer",
        "laptopcomputer",
        "display",
        "keyboard.fill",
        "printer.fill",
        "wifi",
        "antenna.radiowaves.left.and.right",
        "phone.fill",
        "message.fill",
        "envelope.fill",
        "doc.text.fill",
        "newspaper.fill",
        "calendar",
        "clock.fill",
        "sparkles",
        "sun.max.fill",
        "moon.fill",
        "cloud.fill",
        "umbrella.fill",
        "snowflake",
        "flame.fill",
        "drop.fill",
        "bolt.circle.fill",
        "shield.fill",
        "lock.fill",
        "person.fill",
        "person.2.fill",
        "person.3.fill",
        "child.fill",
        "figure.2.and.child.holdinghands",
        "house.lodge.fill",
        "key.fill",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "scissors",
        "sewingneedle",
        "basketball.fill",
        "volleyball.fill",
        "baseball.fill",
        "trophy.fill",
        "medal.fill",
        "flag.checkered",
        "location.fill",
        "map.fill",
        "signpost.right.fill",
        "carrot.fill",
        "fish.fill",
        "takeoutbag.and.cup.and.straw",
        "cup.and.heat.waves.fill",
        "lanyardcard.fill",
        "comb.fill",
        "facemask.fill"
    ]
    static let allowedEmojiIcons: [String] = [
        "🛒", "🛍️", "🏪", "🏬", "🧺", "🍽️", "🍔", "🍕", "🍣", "🍜",
        "☕️", "🍰", "🍩", "🍿", "🎬", "🎮", "🎯", "🎟️", "🎨", "🎵",
        "🎧", "📚", "🧠", "💊", "🩺", "🏥", "🚕", "🚗", "🚌", "🚇",
        "🚲", "🛴", "⛽️", "✈️", "🏨", "🧳", "💼", "🖥️", "💻", "📱",
        "⌚️", "📞", "📶", "🌐", "🛜", "🔌", "💡", "🏠", "🔑", "🛠️",
        "🧰", "🧹", "🧴", "👕", "👟", "💄", "💇", "💆", "🧸",
        "🍼", "🐶", "🐱", "🐾", "🌿", "🌸", "🌳", "🔥", "💧", "☀️",
        "🌙", "🌧️", "❄️", "⚡️", "🧾", "📰", "📦", "🚚", "💳", "💰",
        "🪙", "🏦", "📈", "📊", "🧯", "🛡️", "🔒", "❤️", "🧡", "💜",
        "⭐️", "✨", "🎁", "🏆", "🏅", "⚽️", "🏀", "🏋️", "🧘", "🧑‍💻"
    ]
    static let allowedIcons: [String] = allowedSFSymbolIcons + allowedEmojiIcons

    static func isSFSymbolIcon(_ icon: String) -> Bool {
        allowedSFSymbolIcons.contains(icon)
    }

    static func normalizeIcon(_ icon: String) -> String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowedIcons.contains(trimmed) ? trimmed : defaultIcon
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var categoryID: String = UUID().uuidString
    var kindRaw: String = CashflowCategoryKind.expense.rawValue
    var name: String = ""
    var normalizedName: String = ""
    var icon: String = defaultIcon
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: CashflowCategoryKind {
        get { CashflowCategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(
        kind: CashflowCategoryKind,
        name: String,
        icon: String = CashflowCustomCategory.defaultIcon
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryID = UUID().uuidString
        self.kindRaw = kind.rawValue
        self.name = trimmed
        self.normalizedName = Self.normalize(trimmed)
        self.icon = Self.normalizeIcon(icon)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "CashflowCustomCategory",
            "categoryID": categoryID,
            "kindRaw": kindRaw,
            "name": name,
            "normalizedName": normalizedName,
            "icon": icon,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["categoryID"] as? String != nil,
              dict["kindRaw"] as? String != nil,
              dict["name"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}

struct CashflowCategoryOption: Identifiable, Hashable {
    let rawValue: String
    let displayName: String
    let icon: String
    let isCustom: Bool

    var id: String { rawValue }
}

// MARK: - Cashflow Transaction

@Model
final class CashflowTransaction: Persistable {
    static let customCategoryPrefix = "custom:"

    /// Тип транзакции
    var transactionTypeRaw: String = "expense"
    
    /// Категория дохода (если тип = income)
    var incomeCategoryRaw: String?
    
    /// Категория расхода (если тип = expense)
    var expenseCategoryRaw: String?
    
    /// Сумма транзакции
    var amount: Double = 0.0
    
    /// Валюта
    var currency: String = "RUB"

    /// Зафиксированный курс для истории (transaction.currency -> exchangeRateCurrency)
    var exchangeRate: Double?

    /// Дата курса (дневная гранулярность)
    var exchangeRateDate: Date?

    /// Валюта, к которой применяется exchangeRate
    var exchangeRateCurrency: String?
    
    /// Дата транзакции
    var transactionDate: Date = Date()
    
    /// ID карты для дохода/расхода (или карты-источника для перевода)
    var cardID: String?
    
    /// ID карты-получателя для перевода
    var toCardID: String?
    
    /// ID кредита (для транзакций связанных с кредитами)
    var creditID: String?
    
    /// ID инвестиции (для транзакций связанных с инвестициями)
    var investmentID: String?
    
    /// Описание/комментарий
    var note: String?

    /// Источник пакетного импорта для идемпотентного обновления импортных наборов.
    var importSourceRaw: String?

    /// Уникальный ключ импортной записи внутри её источника.
    var importReferenceKey: String?

    /// Правило автоповтора (none/monthly)
    var recurrenceRuleRaw: String = CashflowRecurrenceRule.none.rawValue

    /// ID серии автоповтора (общий для всех операций серии)
    var recurrenceSeriesID: String?

    /// Влияет ли операция на текущий остаток карты
    var affectsCardBalance: Bool = true
    
    /// Дата создания записи
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    var transactionType: CashflowTransactionType {
        get { CashflowTransactionType(rawValue: transactionTypeRaw) ?? .expense }
        set { transactionTypeRaw = newValue.rawValue }
    }
    
    var incomeCategory: IncomeCategory? {
        get {
            guard let raw = incomeCategoryRaw else { return nil }
            return IncomeCategory(rawValue: raw)
        }
        set { incomeCategoryRaw = newValue?.rawValue }
    }
    
    var expenseCategory: ExpenseCategory? {
        get {
            guard let raw = expenseCategoryRaw else { return nil }
            return ExpenseCategory(rawValue: raw)
        }
        set { expenseCategoryRaw = newValue?.rawValue }
    }

    var recurrenceRule: CashflowRecurrenceRule {
        get { CashflowRecurrenceRule(rawValue: recurrenceRuleRaw) ?? .none }
        set { recurrenceRuleRaw = newValue.rawValue }
    }

    var isRecurringTemplate: Bool {
        recurrenceRule != .none
        && (transactionType == .income || transactionType == .expense)
        && recurrenceSeriesID != nil
    }
    
    init(
        transactionType: CashflowTransactionType,
        amount: Double,
        currency: String,
        transactionDate: Date,
        cardID: String? = nil,
        toCardID: String? = nil,
        creditID: String? = nil,
        investmentID: String? = nil,
        incomeCategory: IncomeCategory? = nil,
        expenseCategory: ExpenseCategory? = nil,
        incomeCategoryRaw: String? = nil,
        expenseCategoryRaw: String? = nil,
        note: String? = nil,
        importSourceRaw: String? = nil,
        importReferenceKey: String? = nil,
        recurrenceRule: CashflowRecurrenceRule = .none,
        recurrenceSeriesID: String? = nil,
        affectsCardBalance: Bool = true
    ) {
        self.transactionTypeRaw = transactionType.rawValue
        self.amount = amount
        self.currency = currency
        self.transactionDate = transactionDate
        self.cardID = cardID
        self.toCardID = toCardID
        self.creditID = creditID
        self.investmentID = investmentID
        self.incomeCategoryRaw = incomeCategoryRaw ?? incomeCategory?.rawValue
        self.expenseCategoryRaw = expenseCategoryRaw ?? expenseCategory?.rawValue
        self.note = note
        self.importSourceRaw = importSourceRaw
        self.importReferenceKey = importReferenceKey
        self.recurrenceRuleRaw = recurrenceRule.rawValue
        self.recurrenceSeriesID = recurrenceSeriesID
        self.affectsCardBalance = affectsCardBalance
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    var transactionUniqueID: String {
        "\(transactionTypeRaw)|\(transactionDate.timeIntervalSince1970)|\(amount)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "CashflowTransaction",
            "transactionTypeRaw": transactionTypeRaw,
            "amount": amount,
            "currency": currency,
            "transactionDate": transactionDate.timeIntervalSince1970,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "transactionUniqueID": transactionUniqueID
        ]
        
        if let incomeCategoryRaw = incomeCategoryRaw {
            dict["incomeCategoryRaw"] = incomeCategoryRaw
        }
        if let expenseCategoryRaw = expenseCategoryRaw {
            dict["expenseCategoryRaw"] = expenseCategoryRaw
        }
        if let cardID = cardID {
            dict["cardID"] = cardID
        }
        if let toCardID = toCardID {
            dict["toCardID"] = toCardID
        }
        if let creditID = creditID {
            dict["creditID"] = creditID
        }
        if let investmentID = investmentID {
            dict["investmentID"] = investmentID
        }
        if let note = note {
            dict["note"] = note
        }
        if let importSourceRaw = importSourceRaw {
            dict["importSourceRaw"] = importSourceRaw
        }
        if let importReferenceKey = importReferenceKey {
            dict["importReferenceKey"] = importReferenceKey
        }
        if let exchangeRate = exchangeRate {
            dict["exchangeRate"] = exchangeRate
        }
        if let exchangeRateDate = exchangeRateDate {
            dict["exchangeRateDate"] = exchangeRateDate.timeIntervalSince1970
        }
        if let exchangeRateCurrency = exchangeRateCurrency {
            dict["exchangeRateCurrency"] = exchangeRateCurrency
        }
        if recurrenceRule != .none {
            dict["recurrenceRuleRaw"] = recurrenceRuleRaw
        }
        if let recurrenceSeriesID = recurrenceSeriesID {
            dict["recurrenceSeriesID"] = recurrenceSeriesID
        }
        if !affectsCardBalance {
            dict["affectsCardBalance"] = false
        }
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "CashflowTransaction"
    }
}
