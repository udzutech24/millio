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
        ModelTypeRegistry.shared.register(CashflowCustomCategory.self, typeName: "CashflowCustomCategory")
        ModelTypeRegistry.shared.register(
            CashflowSystemCategoryOverride.self,
            typeName: "CashflowSystemCategoryOverride"
        )
        ModelTypeRegistry.shared.register(BudgetPlan.self, typeName: "BudgetPlan")
        ModelTypeRegistry.shared.register(BudgetCategoryLimit.self, typeName: "BudgetCategoryLimit")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(CashflowTransactionImporter.self)
        ModelTypeRegistry.shared.registerImporter(CashflowCustomCategoryImporter.self)
        ModelTypeRegistry.shared.registerImporter(CashflowSystemCategoryOverrideImporter.self)
        ModelTypeRegistry.shared.registerImporter(BudgetPlanImporter.self)
        ModelTypeRegistry.shared.registerImporter(BudgetCategoryLimitImporter.self)
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
        let operationGroupID = dict["operationGroupID"] as? String
        let assetQuantityBefore = dict["assetQuantityBefore"] as? Double
        let assetQuantityAfter = dict["assetQuantityAfter"] as? Double
        let assetUnitPriceBefore = dict["assetUnitPriceBefore"] as? Double
        let assetUnitPriceAfter = dict["assetUnitPriceAfter"] as? Double
        let assetAmountBefore = dict["assetAmountBefore"] as? Double
        let assetAmountAfter = dict["assetAmountAfter"] as? Double
        let assetPurchaseUnitPriceBefore = dict["assetPurchaseUnitPriceBefore"] as? Double
        let assetPurchaseUnitPriceAfter = dict["assetPurchaseUnitPriceAfter"] as? Double
        let assetPurchaseCostBefore = dict["assetPurchaseCostBefore"] as? Double
        let assetPurchaseCostAfter = dict["assetPurchaseCostAfter"] as? Double
        let exchangeRate = dict["exchangeRate"] as? Double
        let exchangeRateDate = (dict["exchangeRateDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        let exchangeRateCurrency = dict["exchangeRateCurrency"] as? String
        let recurrenceRuleRaw = dict["recurrenceRuleRaw"] as? String
        let recurrenceRule = recurrenceRuleRaw.flatMap(CashflowRecurrenceRule.init(rawValue:)) ?? .none
        let recurrenceWeekdaysRaw = dict["recurrenceWeekdaysRaw"] as? String
        let recurrenceWeekdays: Set<CashflowRecurrenceWeekday> = {
            guard let recurrenceWeekdaysRaw, !recurrenceWeekdaysRaw.isEmpty else { return [] }
            let weekdays = recurrenceWeekdaysRaw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .compactMap(CashflowRecurrenceWeekday.init(rawValue:))
            return Set(weekdays)
        }()
        let recurrenceSeriesID = dict["recurrenceSeriesID"] as? String
        let affectsCardBalance = dict["affectsCardBalance"] as? Bool ?? true
        let affectsCashflowTotals = dict["affectsCashflowTotals"] as? Bool
        let hasAppliedBalanceEffect = dict["hasAppliedBalanceEffect"] as? Bool ?? false
        
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
            incomeCategoryRaw: incomeCategoryRaw,
            expenseCategoryRaw: expenseCategoryRaw,
            note: note,
            operationGroupID: operationGroupID,
            recurrenceRule: recurrenceRule,
            recurrenceWeekdays: recurrenceWeekdays,
            recurrenceSeriesID: recurrenceSeriesID,
            affectsCardBalance: affectsCardBalance,
            affectsCashflowTotals: affectsCashflowTotals
        )
        transaction.createdAt = createdAt
        transaction.updatedAt = updatedAt
        transaction.exchangeRate = exchangeRate
        transaction.exchangeRateDate = exchangeRateDate
        transaction.exchangeRateCurrency = exchangeRateCurrency
        transaction.assetQuantityBefore = assetQuantityBefore
        transaction.assetQuantityAfter = assetQuantityAfter
        transaction.assetUnitPriceBefore = assetUnitPriceBefore
        transaction.assetUnitPriceAfter = assetUnitPriceAfter
        transaction.assetAmountBefore = assetAmountBefore
        transaction.assetAmountAfter = assetAmountAfter
        transaction.assetPurchaseUnitPriceBefore = assetPurchaseUnitPriceBefore
        transaction.assetPurchaseUnitPriceAfter = assetPurchaseUnitPriceAfter
        transaction.assetPurchaseCostBefore = assetPurchaseCostBefore
        transaction.assetPurchaseCostAfter = assetPurchaseCostAfter
        transaction.hasAppliedBalanceEffect = hasAppliedBalanceEffect

        context.insert(transaction)
    }
}

struct CashflowCustomCategoryImporter: ModelImporter {
    static func importType() -> String {
        "CashflowCustomCategory"
    }

    static var importPriority: Int { 20 }

