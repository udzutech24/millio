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
    case exchange = "exchange"  // Обмен валют
    
    var displayName: String {
        switch self {
        case .income: return "Доход"
        case .expense: return "Расход"
        case .transfer: return "Перевод"
        case .exchange: return "Обмен"
        }
    }
    
    var icon: String {
        switch self {
        case .income: return "arrow.down.circle.fill"
        case .expense: return "arrow.up.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        case .exchange: return "arrow.triangle.2.circlepath.circle.fill"
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

// MARK: - Cashflow Transaction

@Model
final class CashflowTransaction: Persistable {
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
    
    /// Дата транзакции
    var transactionDate: Date = Date()
    
    /// ID карты для дохода/расхода (или карты-источника для перевода)
    var cardID: String?
    
    /// ID карты-получателя для перевода
    var toCardID: String?
    
    /// Валюта обмена "из" (для обмена валют)
    var exchangeFromCurrency: String?
    
    /// Валюта обмена "в" (для обмена валют)
    var exchangeToCurrency: String?
    
    /// Сумма обмена "из" (для обмена валют)
    var exchangeFromAmount: Double?
    
    /// Сумма обмена "в" (для обмена валют)
    var exchangeToAmount: Double?
    
    /// Описание/комментарий
    var note: String?
    
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
    
    init(
        transactionType: CashflowTransactionType,
        amount: Double,
        currency: String,
        transactionDate: Date,
        cardID: String? = nil,
        toCardID: String? = nil,
        incomeCategory: IncomeCategory? = nil,
        expenseCategory: ExpenseCategory? = nil,
        exchangeFromCurrency: String? = nil,
        exchangeToCurrency: String? = nil,
        exchangeFromAmount: Double? = nil,
        exchangeToAmount: Double? = nil,
        note: String? = nil
    ) {
        self.transactionTypeRaw = transactionType.rawValue
        self.amount = amount
        self.currency = currency
        self.transactionDate = transactionDate
        self.cardID = cardID
        self.toCardID = toCardID
        self.incomeCategoryRaw = incomeCategory?.rawValue
        self.expenseCategoryRaw = expenseCategory?.rawValue
        self.exchangeFromCurrency = exchangeFromCurrency
        self.exchangeToCurrency = exchangeToCurrency
        self.exchangeFromAmount = exchangeFromAmount
        self.exchangeToAmount = exchangeToAmount
        self.note = note
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
        if let exchangeFromCurrency = exchangeFromCurrency {
            dict["exchangeFromCurrency"] = exchangeFromCurrency
        }
        if let exchangeToCurrency = exchangeToCurrency {
            dict["exchangeToCurrency"] = exchangeToCurrency
        }
        if let exchangeFromAmount = exchangeFromAmount {
            dict["exchangeFromAmount"] = exchangeFromAmount
        }
        if let exchangeToAmount = exchangeToAmount {
            dict["exchangeToAmount"] = exchangeToAmount
        }
        if let note = note {
            dict["note"] = note
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
