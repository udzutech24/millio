//
//  CashbackLocalizationTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CashbackLocalizationTests {
    @Test("Каталог кешбэк-категорий возвращает разные локализованные имена для en и ru")
    func cashbackCategoriesExposeLocaleSpecificNames() {
        let checks: [CashbackCategory] = [
            .supermarket,
            .education
        ]

        for category in checks {
            let metadata = CashbackCategoryCatalog.metadata(for: category)
            let english = metadata.localizedDisplayName(locale: Locale(identifier: "en"))
            let russian = metadata.localizedDisplayName(locale: Locale(identifier: "ru"))

            #expect(!english.isEmpty)
            #expect(!russian.isEmpty)
            #expect(english != russian)
        }
    }

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
