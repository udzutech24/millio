//
//  CashbackLocalizationTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

struct CashbackLocalizationTests {
    @Test("Системные категории кешбэка резолвятся через ключи локализации")
    func cashbackCategoriesAreLocalized() {
        let checks: [(CashbackCategory, String)] = [
            (.allPurchases, "cashback.category.all_purchases"),
            (.gasStation, "cashback.category.gas_station"),
            (.supermarket, "cashback.category.supermarket"),
            (.restaurant, "cashback.category.restaurant"),
            (.other, "cashback.category.other")
        ]

        for (category, key) in checks {
            let localized = category.displayName
            #expect(localized == NSLocalizedString(key, comment: ""))
            #expect(localized != key)
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
            #expect(error.errorDescription == NSLocalizedString(key, comment: ""))
            #expect(error.errorDescription != key)
        }
    }
}
