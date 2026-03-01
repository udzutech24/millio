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
    case refinancing = "refinancing" // Рефинансирование
    case other = "other" // Другое
    
    var displayName: String {
        switch self {
        case .consumer: return "Потребительский"
        case .mortgage: return "Ипотека"
        case .auto: return "Автокредит"
        case .refinancing: return "Рефинансирование"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .consumer: return "creditcard.fill"
        case .mortgage: return "house.fill"
        case .auto: return "car.fill"
        case .refinancing: return "arrow.triangle.2.circlepath"
        case .other: return "doc.text.fill"
        }
    }
}

/// Режим выбора даты платежа по кредиту
enum CreditPaymentMode: String, Codable, CaseIterable {
    case dayOfMonth = "day_of_month"
    case nextDate = "next_date"

    var displayName: String {
        switch self {
        case .dayOfMonth:
            return "День месяца"
        case .nextDate:
            return "Следующая дата"
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

    /// Изначальный остаток долга для истории (не меняется при редактировании)
    var initialRemainingAmount: Double = 0.0

    /// Флаг, что initialRemainingAmount установлен
    var hasInitialRemainingAmount: Bool = false

    /// Ручная корректировка остатка долга относительно расчетного значения
    var remainingAmountAdjustment: Double = 0.0
    
    /// Сумма досрочных платежей (для расчета)
    var earlyPaymentsAmount: Double = 0.0
    
    /// Избранный кредит
    var isFavorite: Bool = false
    
    /// Кредит закрыт (полностью погашен)
    var isClosed: Bool = false
    
    /// Учитывать в общих финансах
    var includeInTotal: Bool = true

    /// Режим выбора даты платежа
    var paymentModeRaw: String = CreditPaymentMode.dayOfMonth.rawValue

    /// День месяца для платежа (1...31), если выбран режим dayOfMonth
    var paymentDayOfMonth: Int?

    /// Следующая дата платежа, если выбран режим nextDate
    var nextPaymentDate: Date?

    /// Включено ли напоминание о платеже
    var reminderEnabled: Bool = false

    /// За сколько дней до платежа напомнить
    var reminderDaysBefore: Int?

    /// Время напоминания
    var reminderTime: Date?
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    /// Дата архивирования (nil = активный кредит)
    var archivedAt: Date?

    /// Стабильный идентификатор для связей между сущностями
    var uniqueID: String = ""
    
    var bank: Bank {
        get { Bank(rawValue: bankRaw) ?? .other }
        set { bankRaw = newValue.rawValue }
    }
    
    var creditType: CreditType {
        get { CreditType(rawValue: creditTypeRaw) ?? .consumer }
        set { creditTypeRaw = newValue.rawValue }
    }

    var paymentMode: CreditPaymentMode {
        get { CreditPaymentMode(rawValue: paymentModeRaw) ?? .dayOfMonth }
        set { paymentModeRaw = newValue.rawValue }
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
        endDate: Date? = nil,
        includeInTotal: Bool = true
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
        self.initialRemainingAmount = self.remainingAmount
        self.hasInitialRemainingAmount = true
        self.includeInTotal = includeInTotal
        self.createdAt = Date()
        self.updatedAt = Date()
        self.uniqueID = UUID().uuidString
        self.paymentDayOfMonth = Calendar.current.component(.day, from: Date())
    }
    
    /// Обновить остаток долга на основе прошедших месяцев
    /// Использует правильную формулу для аннуитетного кредита через оставшиеся платежи
    func updateRemainingAmount() {
        let scheduledRemaining = calculateScheduledRemainingAmount()

        let adjustedRemaining = scheduledRemaining + remainingAmountAdjustment
        if adjustedRemaining <= 0 {
            remainingAmount = 0
            isClosed = true
        } else {
            remainingAmount = adjustedRemaining
        }

        updatedAt = Date()
    }

    /// Рассчитать остаток долга без учета ручной корректировки
    func calculateScheduledRemainingAmount() -> Double {
        let monthsPaid = min(monthsPassed, termMonths)
        let monthsRemaining = max(0, termMonths - monthsPaid)

        // Если все платежи сделаны, остаток равен нулю
        guard monthsRemaining > 0 else {
            return 0
        }

        // Если платежей не было, остаток равен сумме кредита
        guard monthsPaid > 0 else {
            return max(0, amount - earlyPaymentsAmount)
        }

        let monthlyRate = interestRate / 12.0 / 100.0

        if monthlyRate == 0 {
            // Без процентов: просто вычитаем выплаченное
            let paid = monthlyPayment * Double(monthsPaid)
            return max(0, amount - paid - earlyPaymentsAmount)
        }

        // Формула для расчета остатка долга через текущую стоимость оставшихся платежей:
        // S_n = M * ((1 - (1 + r)^-n_remaining) / r)
        // где M - ежемесячный платеж, r - месячная ставка, n_remaining - оставшиеся месяцы
        let discountFactor = pow(1 + monthlyRate, -Double(monthsRemaining))
        let remaining = monthlyPayment * ((1 - discountFactor) / monthlyRate)
        return max(0, remaining - earlyPaymentsAmount)
    }
    
    /// Рассчитать новый срок при досрочном погашении с уменьшением срока
    /// Возвращает новый срок в месяцах (оставшийся срок после платежа)
    func calculateNewTermAfterEarlyPayment(earlyPaymentAmount: Double) -> Int {
        guard earlyPaymentAmount > 0, remainingAmount > 0 else { 
            return monthsRemaining 
        }
        
        // Новый остаток после досрочного платежа
        let newRemaining = remainingAmount - earlyPaymentAmount
        
        if newRemaining <= 0 {
            return 0 // Кредит полностью погашен
        }
        
        // Рассчитываем новый срок через формулу аннуитета в обратную сторону
        // n = log(1 + S*r/M) / log(1 + r)
        // где S - остаток, r - месячная ставка, M - ежемесячный платеж
        let monthlyRate = interestRate / 12.0 / 100.0
        
        if monthlyRate == 0 {
            // Без процентов: просто делим остаток на платеж
            return Int(ceil(newRemaining / monthlyPayment))
        }
        
        // С формулой аннуитета
        // M = S * (r * (1 + r)^n) / ((1 + r)^n - 1)
        // Решаем обратно: n = log(1 + S*r/M) / log(1 + r)
        let ratio = 1 + (newRemaining * monthlyRate / monthlyPayment)
        guard ratio > 1 else { return 1 }
        
        let newTerm = log(ratio) / log(1 + monthlyRate)
        return max(1, Int(ceil(newTerm)))
    }
    
    /// Рассчитать новый ежемесячный платеж при досрочном погашении с уменьшением платежа
    /// Возвращает новый ежемесячный платеж
    func calculateNewPaymentAfterEarlyPayment(earlyPaymentAmount: Double) -> Double {
        guard earlyPaymentAmount > 0, remainingAmount > 0 else { return monthlyPayment }
        
        // Новый остаток после досрочного платежа
        let newRemaining = remainingAmount - earlyPaymentAmount
        
        if newRemaining <= 0 {
            return 0 // Кредит полностью погашен
        }
        
        // Рассчитываем новый платеж по формуле аннуитета
        return Credit.calculateMonthlyPayment(
            amount: newRemaining,
            annualInterestRate: interestRate,
            termMonths: monthsRemaining
        )
    }

    /// Применить ручную корректировку остатка долга (из формы/быстрого редактирования)
    func applyManualRemainingAmount(_ newAmount: Double) {
        let clampedAmount = max(0, newAmount)
        let scheduledRemaining = calculateScheduledRemainingAmount()
        remainingAmountAdjustment = clampedAmount - scheduledRemaining
        remainingAmount = clampedAmount
    }

    /// Обновить режим и дату платежа с очисткой взаимоисключающего поля
    func applyPaymentSchedule(
        mode: CreditPaymentMode,
        dayOfMonth: Int?,
        nextDate: Date?
    ) {
        paymentMode = mode
        switch mode {
        case .dayOfMonth:
            if let dayOfMonth {
                paymentDayOfMonth = min(31, max(1, dayOfMonth))
            } else {
                paymentDayOfMonth = nil
            }
            nextPaymentDate = nil
        case .nextDate:
            nextPaymentDate = nextDate
            paymentDayOfMonth = nil
        }
    }

    /// Обновить настройки напоминания
    func applyReminder(
        enabled: Bool,
        daysBefore: Int?,
        reminderTime: Date?
    ) {
        reminderEnabled = enabled
        guard enabled else {
            reminderDaysBefore = nil
            self.reminderTime = nil
            return
        }
        if let daysBefore {
            reminderDaysBefore = max(0, daysBefore)
        } else {
            reminderDaysBefore = nil
        }
        self.reminderTime = reminderTime
    }
    
    /// Применить досрочное погашение
    /// - Parameters:
    ///   - amount: Сумма досрочного платежа
    ///   - reduceTerm: true = уменьшить срок, false = уменьшить платеж
    func applyEarlyPayment(amount: Double, reduceTerm: Bool) {
        guard amount > 0, remainingAmount > 0, !isClosed else { return }
        
        // Сначала обновляем остаток
        remainingAmount -= amount
        earlyPaymentsAmount += amount
        
        if remainingAmount <= 0 {
            // Полное погашение
            isClosed = true
            remainingAmount = 0
            termMonths = monthsPassed
            endDate = Date() // Обновляем дату окончания на сегодня
        } else if reduceTerm {
            // Уменьшаем срок, платеж не меняется
            // Рассчитываем новый срок на основе нового остатка
            let newTerm = calculateNewTermAfterEarlyPayment(earlyPaymentAmount: amount)
            termMonths = monthsPassed + newTerm
            
            // Обновляем дату окончания
            if let newEndDate = Calendar.current.date(byAdding: .month, value: newTerm, to: Date()) {
                endDate = newEndDate
            }
        } else {
            // Уменьшаем платеж, срок не меняется
            // Рассчитываем новый платеж на основе нового остатка и оставшегося срока
            monthlyPayment = calculateNewPaymentAfterEarlyPayment(earlyPaymentAmount: amount)
            // Срок и дата окончания остаются прежними
        }
        
        updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    /// Уникальный идентификатор кредита для восстановления связей при restore
    var creditUniqueID: String {
        return uniqueID.isEmpty ? legacyCreditUniqueID() : uniqueID
    }
    
    /// Убедиться, что uniqueID установлен (миграция для старых данных)
    func ensureUniqueID() {
        if uniqueID.isEmpty {
            uniqueID = legacyCreditUniqueID()
        }
    }

    private func legacyCreditUniqueID() -> String {
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
            "initialRemainingAmount": initialRemainingAmount,
            "hasInitialRemainingAmount": hasInitialRemainingAmount,
            "remainingAmountAdjustment": remainingAmountAdjustment,
            "earlyPaymentsAmount": earlyPaymentsAmount,
            "isClosed": isClosed,
            "isFavorite": isFavorite,
            "includeInTotal": includeInTotal,
            "paymentModeRaw": paymentModeRaw,
            "reminderEnabled": reminderEnabled,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "creditUniqueID": creditUniqueID
        ]

        if let paymentDayOfMonth {
            dict["paymentDayOfMonth"] = paymentDayOfMonth
        }
        if let nextPaymentDate {
            dict["nextPaymentDate"] = nextPaymentDate.timeIntervalSince1970
        }
        if let reminderDaysBefore {
            dict["reminderDaysBefore"] = reminderDaysBefore
        }
        if let reminderTime {
            dict["reminderTime"] = reminderTime.timeIntervalSince1970
        }
        
        if let archivedAt = archivedAt {
            dict["archivedAt"] = archivedAt.timeIntervalSince1970
        }
        
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
