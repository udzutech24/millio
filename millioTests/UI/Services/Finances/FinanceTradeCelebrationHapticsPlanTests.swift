//
//  FinanceTradeCelebrationHapticsPlanTests.swift
//  millioTests
//

import Testing
@testable import millio

struct FinanceTradeCelebrationHapticsPlanTests {
    @Test("Trade celebration haptics: reduced motion collapses to one success pulse")
    func reducedMotionPlan() {
        let buyPlan = FinanceTradeCelebrationHapticsPlan.events(for: .buy, reduceMotion: true)
        let sellPlan = FinanceTradeCelebrationHapticsPlan.events(for: .sell, reduceMotion: true)

        #expect(buyPlan.count == 1)
        #expect(sellPlan.count == 1)
        #expect(buyPlan[0] == FinanceTradeCelebrationHapticEvent(delayNanoseconds: 0, kind: .successNotification, intensity: 1))
        #expect(sellPlan[0] == FinanceTradeCelebrationHapticEvent(delayNanoseconds: 0, kind: .successNotification, intensity: 1))
    }

    @Test("Trade celebration haptics: buy feels softer and shorter than sell")
    func buyAndSellPlansDiffer() {
        let buyPlan = FinanceTradeCelebrationHapticsPlan.events(for: .buy, reduceMotion: false)
        let sellPlan = FinanceTradeCelebrationHapticsPlan.events(for: .sell, reduceMotion: false)

        #expect(buyPlan.count == 3)
        #expect(sellPlan.count == 4)
        #expect(buyPlan.first?.kind == .softImpact)
        #expect(buyPlan.last?.kind == .successNotification)
        #expect(sellPlan.first?.kind == .rigidImpact)
        #expect(sellPlan.last?.kind == .successNotification)
        #expect((buyPlan.last?.delayNanoseconds ?? 0) < (sellPlan.last?.delayNanoseconds ?? 0))
    }
}
