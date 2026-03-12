//
//  InteractiveBackSwipePolicyTests.swift
//  millioTests
//

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
}
