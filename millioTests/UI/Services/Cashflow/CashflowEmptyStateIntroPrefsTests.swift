//
//  CashflowEmptyStateIntroPrefsTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CashflowEmptyStateIntroPrefsTests {
    @Test("По умолчанию onboarding в пустом состоянии Cashflow видим")
    func defaultsToVisible() {
        let suiteName = "CashflowEmptyStateIntroPrefsTests.default"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = CashflowEmptyStateIntroPrefs(defaults: defaults)

        #expect(prefs.isHidden() == false)
    }

    @Test("Скрытие onboarding в Cashflow сохраняется")
    func setHiddenPersistsValue() {
        let suiteName = "CashflowEmptyStateIntroPrefsTests.persist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = CashflowEmptyStateIntroPrefs(defaults: defaults)

        prefs.setHidden(true)

        #expect(prefs.isHidden())
    }
}
