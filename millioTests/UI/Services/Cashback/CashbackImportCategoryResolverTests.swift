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
        #expect(resolver.resolveSystemCategoryRaw(for: "Все покупки") == CashbackCategory.allPurchases.rawValue)
    }

    @Test("Резолвер маппит очевидные банковские категории в системные")
    func testResolveSystemCategoryRawMapsObviousNames() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Продукты") == CashbackCategory.supermarket.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Супермаркеты") == CashbackCategory.supermarket.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Рестораны") == CashbackCategory.restaurant.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Топливо и АЗС") == CashbackCategory.gasStation.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Транспорт") == CashbackCategory.transport.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Дом и ремонт") == CashbackCategory.homeRepair.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Детские товары") == CashbackCategory.kids.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Такси") == CashbackCategory.taxi.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Медицинские клиники") == CashbackCategory.healthcare.rawValue)
    }

    @Test("Резолвер маппит очевидные англоязычные категории в системные")
    func testResolveSystemCategoryRawMapsObviousEnglishNames() {
        #expect(resolver.resolveSystemCategoryRaw(for: "All purchases") == CashbackCategory.allPurchases.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Supermarkets") == CashbackCategory.supermarket.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Restaurants") == CashbackCategory.restaurant.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Fuel and Gas Stations") == CashbackCategory.gasStation.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Hotels") == CashbackCategory.hotels.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Electronics") == CashbackCategory.electronics.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Medical clinics") == CashbackCategory.healthcare.rawValue)
    }

    @Test("Неочевидные категории остаются без маппинга")
    func testResolveSystemCategoryRawKeepsUnknownAsNil() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Полис ОСАГО") == nil)
    }

    @Test("Банковские ярлыки маппятся в канонические категории для иконок и избранного")
    func testResolveSystemCategoryRawMapsBankAliases() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Яндекс Лавка") == CashbackCategory.supermarket.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Лавка") == CashbackCategory.supermarket.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Комфорт") == CashbackCategory.taxi.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Комфорт+") == CashbackCategory.taxi.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Ultima") == CashbackCategory.taxi.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Цветы") == CashbackCategory.flowersGifts.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Цветы и подарки") == CashbackCategory.flowersGifts.rawValue)
    }

    @Test("Импорт остаётся консервативным для тарифных ярлыков такси")
    func testResolveSystemCategoryRawForImportKeepsTaxiTariffsCustom() {
        #expect(resolver.resolveSystemCategoryRawForImport("Комфорт") == nil)
        #expect(resolver.resolveSystemCategoryRawForImport("Комфорт+") == nil)
        #expect(resolver.resolveSystemCategoryRawForImport("Ultima") == nil)
        #expect(resolver.resolveSystemCategoryRawForImport("Яндекс Такси") == CashbackCategory.taxi.rawValue)
    }
}
