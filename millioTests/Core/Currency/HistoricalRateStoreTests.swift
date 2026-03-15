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
    var historicalRatesByPair: [String: Double] = [:]
    private(set) var historicalCalls: Int = 0
    
    func getRate(from: String, to: String) async -> Double? {
        currentRate
    }
    
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        historicalCalls += 1
        if let mapped = historicalRatesByPair["\(from.uppercased())_\(to.uppercased())"] {
            return mapped
        }
        return historicalRate
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
        try context.deleteAll(HistoricalRate.self)
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

    // MARK: - Дополнительные тесты

    @Test("Одинаковые валюты: resolution = .exact, rate = 1.0")
    func testSameCurrencyReturnsExact() async throws {
        let context = try createTestModelContext()
        let mockService = MockHistoricalRateService()

        let store = HistoricalRateStore(modelContext: context, currencyService: mockService)

        let result = await store.getRate(on: Date(), from: "USD", to: "USD")

        #expect(result.rate == 1.0)
        #expect(result.resolution == .exact)
    }

    @Test("Fallback на предыдущий курс при отсутствии точного")
    func testFallbackToPreviousRate() async throws {
        let context = try createTestModelContext()
        let mockService = MockHistoricalRateService()
        mockService.historicalRate = nil // API не возвращает исторический курс

        let today = Calendar.current.startOfDay(for: Date())
        let weekAgo = Calendar.current.startOfDay(for: Date().addingTimeInterval(-7 * 86400))

        // Вставляем курс недельной давности
        let cachedRate = HistoricalRate(
            baseCurrency: "USD",
            quoteCurrency: "RUB",
            rate: 88.0,
            rateDate: weekAgo,
            source: "test"
        )
        context.insert(cachedRate)
        try context.save()

        let store = HistoricalRateStore(modelContext: context, currencyService: mockService)

        // Запрашиваем курс на сегодня — нет точного, берётся предыдущий
        let result = await store.getRate(on: today, from: "USD", to: "RUB")

        #expect(result.rate == 88.0)
        #expect(result.resolution == .previous)
        #expect(result.rateDate == weekAgo)
    }

    @Test("Fallback на текущий курс при отсутствии исторических")
    func testFallbackToCurrentRate() async throws {
        let context = try createTestModelContext()
        let mockService = MockHistoricalRateService()
        mockService.historicalRate = nil // исторических нет
        mockService.currentRate = 92.0 // только текущий

        let weekAgo = Calendar.current.startOfDay(for: Date().addingTimeInterval(-7 * 86400))

        let store = HistoricalRateStore(modelContext: context, currencyService: mockService)

        // Запрашиваем исторический курс — нет ни в кэше, ни в API, fallback на текущий
        let result = await store.getRate(on: weekAgo, from: "USD", to: "RUB")

        #expect(result.rate == 92.0)
        #expect(result.resolution == .current)
        #expect(result.rateDate == nil)
    }

    @Test("Unavailable при отсутствии любых курсов")
    func testUnavailableWhenNoRates() async throws {
        let context = try createTestModelContext()
        let mockService = MockHistoricalRateService()
        mockService.historicalRate = nil
        mockService.currentRate = nil

        let store = HistoricalRateStore(modelContext: context, currencyService: mockService)

        let result = await store.getRate(on: Date(), from: "USD", to: "XYZ")

        #expect(result.rate == nil)
        #expect(result.resolution == .unavailable)
    }

    @Test("Нормализация даты: время отбрасывается")
    func testDateNormalization() async throws {
        let context = try createTestModelContext()
        let mockService = MockHistoricalRateService()
        mockService.historicalRate = nil

        let today = Calendar.current.startOfDay(for: Date())

        // Вставляем курс на начало дня
        let cachedRate = HistoricalRate(
            baseCurrency: "USD",
            quoteCurrency: "EUR",
            rate: 0.92,
            rateDate: today,
            source: "test"
        )
        context.insert(cachedRate)
        try context.save()

        let store = HistoricalRateStore(modelContext: context, currencyService: mockService)

        // Запрашиваем с произвольным временем в тот же день
        let dateWithTime = today.addingTimeInterval(12 * 3600) // +12 часов
        let result = await store.getRate(on: dateWithTime, from: "USD", to: "EUR")

        #expect(result.rate == 0.92)
        #expect(result.resolution == .exact)
    }

    @Test("Prefetch exact-курсов сохраняет запись в кэш")
    func testPrefetchExactRatesStoresCache() async throws {
        let context = try createTestModelContext()
        let mockService = MockHistoricalRateService()
        mockService.historicalRatesByPair["USD_RUB"] = 95.0

        let store = HistoricalRateStore(modelContext: context, currencyService: mockService)
        let date = Date()
        await store.prefetchExactRates(on: [date], pairs: [(from: "USD", to: "RUB")])

        let result = await store.getRate(on: date, from: "USD", to: "RUB")
        #expect(result.rate == 95.0)
        #expect(result.resolution == .exact)
    }

    @Test("Store не повторяет historical lookup для того же miss")
    func testStoreNegativeCachesUnavailableHistoricalRequests() async throws {
        let context = try createTestModelContext()
        let mockService = MockHistoricalRateService()
        mockService.historicalRate = nil
        mockService.currentRate = 92.0

        let store = HistoricalRateStore(modelContext: context, currencyService: mockService)
        let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(-7 * 86400))

        let first = await store.getRate(on: date, from: "CNY", to: "RUB")
        let second = await store.getRate(on: date, from: "CNY", to: "RUB")

        #expect(first.rate == 92.0)
        #expect(first.resolution == .current)
        #expect(second.rate == 92.0)
        #expect(second.resolution == .current)
        #expect(mockService.historicalCalls == 1)
    }
}
