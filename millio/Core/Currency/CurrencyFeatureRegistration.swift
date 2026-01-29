//
//  CurrencyFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 29.01.2026.
//

import Foundation
import SwiftData

/// Регистрация моделей валют для backup/restore
struct CurrencyFeatureRegistration {
    static func register() {
        ModelTypeRegistry.shared.register(HistoricalRate.self, typeName: "HistoricalRate")
        ModelTypeRegistry.shared.registerImporter(HistoricalRateImporter.self)
    }
}

// MARK: - Historical Rate Importer

struct HistoricalRateImporter: ModelImporter {
    static func importType() -> String {
        "HistoricalRate"
    }
    
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let baseCurrency = data["baseCurrency"] as? String,
              let quoteCurrency = data["quoteCurrency"] as? String,
              let rate = data["rate"] as? Double,
              let rateDateTimestamp = data["rateDate"] as? TimeInterval,
              let source = data["source"] as? String,
              let fetchedAtTimestamp = data["fetchedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        let rateDate = Date(timeIntervalSince1970: rateDateTimestamp)
        let fetchedAt = Date(timeIntervalSince1970: fetchedAtTimestamp)
        
        let descriptor = FetchDescriptor<HistoricalRate>(
            predicate: #Predicate<HistoricalRate> { item in
                item.baseCurrency == baseCurrency &&
                item.quoteCurrency == quoteCurrency &&
                item.rateDate == rateDate
            }
        )
        
        if let existing = try? context.fetch(descriptor).first {
            existing.rate = rate
            existing.source = source
            existing.fetchedAt = fetchedAt
            return
        }
        
        let historicalRate = HistoricalRate(
            baseCurrency: baseCurrency,
            quoteCurrency: quoteCurrency,
            rate: rate,
            rateDate: rateDate,
            source: source,
            fetchedAt: fetchedAt
        )
        
        context.insert(historicalRate)
    }
}
