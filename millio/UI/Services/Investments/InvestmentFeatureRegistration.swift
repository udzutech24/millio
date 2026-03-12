//
//  InvestmentFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей Investment для backup/restore
struct InvestmentFeatureRegistration {
    static func register() {
        // Регистрируем модели
        ModelTypeRegistry.shared.register(Investment.self, typeName: "Investment")
        ModelTypeRegistry.shared.register(AssetCatalogItem.self, typeName: "AssetCatalogItem")
        ModelTypeRegistry.shared.register(AssetProviderMapping.self, typeName: "AssetProviderMapping")
        
        // Регистрируем импортеры
        ModelTypeRegistry.shared.registerImporter(InvestmentImporter.self)
        ModelTypeRegistry.shared.registerImporter(AssetCatalogItemImporter.self)
        ModelTypeRegistry.shared.registerImporter(AssetProviderMappingImporter.self)
    }
}

// MARK: - Investment Importer

struct InvestmentImporter: ModelImporter {
    static func importType() -> String {
        "Investment"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let name = data["name"] as? String,
              let investmentTypeRaw = data["investmentTypeRaw"] as? String,
              let categoryRaw = data["categoryRaw"] as? String,
              let amount = data["amount"] as? Double,
              let currency = data["currency"] as? String,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Получаем priority (для обратной совместимости используем normal по умолчанию)
        let priorityRaw = data["priorityRaw"] as? String ?? "normal"
        let priority = InvestmentPriority(rawValue: priorityRaw) ?? .normal
        
        // Получаем includeInTotal (для обратной совместимости используем true по умолчанию)
        let includeInTotal = data["includeInTotal"] as? Bool ?? true
        let initialAmount = data["initialAmount"] as? Double
        let hasInitialAmount = data["hasInitialAmount"] as? Bool
        let marketSymbol = data["marketSymbol"] as? String
        let assetID = data["assetID"] as? String
        let marketExchange = data["marketExchange"] as? String
        let marketQuoteLookupKey = data["marketQuoteLookupKey"] as? String
        let marketMICCode = data["marketMICCode"] as? String
        let marketCurrency = data["marketCurrency"] as? String
        let marketQuantity = data["marketQuantity"] as? Double
        let lastKnownUnitPrice = data["lastKnownUnitPrice"] as? Double
        let averagePurchaseUnitPrice = data["averagePurchaseUnitPrice"] as? Double
        let totalPurchaseCost = data["totalPurchaseCost"] as? Double
        let marketProviderRaw = data["marketProviderRaw"] as? String
        let lastKnownPriceUpdatedAt = (data["lastKnownPriceUpdatedAt"] as? TimeInterval).map {
            Date(timeIntervalSince1970: $0)
        }
        
        // Проверяем, не существует ли уже инвестиция с такими же данными
        let existingInvestmentDescriptor = FetchDescriptor<Investment>(
            predicate: #Predicate<Investment> { investment in
                investment.name == name &&
                investment.investmentTypeRaw == investmentTypeRaw &&
                investment.categoryRaw == categoryRaw &&
                investment.amount == amount &&
                investment.currency == currency
            }
        )
        
