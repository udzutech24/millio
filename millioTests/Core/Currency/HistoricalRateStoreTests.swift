//
//  HistoricalRateStoreTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 29.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@MainActor
final class MockHistoricalRateService: CurrencyRateServiceProtocol {
    var historicalRate: Double?
    var currentRate: Double?
    
    func getRate(from: String, to: String) async -> Double? {
        currentRate
    }
    
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        historicalRate
    }
    
    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }
    
    func forceRefreshRates() async {}
}

@Suite(.serialized)
@MainActor
struct HistoricalRateStoreTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([HistoricalRate.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
    
    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.delete(model: HistoricalRate.self)
        try context.save()
        return context
    }
    
    @Test("Исторический курс сохраняется в кэш после получения")
    func testHistoricalRateIsStored() async throws {
        let modelContext = try createTestModelContext()
        let mockService = MockHistoricalRateService()
        mockService.historicalRate = 90.0
        
        let store = HistoricalRateStore(modelContext: modelContext, currencyService: mockService)
        let date = Date()
        
        let result = await store.getRate(on: date, from: "USD", to: "RUB")
        #expect(result.rate == 90.0)
        #expect(result.resolution == .exact)
        
        let descriptor = FetchDescriptor<HistoricalRate>()
        let rates = (try? modelContext.fetch(descriptor)) ?? []
        #expect(rates.count == 1)
        #expect(rates.first?.rate == 90.0)
    }
    
    @Test("Инвертирование курса работает для обратной пары")
    func testInverseRateLookup() async throws {
        let modelContext = try createTestModelContext()
        let store = HistoricalRateStore(modelContext: modelContext, currencyService: MockHistoricalRateService())
        
        let date = Calendar.current.startOfDay(for: Date())
        let rate = HistoricalRate(
            baseCurrency: "RUB",
            quoteCurrency: "USD",
            rate: 0.01,
            rateDate: date,
            source: "test"
        )
        modelContext.insert(rate)
        try modelContext.save()
        
        let result = await store.getRate(on: date, from: "USD", to: "RUB")
        #expect(result.rate == 100.0)
        #expect(result.resolution == .exact)
    }
}