    static func `import`(from data: [String : Any], context: ModelContext) throws {
        guard let categoryID = data["categoryID"] as? String,
              let kindRaw = data["kindRaw"] as? String,
              let name = data["name"] as? String,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let kind = CashflowCategoryKind(rawValue: kindRaw) ?? .expense
        let normalizedName = (data["normalizedName"] as? String) ?? CashflowCustomCategory.normalize(name)
        let icon = CashflowCustomCategory.normalizeIcon(
            (data["icon"] as? String) ?? CashflowCustomCategory.defaultIcon
        )

        let category = CashflowCustomCategory(kind: kind, name: name)
        category.categoryID = categoryID
        category.kindRaw = kind.rawValue
        category.name = name
        category.normalizedName = normalizedName
        category.icon = icon
        category.createdAt = Date(timeIntervalSince1970: createdAt)
        category.updatedAt = Date(timeIntervalSince1970: updatedAt)

        context.insert(category)
    }
}

struct CashflowSystemCategoryOverrideImporter: ModelImporter {
    static func importType() -> String {
        "CashflowSystemCategoryOverride"
    }

    static var importPriority: Int { 21 }

    static func `import`(from data: [String : Any], context: ModelContext) throws {
        guard let overrideID = data["overrideID"] as? String,
              let kindRaw = data["kindRaw"] as? String,
              let categoryRaw = data["categoryRaw"] as? String,
              let name = data["name"] as? String,
              let isHidden = data["isHidden"] as? Bool,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let kind = CashflowCategoryKind(rawValue: kindRaw) ?? .expense
        let icon = CashflowCustomCategory.normalizeIcon(
            (data["icon"] as? String) ?? CashflowCustomCategory.defaultIcon
        )
        let normalizedName = (data["normalizedName"] as? String) ?? CashflowCustomCategory.normalize(name)

        let override = CashflowSystemCategoryOverride(
            kind: kind,
            categoryRaw: categoryRaw,
            name: name,
            icon: icon,
            isHidden: isHidden
        )
        override.overrideID = overrideID
        override.kindRaw = kind.rawValue
        override.categoryRaw = categoryRaw
        override.name = name
        override.normalizedName = normalizedName
        override.icon = icon
        override.isHidden = isHidden
        override.createdAt = Date(timeIntervalSince1970: createdAt)
        override.updatedAt = Date(timeIntervalSince1970: updatedAt)

        context.insert(override)
    }
}

struct BudgetPlanImporter: ModelImporter {
    static func importType() -> String {
        "BudgetPlan"
    }

    static var importPriority: Int { 22 }

    static func `import`(from data: [String : Any], context: ModelContext) throws {
        guard let budgetID = data["budgetID"] as? String,
              let periodTypeRaw = data["periodTypeRaw"] as? String,
              let anchorYear = data["anchorYear"] as? Int,
              let anchorMonth = data["anchorMonth"] as? Int,
              let currencyCode = data["currencyCode"] as? String,
              let totalLimitAmount = data["totalLimitAmount"] as? Double,
              let isCategoryBudgetingEnabled = data["isCategoryBudgetingEnabled"] as? Bool,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        let categoryKindRaw = data["categoryKindRaw"] as? String ?? CashflowCategoryKind.expense.rawValue

        let descriptor = BudgetPeriodDescriptor(
            type: BudgetPeriodType(rawValue: periodTypeRaw) ?? .month,
            startDate: (data["customStartDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            endDate: (data["customEndDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            anchorYear: anchorYear,
            anchorMonth: anchorMonth
        )
        let plan = BudgetPlan(
            categoryKind: CashflowCategoryKind(rawValue: categoryKindRaw) ?? .expense,
            descriptor: descriptor,
            currencyCode: currencyCode,
            totalLimitAmount: totalLimitAmount,
            isCategoryBudgetingEnabled: isCategoryBudgetingEnabled
        )
        plan.budgetID = budgetID
        plan.categoryKindRaw = categoryKindRaw
        plan.periodTypeRaw = periodTypeRaw
        plan.anchorYear = anchorYear
        plan.anchorMonth = anchorMonth
        plan.customStartDate = (data["customStartDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        plan.customEndDate = (data["customEndDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        plan.currencyCode = currencyCode
        plan.totalLimitAmount = totalLimitAmount
        plan.isCategoryBudgetingEnabled = isCategoryBudgetingEnabled
        plan.createdAt = Date(timeIntervalSince1970: createdAt)
        plan.updatedAt = Date(timeIntervalSince1970: updatedAt)
        context.insert(plan)
    }
}

struct BudgetCategoryLimitImporter: ModelImporter {
    static func importType() -> String {
        "BudgetCategoryLimit"
    }

    static var importPriority: Int { 23 }

    static func `import`(from data: [String : Any], context: ModelContext) throws {
        guard let categoryLimitID = data["categoryLimitID"] as? String,
              let budgetID = data["budgetID"] as? String,
              let categoryKindRaw = data["categoryKindRaw"] as? String,
              let categoryRawValue = data["categoryRawValue"] as? String,
              let limitAmount = data["limitAmount"] as? Double,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let limit = BudgetCategoryLimit(
            budgetID: budgetID,
            categoryKind: CashflowCategoryKind(rawValue: categoryKindRaw) ?? .expense,
            categoryRawValue: categoryRawValue,
            limitAmount: limitAmount
        )
        limit.categoryLimitID = categoryLimitID
        limit.budgetID = budgetID
        limit.categoryKindRaw = categoryKindRaw
        limit.categoryRawValue = categoryRawValue
        limit.limitAmount = limitAmount
        limit.createdAt = Date(timeIntervalSince1970: createdAt)
        limit.updatedAt = Date(timeIntervalSince1970: updatedAt)
        context.insert(limit)
    }
}