        // Если инвестиция уже существует, обновляем ее данные вместо создания новой
        if let existingInvestment = try? context.fetch(existingInvestmentDescriptor).first {
            if let uniqueID = data["investmentUniqueID"] as? String, !uniqueID.isEmpty {
                existingInvestment.uniqueID = uniqueID
            }
            if let initialAmount = initialAmount {
                existingInvestment.initialAmount = initialAmount
                existingInvestment.hasInitialAmount = hasInitialAmount ?? true
            }
            existingInvestment.isFavorite = data["isFavorite"] as? Bool ?? false
            existingInvestment.priority = priority
            existingInvestment.includeInTotal = includeInTotal
            existingInvestment.updatedAt = Date(timeIntervalSince1970: updatedAt)
            existingInvestment.marketSymbol = marketSymbol
            existingInvestment.assetID = assetID
            existingInvestment.marketExchange = marketExchange
            existingInvestment.marketQuoteLookupKey = marketQuoteLookupKey
            existingInvestment.marketMICCode = marketMICCode
            existingInvestment.marketCurrency = marketCurrency
            existingInvestment.marketQuantity = marketQuantity
            existingInvestment.lastKnownUnitPrice = lastKnownUnitPrice
            existingInvestment.averagePurchaseUnitPrice = averagePurchaseUnitPrice
            existingInvestment.totalPurchaseCost = totalPurchaseCost
            existingInvestment.lastKnownPriceUpdatedAt = lastKnownPriceUpdatedAt
            existingInvestment.marketProviderRaw = marketProviderRaw
            if existingInvestment.assetID == nil || existingInvestment.assetID?.isEmpty == true {
                let resolvedIdentity = MarketAssetIdentityResolver.resolve(
                    category: existingInvestment.category,
                    symbol: marketSymbol,
                    exchange: marketExchange,
                    instrumentName: existingInvestment.name,
                    micCode: marketMICCode,
                    instrumentType: existingInvestment.category == .crypto ? "Cryptocurrency" : "Common Stock",
                    currency: marketCurrency,
                    country: nil,
                    providerName: marketProviderRaw
                )
                existingInvestment.assetID = resolvedIdentity?.assetID
                if let resolvedIdentity {
                    syncCatalogOnMainActorIfNeeded(identity: resolvedIdentity, context: context)
                }
            }
            if let archivedAt = data["archivedAt"] as? TimeInterval {
                existingInvestment.archivedAt = Date(timeIntervalSince1970: archivedAt)
            }
            existingInvestment.ensureUniqueID()
            
            AppLogger.log(.info, category: "InvestmentImporter", "Updated existing investment '\(name)' instead of creating duplicate")
            return
        }
        
        // Создаем новую инвестицию только если она не существует
        let investment = Investment(
            name: name,
            investmentType: InvestmentType(rawValue: investmentTypeRaw) ?? .positive,
            category: InvestmentCategory(rawValue: categoryRaw) ?? .other,
            amount: amount,
            currency: currency,
            includeInTotal: includeInTotal,
            priority: priority,
            isFavorite: data["isFavorite"] as? Bool ?? false
        )
        
        investment.createdAt = Date(timeIntervalSince1970: createdAt)
        investment.updatedAt = Date(timeIntervalSince1970: updatedAt)
        if let archivedAt = data["archivedAt"] as? TimeInterval {
            investment.archivedAt = Date(timeIntervalSince1970: archivedAt)
        }
        if let initialAmount = initialAmount {
            investment.initialAmount = initialAmount
            investment.hasInitialAmount = hasInitialAmount ?? true
        } else {
            investment.initialAmount = amount
            investment.hasInitialAmount = true
        }
        if let uniqueID = data["investmentUniqueID"] as? String, !uniqueID.isEmpty {
            investment.uniqueID = uniqueID
        }
        investment.marketSymbol = marketSymbol
        investment.assetID = assetID
        investment.marketExchange = marketExchange
        investment.marketQuoteLookupKey = marketQuoteLookupKey
        investment.marketMICCode = marketMICCode
        investment.marketCurrency = marketCurrency
        investment.marketQuantity = marketQuantity
        investment.lastKnownUnitPrice = lastKnownUnitPrice
        investment.averagePurchaseUnitPrice = averagePurchaseUnitPrice
        investment.totalPurchaseCost = totalPurchaseCost
        investment.lastKnownPriceUpdatedAt = lastKnownPriceUpdatedAt
        investment.marketProviderRaw = marketProviderRaw
        if investment.assetID == nil || investment.assetID?.isEmpty == true {
            let resolvedIdentity = MarketAssetIdentityResolver.resolve(
                category: investment.category,
                symbol: marketSymbol,
                exchange: marketExchange,
                instrumentName: investment.name,
                micCode: marketMICCode,
                instrumentType: investment.category == .crypto ? "Cryptocurrency" : "Common Stock",
                currency: marketCurrency,
                country: nil,
                providerName: marketProviderRaw
            )
            investment.assetID = resolvedIdentity?.assetID
            if let resolvedIdentity {
                syncCatalogOnMainActorIfNeeded(identity: resolvedIdentity, context: context)
            }
        }
        investment.ensureUniqueID()
        
        context.insert(investment)
    }

    private static func syncCatalogOnMainActorIfNeeded(
        identity: ResolvedAssetIdentity,
        context: ModelContext
    ) {
        if Thread.isMainThread {
            _ = MainActor.assumeIsolated {
                AssetCatalogStore(modelContext: context).syncIfSupported(identity: identity)
            }
            return
        }

        _ = DispatchQueue.main.sync {
            AssetCatalogStore(modelContext: context).syncIfSupported(identity: identity)
        }
    }
}
