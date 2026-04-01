//
//  CashbackCategoryCatalogTests.swift
//  millioTests
//
//  Created by Codex on 19.03.2026.
//

import Foundation
import Testing
@testable import millio

@Suite
struct CashbackCategoryCatalogTests {
    @Test("Системная категория супермаркетов локализуется для ru/en/zh-Hans")
    func supermarketDisplayNameUsesThreeLanguageCatalog() {
        let metadata = CashbackCategoryCatalog.metadata(for: .supermarket)

        #expect(metadata.localizedDisplayName(locale: Locale(identifier: "ru_RU")) == "Продукты")
        #expect(metadata.localizedDisplayName(locale: Locale(identifier: "en_US")) == "Groceries")
        #expect(metadata.localizedDisplayName(locale: Locale(identifier: "zh-Hans")) == "商超购物")
    }

    @Test("Поиск категорий не зависит от ручного RU/EN ветвления")
    func categorySearchUsesLocalizedCatalogNames() {
        #expect(
            CashbackCategoryCatalog.matchesSearch(
                rawValue: CashbackCategory.supermarket.rawValue,
                query: "商超",
                locale: Locale(identifier: "zh-Hans")
            )
        )
        #expect(
            CashbackCategoryCatalog.matchesSearch(
                rawValue: CashbackCategory.gasStation.rawValue,
                query: "заправки",
                locale: Locale(identifier: "en_US")
            )
        )
    }

    @Test("Частичный запрос по компьютерам даёт релевантные иконки для кэшбэка")
    func suggestedIconsPreferComputerIconsForPartialComputerQuery() {
        let suggestions = CashbackCategoryCatalog.suggestedIcons(for: "Компью")

        #expect(!suggestions.isEmpty)
        #expect(suggestions.contains("💻"))
        #expect(suggestions.contains("🖥️"))
    }

    @Test("Неполное слово пиццы даёт релевантную рекомендацию для кэшбэка")
    func suggestedIconsPreferPizzaForPartialPizzaQuery() {
        let suggestions = CashbackCategoryCatalog.suggestedIcons(for: "Пицц")

        #expect(!suggestions.isEmpty)
        #expect(suggestions.prefix(3).contains("🍕"))
    }

    @Test("Рекомендации кэшбэка учитывают все слова в названии категории")
    func suggestedIconsUseAllWordsInQuery() {
        let suggestions = CashbackCategoryCatalog.suggestedIcons(for: "доставка роллов домой")

        #expect(!suggestions.isEmpty)
        #expect(suggestions.prefix(3).contains("🍣"))
    }
}
