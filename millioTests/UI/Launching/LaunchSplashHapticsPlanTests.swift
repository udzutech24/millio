//
//  LaunchSplashHapticsPlanTests.swift
//  millioTests
//
//  Created by Codex on 05.03.2026.
//

import Testing
@testable import millio

struct LaunchSplashHapticsPlanTests {
    @Test("Splash haptics: reduced motion uses strong vibration")
    func reducedMotionPlan() {
        let plan = LaunchSplashHapticsPlan.events(reduceMotion: true)

        #expect(plan.count == 1)
        #expect(plan[0] == LaunchSplashHapticEvent(delayNanoseconds: 0, kind: .strongVibration))
    }

    @Test("Splash haptics: default plan uses four staged events")
    func defaultPlan() {
        let plan = LaunchSplashHapticsPlan.events(reduceMotion: false)

        #expect(plan.count == 4)
        #expect(plan[0] == LaunchSplashHapticEvent(delayNanoseconds: 120_000_000, kind: .mediumImpact))
        #expect(plan[1] == LaunchSplashHapticEvent(delayNanoseconds: 360_000_000, kind: .rigidImpact))
        #expect(plan[2] == LaunchSplashHapticEvent(delayNanoseconds: 460_000_000, kind: .strongVibration))
        #expect(plan[3] == LaunchSplashHapticEvent(delayNanoseconds: 780_000_000, kind: .successNotification))
    }
}
