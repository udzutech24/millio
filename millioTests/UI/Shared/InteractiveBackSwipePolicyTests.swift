//
//  InteractiveBackSwipePolicyTests.swift
//  millioTests
//

import CoreGraphics
import Testing
@testable import millio

struct InteractiveBackSwipePolicyTests {
    @Test("Жест назад включается только для экранов не в корне стека")
    func enablesGestureOnlyForNestedScreens() {
        #expect(InteractiveBackSwipePolicy.shouldEnableGesture(isEnabled: true, navigationStackDepth: 2))
        #expect(InteractiveBackSwipePolicy.shouldEnableGesture(isEnabled: true, navigationStackDepth: 5))
        #expect(!InteractiveBackSwipePolicy.shouldEnableGesture(isEnabled: true, navigationStackDepth: 1))
        #expect(!InteractiveBackSwipePolicy.shouldEnableGesture(isEnabled: true, navigationStackDepth: 0))
    }

    @Test("Отключённый флаг всегда запрещает жест назад")
    func respectsExplicitDisableFlag() {
        #expect(!InteractiveBackSwipePolicy.shouldEnableGesture(isEnabled: false, navigationStackDepth: 2))
        #expect(!InteractiveBackSwipePolicy.shouldEnableGesture(isEnabled: false, navigationStackDepth: 8))
    }

    @Test("Жест начинается только для уверенного свайпа вправо")
    func startsOnlyForRightDominantVelocity() {
        #expect(InteractiveBackSwipePolicy.shouldBeginGesture(velocity: CGPoint(x: 600, y: 40)))
        #expect(!InteractiveBackSwipePolicy.shouldBeginGesture(velocity: CGPoint(x: -600, y: 20)))
        #expect(!InteractiveBackSwipePolicy.shouldBeginGesture(velocity: CGPoint(x: 220, y: 400)))
    }
}
