//
//  CashflowFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Cashflow для backup/restore
struct CashflowFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(CashflowTransaction.self, typeName: "CashflowTransaction")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(CashflowTransactionImporter.self)
    }
}

// MARK: - Cashflow Transaction Importer

struct CashflowTransactionImporter: ModelImporter {
    static func importType() -> String {
        "CashflowTransaction"
    }
    
    static func `import`(from dict: [String: Any], context: ModelContext) throws {
        guard let transactionTypeRaw = dict["transactionTypeRaw"] as? String,
              let amount = dict["amount"] as? Double,
              let currency = dict["currency"] as? String,
              let transactionDateTimestamp = dict["transactionDate"] as? TimeInterval,
              let createdAtTimestamp = dict["createdAt"] as? TimeInterval,
              let updatedAtTimestamp = dict["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        let transactionDate = Date(timeIntervalSince1970: transactionDateTimestamp)
        let createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
        let updatedAt = Date(timeIntervalSince1970: updatedAtTimestamp)
        
        let transactionType = CashflowTransactionType(rawValue: transactionTypeRaw) ?? .expense
        let incomeCategoryRaw = dict["incomeCategoryRaw"] as? String
        let expenseCategoryRaw = dict["expenseCategoryRaw"] as? String
        let cardID = dict["cardID"] as? String
        let toCardID = dict["toCardID"] as? String
        let creditID = dict["creditID"] as? String
        let investmentID = dict["investmentID"] as? String
        let note = dict["note"] as? String
        let exchangeRate = dict["exchangeRate"] as? Double
        let exchangeRateDate = (dict["exchangeRateDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        let exchangeRateCurrency = dict["exchangeRateCurrency"] as? String
        
        let incomeCategory = incomeCategoryRaw.flatMap { IncomeCategory(rawValue: $0) }
        let expenseCategory = expenseCategoryRaw.flatMap { ExpenseCategory(rawValue: $0) }
        
        // Проверяем, не существует ли уже такая транзакция
        let uniqueID = dict["transactionUniqueID"] as? String
        if let uniqueID = uniqueID {
            let existingDescriptor = FetchDescriptor<CashflowTransaction>(
                predicate: #Predicate<CashflowTransaction> { transaction in
                    transaction.transactionUniqueID == uniqueID
                }
            )
            
            if let existing = try? context.fetch(existingDescriptor).first {
                // Обновляем существующую транзакцию
                existing.transactionTypeRaw = transactionTypeRaw
                existing.amount = amount
                existing.currency = currency
                existing.transactionDate = transactionDate
                existing.cardID = cardID
                existing.toCardID = toCardID
                existing.creditID = creditID
                existing.investmentID = investmentID
                existing.incomeCategoryRaw = incomeCategoryRaw
                existing.expenseCategoryRaw = expenseCategoryRaw
                existing.note = note
                existing.exchangeRate = exchangeRate
                existing.exchangeRateDate = exchangeRateDate
                existing.exchangeRateCurrency = exchangeRateCurrency
                existing.updatedAt = updatedAt
                return
            }
        }
        
        // Создаем новую транзакцию
        let transaction = CashflowTransaction(
            transactionType: transactionType,
            amount: amount,
            currency: currency,
            transactionDate: transactionDate,
            cardID: cardID,
            toCardID: toCardID,
            creditID: creditID,
            investmentID: investmentID,
            incomeCategory: incomeCategory,
            expenseCategory: expenseCategory,
            note: note
        )
        transaction.createdAt = createdAt
        transaction.updatedAt = updatedAt
        transaction.exchangeRate = exchangeRate
        transaction.exchangeRateDate = exchangeRateDate
        transaction.exchangeRateCurrency = exchangeRateCurrency
        
        context.insert(transaction)
    }
}
