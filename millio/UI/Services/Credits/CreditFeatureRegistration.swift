//
//  CreditFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 11.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Credit для backup/restore
struct CreditFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(Credit.self, typeName: "Credit")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(CreditImporter.self)
    }
}

// MARK: - Credit Importer

struct CreditImporter: ModelImporter {
    static func importType() -> String {
        "Credit"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String,
              let amount = data["amount"] as? Double,
              let interestRate = data["interestRate"] as? Double,
              let monthlyPayment = data["monthlyPayment"] as? Double,
              let startDate = data["startDate"] as? TimeInterval,
              let termMonths = data["termMonths"] as? Int,
              let endDate = data["endDate"] as? TimeInterval,
              let currency = data["currency"] as? String,
              let bankRaw = data["bankRaw"] as? String,
              let creditTypeRaw = data["creditTypeRaw"] as? String,
              let remainingAmount = data["remainingAmount"] as? Double,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Проверяем, не существует ли уже кредит с такими же данными
        // Используем комбинацию полей без точного сравнения дат
        let existingCreditDescriptor = FetchDescriptor<Credit>(
            predicate: #Predicate<Credit> { credit in
                credit.name == name &&
                credit.amount == amount &&
                credit.termMonths == termMonths &&
                credit.currency == currency &&
                credit.bankRaw == bankRaw &&
                credit.creditTypeRaw == creditTypeRaw
            }
        )
        
        // Если кредит уже существует, обновляем его данные вместо создания нового
        if let existingCredit = try? context.fetch(existingCreditDescriptor).first {
            if let uniqueID = data["creditUniqueID"] as? String, !uniqueID.isEmpty {
                existingCredit.uniqueID = uniqueID
            }
            if let initialRemainingAmount = data["initialRemainingAmount"] as? Double {
                existingCredit.initialRemainingAmount = initialRemainingAmount
                existingCredit.hasInitialRemainingAmount = data["hasInitialRemainingAmount"] as? Bool ?? true
            }
            existingCredit.interestRate = interestRate
            existingCredit.monthlyPayment = monthlyPayment
            existingCredit.remainingAmount = remainingAmount
            existingCredit.earlyPaymentsAmount = data["earlyPaymentsAmount"] as? Double ?? 0.0
            existingCredit.isClosed = data["isClosed"] as? Bool ?? false
            existingCredit.isFavorite = data["isFavorite"] as? Bool ?? false
            existingCredit.includeInTotal = data["includeInTotal"] as? Bool ?? true
            existingCredit.updatedAt = Date(timeIntervalSince1970: updatedAt)
            existingCredit.updateRemainingAmount()
            
            AppLogger.log(.info, category: "CreditImporter", "Updated existing credit '\(name)' instead of creating duplicate")
            return
        }
        
        // Создаем новый кредит только если он не существует
        let credit = Credit(
            name: name,
            amount: amount,
            interestRate: interestRate,
            monthlyPayment: monthlyPayment,
            startDate: Date(timeIntervalSince1970: startDate),
            termMonths: termMonths,
            currency: currency,
            bank: Bank(rawValue: bankRaw) ?? .other,
            creditType: CreditType(rawValue: creditTypeRaw) ?? .consumer
        )
        
        credit.endDate = endDate > 0 ? Date(timeIntervalSince1970: endDate) : nil
        credit.remainingAmount = remainingAmount
        if let initialRemainingAmount = data["initialRemainingAmount"] as? Double {
            credit.initialRemainingAmount = initialRemainingAmount
            credit.hasInitialRemainingAmount = data["hasInitialRemainingAmount"] as? Bool ?? true
        } else {
            credit.initialRemainingAmount = remainingAmount
            credit.hasInitialRemainingAmount = true
        }
        credit.earlyPaymentsAmount = data["earlyPaymentsAmount"] as? Double ?? 0.0
        credit.isClosed = data["isClosed"] as? Bool ?? false
        credit.isFavorite = data["isFavorite"] as? Bool ?? false
        credit.includeInTotal = data["includeInTotal"] as? Bool ?? true
        credit.createdAt = Date(timeIntervalSince1970: createdAt)
        credit.updatedAt = Date(timeIntervalSince1970: updatedAt)
        if let uniqueID = data["creditUniqueID"] as? String, !uniqueID.isEmpty {
            credit.uniqueID = uniqueID
        }
        
        context.insert(credit)
    }
}
