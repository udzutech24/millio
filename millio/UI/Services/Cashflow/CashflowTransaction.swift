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
        case .balanceAdjustment: return "Изменение баланса"
        case .cardBalanceAdjustment: return "Корректировка баланса"
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
        creditID: String? = nil,
        investmentID: String? = nil,
        incomeCategory: IncomeCategory? = nil,
        expenseCategory: ExpenseCategory? = nil,
        note: String? = nil
    ) {
        self.transactionTypeRaw = transactionType.rawValue
        self.amount = amount
        self.currency = currency
        self.transactionDate = transactionDate
        self.cardID = cardID
        self.toCardID = toCardID
        self.creditID = creditID
        self.investmentID = investmentID
        self.incomeCategoryRaw = incomeCategory?.rawValue
        self.expenseCategoryRaw = expenseCategory?.rawValue
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
