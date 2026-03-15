//
//  CashbackLocalizationTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

struct CashbackLocalizationTests {
    @Test("Системные категории кешбэка резолвятся через локализованный каталог")
    func cashbackCategoriesAreLocalized() {
        let checks: [CashbackCategory] = [
            .allPurchases,
            .gasStation,
            .supermarket,
            .restaurant,
            .other
        ]

        for category in checks {
            let localized = category.displayName
            let expected = CashbackCategoryCatalog.metadata(for: category).localizedDisplayName()
            #expect(localized == expected)
            #expect(!localized.isEmpty)
        }
    }

    @Test("Ошибки импорта cashback используют локализацию")
    func cashbackImportErrorsAreLocalized() {
        let checks: [(CashbackScreenshotImportError, String)] = [
            (.invalidImage, "cashback.import.error.invalid_image"),
            (.noTextFound, "cashback.import.error.no_text"),
            (.noCashbackLinesFound, "cashback.import.error.no_cashback_lines")
        ]

        for (error, key) in checks {
            let expected = String(localized: String.LocalizationValue(key))
            #expect(error.errorDescription == expected)
            #expect(error.errorDescription != key)
        }
    }
}
