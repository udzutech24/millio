//
//  FinanceDynamicsEstimatedRateWarningPrefsTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct FinanceDynamicsEstimatedRateWarningPrefsTests {
    @Test("По умолчанию предупреждение не скрыто")
    func testDefaultsToVisible() {
        let suiteName = "FinanceDynamicsEstimatedRateWarningPrefsTests.default"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = FinanceDynamicsEstimatedRateWarningPrefs(defaults: defaults)

        #expect(prefs.isHidden() == false)
    }

    @Test("Скрытие предупреждения сохраняется")
    func testSetHiddenPersistsValue() {
        let suiteName = "FinanceDynamicsEstimatedRateWarningPrefsTests.persist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let prefs = FinanceDynamicsEstimatedRateWarningPrefs(defaults: defaults)

        prefs.setHidden(true)

        #expect(prefs.isHidden())
    }
}
