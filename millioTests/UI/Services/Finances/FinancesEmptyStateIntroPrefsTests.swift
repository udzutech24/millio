//
//  FinancesEmptyStateIntroPrefsTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct FinancesEmptyStateIntroPrefsTests {
    @Test("По умолчанию onboarding в пустом состоянии Финансов видим")
    func defaultsToVisible() {
        let suiteName = "FinancesEmptyStateIntroPrefsTests.default"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = FinancesEmptyStateIntroPrefs(defaults: defaults)

        #expect(prefs.isHidden() == false)
    }

    @Test("Скрытие onboarding в пустом состоянии сохраняется")
    func setHiddenPersistsValue() {
        let suiteName = "FinancesEmptyStateIntroPrefsTests.persist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = FinancesEmptyStateIntroPrefs(defaults: defaults)

        prefs.setHidden(true)

        #expect(prefs.isHidden())
    }
}
