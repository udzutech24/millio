//
//  Payment.swift
//  millio
//
//  Created by Александр Сидоркин on 11.01.2026.
//

import Foundation
import SwiftData

/// Тип платежа
enum PaymentType: String, Codable {
    case regular = "regular" // Обычный ежемесячный платеж
    case earlyFull = "early_full" // Полное досрочное погашение
    case earlyReduceTerm = "early_reduce_term" // Досрочное погашение с уменьшением срока
    case earlyReducePayment = "early_reduce_payment" // Досрочное погашение с уменьшением платежа
}

/// Платеж по кредиту
@Model
final class Payment: Persistable {
    /// Сумма платежа
    var amount: Double = 0.0
    
    /// Тип платежа
    var paymentTypeRaw: String = "regular"
    
    /// Дата платежа
    var paymentDate: Date = Date()
    
    /// Примечание (опционально)
    var note: String = ""
    
    /// Дата создания
    var createdAt: Date = Date()
    
    var paymentType: PaymentType {
        get { PaymentType(rawValue: paymentTypeRaw) ?? .regular }
        set { paymentTypeRaw = newValue.rawValue }
    }
    
    init(
        amount: Double,
        paymentType: PaymentType = .regular,
        paymentDate: Date = Date(),
        note: String = ""
    ) {
        self.amount = amount
        self.paymentTypeRaw = paymentType.rawValue
        self.paymentDate = paymentDate
        self.note = note
        self.createdAt = Date()
    }
    
    // MARK: - Exportable
    
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "Payment",
            "amount": amount,
            "paymentTypeRaw": paymentTypeRaw,
            "paymentDate": paymentDate.timeIntervalSince1970,
            "note": note,
            "createdAt": createdAt.timeIntervalSince1970
        ]
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["amount"] as? Double != nil,
              dict["paymentTypeRaw"] as? String != nil,
              dict["paymentDate"] as? TimeInterval != nil,
              dict["createdAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}
