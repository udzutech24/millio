//
//  FinanceTradeCelebrationHapticsPlan.swift
//  millio
//

import Foundation

enum FinanceTradeCelebrationHapticKind: Equatable {
    case softImpact
    case lightImpact
    case mediumImpact
    case rigidImpact
    case successNotification
}

struct FinanceTradeCelebrationHapticEvent: Equatable {
    let delayNanoseconds: UInt64
    let kind: FinanceTradeCelebrationHapticKind
    let intensity: Double
}

enum FinanceTradeCelebrationHapticsPlan {
    static func events(
        for side: InvestmentOrderSide,
        reduceMotion: Bool
    ) -> [FinanceTradeCelebrationHapticEvent] {
        if reduceMotion {
            return [
                FinanceTradeCelebrationHapticEvent(
                    delayNanoseconds: 0,
                    kind: .successNotification,
                    intensity: 1
                )
            ]
        }

        switch side {
        case .buy:
            return [
                FinanceTradeCelebrationHapticEvent(
                    delayNanoseconds: 40_000_000,
                    kind: .softImpact,
                    intensity: 0.52
                ),
                FinanceTradeCelebrationHapticEvent(
                    delayNanoseconds: 180_000_000,
                    kind: .mediumImpact,
                    intensity: 0.82
                ),
                FinanceTradeCelebrationHapticEvent(
                    delayNanoseconds: 340_000_000,
                    kind: .successNotification,
                    intensity: 1
                )
            ]
        case .sell:
            return [
                FinanceTradeCelebrationHapticEvent(
                    delayNanoseconds: 30_000_000,
                    kind: .rigidImpact,
                    intensity: 0.72
                ),
                FinanceTradeCelebrationHapticEvent(
                    delayNanoseconds: 150_000_000,
                    kind: .mediumImpact,
                    intensity: 0.68
                ),
                FinanceTradeCelebrationHapticEvent(
                    delayNanoseconds: 300_000_000,
                    kind: .lightImpact,
                    intensity: 0.48
                ),
                FinanceTradeCelebrationHapticEvent(
                    delayNanoseconds: 430_000_000,
                    kind: .successNotification,
                    intensity: 1
                )
            ]
        }
    }
}
