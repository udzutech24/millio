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
        case .income: return "Доход"
        case .expense: return "Расход"
        case .transfer: return "Перевод"
        case .balanceAdjustment: return "Изменение стоимости актива"
        case .cardBalanceAdjustment: return "Корректировка баланса счета"
        case .creditDebtAdjustment: return "Корректировка долга"
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
        case .none: return "Не повторять"
        case .monthly: return "Ежемесячно"
        }
    }
}

// MARK: - Income Category

enum IncomeCategory: String, Codable, CaseIterable {
    case salary = "salary"           // Зарплата
    case freelance = "freelance"     // Фриланс
    case investment = "investment"   // Инвестиции
    case gift = "gift"               // Подарок
    case bonus = "bonus"             // Премия
    case other = "other"             // Другое
    
    var displayName: String {
        switch self {
        case .salary: return "Зарплата"
        case .freelance: return "Фриланс"
        case .investment: return "Инвестиции"
        case .gift: return "Подарок"
        case .bonus: return "Премия"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .salary: return "briefcase.fill"
        case .freelance: return "laptopcomputer"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .gift: return "gift.fill"
        case .bonus: return "star.fill"
        case .other: return "ellipsis.circle.fill"
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
        case .groceries: return "Продукты"
        case .cafe: return "Кафе"
        case .transport: return "Транспорт"
        case .shopping: return "Покупки"
        case .entertainment: return "Развлечения"
        case .bills: return "Счета"
        case .health: return "Здоровье"
        case .education: return "Образование"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .groceries: return "cart.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "tv.fill"
        case .bills: return "doc.text.fill"
        case .health: return "cross.case.fill"
        case .education: return "book.fill"
        case .other: return "ellipsis.circle.fill"
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
    static let defaultIcon = "tag.fill"
    static let allowedIcons: [String] = [
        "tag.fill",
        "briefcase.fill",
        "laptopcomputer",
        "chart.line.uptrend.xyaxis",
        "gift.fill",
        "star.fill",
        "cart.fill",
        "cup.and.saucer.fill",
        "car.fill",
        "bag.fill",
        "tv.fill",
        "doc.text.fill",
        "cross.case.fill",
        "book.fill",
        "house.fill",
        "airplane",
        "figure.walk",
        "bolt.fill"
    ]

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

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizeIcon(_ icon: String) -> String {
        allowedIcons.contains(icon) ? icon : defaultIcon
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

    /// Правило автоповтора (none/monthly)
    var recurrenceRuleRaw: String = CashflowRecurrenceRule.none.rawValue

    /// ID серии автоповтора (общий для всех операций серии)
    var recurrenceSeriesID: String?
    
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
        recurrenceRule: CashflowRecurrenceRule = .none,
        recurrenceSeriesID: String? = nil
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
        self.recurrenceRuleRaw = recurrenceRule.rawValue
        self.recurrenceSeriesID = recurrenceSeriesID
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
