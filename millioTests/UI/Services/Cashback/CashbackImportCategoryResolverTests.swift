//
//  CashbackImportCategoryResolverTests.swift
//  millioTests
//
//  Created by Codex on 26.02.2026.
//

import Testing
@testable import millio

struct CashbackImportCategoryResolverTests {
    private let resolver = CashbackImportCategoryResolver()

    @Test("Точное совпадение с системной категорией маппится в системный raw")
    func testResolveSystemCategoryRawMapsExactSystemNames() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Авиабилеты") == CashbackCategory.airlines.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Красота") == CashbackCategory.beauty.rawValue)
    }

    @Test("Резолвер маппит очевидные банковские категории в системные")
    func testResolveSystemCategoryRawMapsObviousNames() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Супермаркеты") == CashbackCategory.supermarket.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Рестораны") == CashbackCategory.restaurant.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Топливо и АЗС") == CashbackCategory.gasStation.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Транспорт") == CashbackCategory.transport.rawValue)
    }

    @Test("Резолвер маппит очевидные англоязычные категории в системные")
    func testResolveSystemCategoryRawMapsObviousEnglishNames() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Supermarkets") == CashbackCategory.supermarket.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Restaurants") == CashbackCategory.restaurant.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Fuel and Gas Stations") == CashbackCategory.gasStation.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Hotels") == CashbackCategory.hotels.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Electronics") == CashbackCategory.electronics.rawValue)
    }

    @Test("Неочевидные категории остаются без маппинга")
    func testResolveSystemCategoryRawKeepsUnknownAsNil() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Медицинские клиники") == nil)
        #expect(resolver.resolveSystemCategoryRaw(for: "Яндекс Лавка") == nil)
        #expect(resolver.resolveSystemCategoryRaw(for: "Полис ОСАГО") == nil)
    }

    @Test("Тарифы такси не схлопываются в системный транспорт")
    func testResolveSystemCategoryRawKeepsTaxiTariffsAsCustom() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Комфорт") == nil)
        #expect(resolver.resolveSystemCategoryRaw(for: "Комфорт+") == nil)
        #expect(resolver.resolveSystemCategoryRaw(for: "Ultima") == nil)
        #expect(resolver.resolveSystemCategoryRaw(for: "Яндекс Такси Комфорт") == nil)
    }
}
