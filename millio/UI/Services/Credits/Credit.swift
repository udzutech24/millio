//
//  Credit.swift
//  millio
//
//  Created by Александр Сидоркин on 11.01.2026.
//

import Foundation
import SwiftData

/// Тип кредита
enum CreditType: String, Codable, CaseIterable {
    case consumer = "consumer" // Потребительский
    case mortgage = "mortgage" // Ипотека
    case auto = "auto" // Автокредит
    case creditCard = "credit_card" // Кредитная карта
    case refinancing = "refinancing" // Рефинансирование
    case other = "other" // Другое
    
    var displayName: String {
        switch self {
        case .consumer: return "Потребительский"
        case .mortgage: return "Ипотека"
        case .auto: return "Автокредит"
        case .creditCard: return "Кредитная карта"
        case .refinancing: return "Рефинансирование"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .consumer: return "creditcard.fill"
        case .mortgage: return "house.fill"
        case .auto: return "car.fill"
        case .creditCard: return "creditcard.trianglebadge.exclamationmark.fill"
        case .refinancing: return "arrow.triangle.2.circlepath"
        case .other: return "doc.text.fill"
        }
    }
}

/// Кредит
@Model
final class Credit: Persistable {
    /// Название кредита
    var name: String = ""
    
    /// Сумма кредита (первоначальная)
    var amount: Double = 0.0
    
    /// Процентная ставка (годовая, в процентах)
    var interestRate: Double = 0.0
    
    /// Ежемесячный платеж
    var monthlyPayment: Double = 0.0
    
    /// Дата начала кредита
    var startDate: Date = Date()
    
    /// Дата окончания кредита
    var endDate: Date?
    
    /// Срок кредита в месяцах
    var termMonths: Int = 0
    
    /// Валюта кредита
    var currency: String = "RUB"
    
    /// Банк
    var bankRaw: String = "other"
    
    /// Тип кредита
    var creditTypeRaw: String = "consumer"
    
    /// Остаток долга (вычисляется автоматически)
    var remainingAmount: Double = 0.0
    
    /// Избранный кредит
    var isFavorite: Bool = false
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    var bank: Bank {
        get { Bank(rawValue: bankRaw) ?? .other }
        set { bankRaw = newValue.rawValue }
    }
    
    var creditType: CreditType {
        get { CreditType(rawValue: creditTypeRaw) ?? .consumer }
        set { creditTypeRaw = newValue.rawValue }
    }
    
