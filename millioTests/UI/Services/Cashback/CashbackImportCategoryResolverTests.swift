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

    @Test("Резолвер маппит очевидные банковские категории в системные")
    func testResolveSystemCategoryRawMapsObviousNames() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Супермаркеты") == CashbackCategory.supermarket.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Рестораны") == CashbackCategory.restaurant.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Топливо и АЗС") == CashbackCategory.gasStation.rawValue)
        #expect(resolver.resolveSystemCategoryRaw(for: "Транспорт") == CashbackCategory.transport.rawValue)
    }

    @Test("Неочевидные категории остаются без маппинга")
    func testResolveSystemCategoryRawKeepsUnknownAsNil() {
        #expect(resolver.resolveSystemCategoryRaw(for: "Авиабилеты") == nil)
        #expect(resolver.resolveSystemCategoryRaw(for: "Медицинские клиники") == nil)
        #expect(resolver.resolveSystemCategoryRaw(for: "Красота") == nil)
    }
}
