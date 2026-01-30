//
//  HistoricalRateStore.swift
//  millio
//
//  Created by Александр Сидоркин on 29.01.2026.
//

import Foundation
import SwiftData

enum HistoricalRateResolution {
    case exact
    case previous
    case current
    case unavailable
}

struct HistoricalRateResult {
    let rate: Double?
    let resolution: HistoricalRateResolution
    let rateDate: Date?
}

/// Хранилище исторических курсов с кэшем в SwiftData
@MainActor
final class HistoricalRateStore {
    private let modelContext: ModelContext
    private let currencyService: CurrencyRateServiceProtocol
    
    init(
        modelContext: ModelContext,
        currencyService: CurrencyRateServiceProtocol
    ) {
        self.modelContext = modelContext
        self.currencyService = currencyService
    }

    convenience init(modelContext: ModelContext) {
        self.init(modelContext: modelContext, currencyService: CurrencyRateService.shared)
    }
    
    func getRate(on date: Date, from: String, to: String) async -> HistoricalRateResult {
        let base = from.uppercased()
        let quote = to.uppercased()
        
        if base == quote {
            return HistoricalRateResult(rate: 1.0, resolution: .exact, rateDate: normalizedDate(date))
        }
        
        let targetDate = normalizedDate(date)
        
        if let cached = fetchExactRate(base: base, quote: quote, date: targetDate) {
            return HistoricalRateResult(rate: cached.rate, resolution: .exact, rateDate: cached.rateDate)
        }
        if let cachedInverse = fetchExactRate(base: quote, quote: base, date: targetDate) {
            return HistoricalRateResult(rate: 1.0 / cachedInverse.rate, resolution: .exact, rateDate: cachedInverse.rateDate)
        }
        
        if let fetched = await currencyService.getHistoricalRate(on: targetDate, from: base, to: quote) {
            upsertRate(base: base, quote: quote, rate: fetched, date: targetDate, source: "historical")
            return HistoricalRateResult(rate: fetched, resolution: .exact, rateDate: targetDate)
        }
        
        if let previous = fetchLatestBefore(base: base, quote: quote, date: targetDate) {
            return HistoricalRateResult(rate: previous.rate, resolution: .previous, rateDate: previous.rateDate)
        }
        if let previousInverse = fetchLatestBefore(base: quote, quote: base, date: targetDate) {
            return HistoricalRateResult(rate: 1.0 / previousInverse.rate, resolution: .previous, rateDate: previousInverse.rateDate)
        }
        
        if let current = await currencyService.getRate(from: base, to: quote) {
            return HistoricalRateResult(rate: current, resolution: .current, rateDate: nil)
        }
        
        return HistoricalRateResult(rate: nil, resolution: .unavailable, rateDate: nil)
    }
    
    private func normalizedDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
    
    private func fetchExactRate(base: String, quote: String, date: Date) -> HistoricalRate? {
        let descriptor = FetchDescriptor<HistoricalRate>(
            predicate: #Predicate<HistoricalRate> { rate in
                rate.baseCurrency == base &&
                rate.quoteCurrency == quote &&
                rate.rateDate == date
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    private func fetchLatestBefore(base: String, quote: String, date: Date) -> HistoricalRate? {
        var descriptor = FetchDescriptor<HistoricalRate>(
            predicate: #Predicate<HistoricalRate> { rate in
                rate.baseCurrency == base &&
                rate.quoteCurrency == quote &&
                rate.rateDate < date
            },
            sortBy: [SortDescriptor(\.rateDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
    
    private func upsertRate(base: String, quote: String, rate: Double, date: Date, source: String) {
        if let existing = fetchExactRate(base: base, quote: quote, date: date) {
            existing.rate = rate
            existing.source = source
            existing.fetchedAt = Date()
            do {
                try modelContext.save()
            } catch {
                AppLogger.log(.error, category: "HistoricalRateStore", "Failed to save historical rate: \(error.localizedDescription)")
            }
            return
        }
        
        let newRate = HistoricalRate(
            baseCurrency: base,
            quoteCurrency: quote,
            rate: rate,
            rateDate: date,
            source: source,
            fetchedAt: Date()
        )
        modelContext.insert(newRate)
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "HistoricalRateStore", "Failed to save historical rate: \(error.localizedDescription)")
        }
    }
}
