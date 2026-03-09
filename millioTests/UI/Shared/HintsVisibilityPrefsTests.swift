//
//  HintsVisibilityPrefsTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import Foundation
import Testing
@testable import millio

struct HintsVisibilityPrefsTests {
    @Test("Prefs: по умолчанию подсказка не скрыта")
    func defaultIsNotHidden() {
        let suite = "HintsVisibilityPrefsTests.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let prefs = HintsVisibilityPrefs(key: "finances.overview.ledger", defaults: defaults)
        #expect(prefs.isHidden == false)
    }

    @Test("Prefs: setHidden(true) сохраняет скрытие")
    func setHiddenPersistsTrue() {
        let suite = "HintsVisibilityPrefsTests.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let prefs = HintsVisibilityPrefs(key: "finances.overview.ledger", defaults: defaults)
        prefs.setHidden(true)

        let restored = HintsVisibilityPrefs(key: "finances.overview.ledger", defaults: defaults)
        #expect(restored.isHidden == true)
    }
}

