//
//  BudgetThresholdHapticsPlanTests.swift
//  millioTests
//
//  Created by Codex on 14.03.2026.
//

import Testing
@testable import millio

struct BudgetThresholdHapticsPlanTests {
    @Test("Budget haptic step only advances after thresholds")
    func hapticStepsMatchThresholds() {
        #expect(BudgetThresholdHapticsPlan.step(for: -0.1) == -1)
        #expect(BudgetThresholdHapticsPlan.step(for: 0.69) == -1)
        #expect(BudgetThresholdHapticsPlan.step(for: 0.7) == 0)
        #expect(BudgetThresholdHapticsPlan.step(for: 0.95) == 1)
        #expect(BudgetThresholdHapticsPlan.step(for: 1.0) == 2)
        #expect(BudgetThresholdHapticsPlan.step(for: 1.5) == 2)
    }
}