    /// Количество прошедших месяцев с начала кредита
    var monthsPassed: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: startDate, to: Date())
        return max(0, components.month ?? 0)
    }
    
    /// Осталось месяцев до погашения
    var monthsRemaining: Int {
        max(0, termMonths - monthsPassed)
    }
    
    /// Рассчитать ежемесячный платеж по формуле аннуитета
    /// M = S * (r * (1 + r)^n) / ((1 + r)^n - 1)
    /// где S - сумма кредита, r - месячная ставка, n - количество месяцев
    static func calculateMonthlyPayment(amount: Double, annualInterestRate: Double, termMonths: Int) -> Double {
        guard amount > 0, termMonths > 0, annualInterestRate >= 0 else { return 0 }
        
        // Месячная процентная ставка (в долях)
        let monthlyRate = annualInterestRate / 12.0 / 100.0
        
        // Если процентная ставка равна нулю, просто делим сумму на количество месяцев
        if monthlyRate == 0 {
            return amount / Double(termMonths)
        }
        
        // Формула аннуитетного платежа
        let power = pow(1 + monthlyRate, Double(termMonths))
        let monthlyPayment = amount * (monthlyRate * power) / (power - 1)
        
        return monthlyPayment
    }
    
    /// Рассчитать срок в месяцах из дат начала и окончания
    /// Считает количество месяцев между датами (включая начальный и конечный месяц)
    /// Пример: с 17 дек 2022 до 11 окт 2027 = 58 месяцев
    static func calculateTermMonths(from startDate: Date, to endDate: Date) -> Int {
        let calendar = Calendar.current
        
        // Получаем компоненты дат
        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
        
        guard let startYear = startComponents.year,
              let startMonth = startComponents.month,
              let startDay = startComponents.day,
              let endYear = endComponents.year,
              let endMonth = endComponents.month,
              let endDay = endComponents.day else {
            // Fallback: используем dateComponents
            let components = calendar.dateComponents([.year, .month], from: startDate, to: endDate)
            if let years = components.year, let months = components.month {
                return max(1, years * 12 + months)
            }
            return max(1, components.month ?? 0)
        }
        
        // Считаем количество месяцев от начала начального месяца до начала конечного месяца
        // (год_конца - год_начала) * 12 + (месяц_конца - месяц_начала)
        // Это дает количество месяцев ВКЛЮЧАЯ начальный месяц до начала конечного месяца
        let monthsToEndMonth = (endYear - startYear) * 12 + (endMonth - startMonth)
        
        // Если endDay >= startDay, конечный месяц считается полным
        // Иначе конечный месяц неполный и не считается
        if endDay >= startDay {
            // Конечный месяц полный: monthsToEndMonth уже включает начальный месяц,
            // добавляем конечный месяц
            return max(1, monthsToEndMonth + 1)
        } else {
            // Конечный месяц неполный: monthsToEndMonth уже включает начальный месяц,
            // конечный месяц не считаем
            return max(1, monthsToEndMonth)
        }
    }
    
    /// Общая сумма к выплате (сумма кредита + проценты)
    var totalAmount: Double {
        amount + totalInterest
    }
    
    /// Общая сумма процентов
    var totalInterest: Double {
        (monthlyPayment * Double(termMonths)) - amount
    }
    
    /// Уже выплачено
    var paidAmount: Double {
        amount - remainingAmount
    }
    
    /// Процент выплаты
    var paymentProgress: Double {
        guard amount > 0 else { return 0 }
        return min(1.0, paidAmount / amount)
    }
    
    init(
        name: String,
        amount: Double,
        interestRate: Double,
        monthlyPayment: Double,
        startDate: Date,
        termMonths: Int,
        currency: String,
        bank: Bank = .other,
        creditType: CreditType = .consumer,
        endDate: Date? = nil
    ) {
        self.name = name
        self.amount = amount
        self.interestRate = interestRate
        self.monthlyPayment = monthlyPayment
        self.startDate = startDate
        self.termMonths = termMonths
        self.currency = currency
        self.bankRaw = bank.rawValue
        self.creditTypeRaw = creditType.rawValue
        self.endDate = endDate
        self.remainingAmount = amount // Изначально остаток равен сумме кредита
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Обновить остаток долга на основе прошедших месяцев
    func updateRemainingAmount() {
        let paid = monthlyPayment * Double(min(monthsPassed, termMonths))
        remainingAmount = max(0, amount - paid)
        updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    /// Уникальный идентификатор кредита для восстановления связей при restore
    var creditUniqueID: String {
        "\(name)|\(amount)|\(interestRate)|\(startDate.timeIntervalSince1970)|\(termMonths)|\(currency)|\(bankRaw)|\(creditTypeRaw)"
    }
    
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "Credit",
            "name": name,
            "amount": amount,
            "interestRate": interestRate,
            "monthlyPayment": monthlyPayment,
            "startDate": startDate.timeIntervalSince1970,
            "endDate": endDate?.timeIntervalSince1970 ?? 0,
            "termMonths": termMonths,
            "currency": currency,
            "bankRaw": bankRaw,
            "creditTypeRaw": creditTypeRaw,
            "remainingAmount": remainingAmount,
            "isFavorite": isFavorite,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "creditUniqueID": creditUniqueID
        ]
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["amount"] as? Double != nil,
              dict["interestRate"] as? Double != nil,
              dict["monthlyPayment"] as? Double != nil,
              dict["startDate"] as? TimeInterval != nil,
              dict["termMonths"] as? Int != nil,
              dict["currency"] as? String != nil,
              dict["bankRaw"] as? String != nil,
              dict["creditTypeRaw"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
}
