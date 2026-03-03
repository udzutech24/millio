//
//  CashbackCardPickerRecommendationPrefsTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CashbackCardPickerRecommendationPrefsTests {
    @Test("По умолчанию рекомендация не скрыта")
    func testDefaultsToVisible() {
        let defaults = UserDefaults(suiteName: "CashbackCardPickerRecommendationPrefsTests.default")!
        defaults.removePersistentDomain(forName: "CashbackCardPickerRecommendationPrefsTests.default")
        let prefs = CashbackCardPickerRecommendationPrefs(defaults: defaults)

        #expect(prefs.isHidden() == false)
    }

    @Test("Скрытие рекомендации сохраняется")
    func testSetHiddenPersistsValue() {
        let suiteName = "CashbackCardPickerRecommendationPrefsTests.persist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = CashbackCardPickerRecommendationPrefs(defaults: defaults)

        prefs.setHidden(true)

        #expect(prefs.isHidden())
    }
}

