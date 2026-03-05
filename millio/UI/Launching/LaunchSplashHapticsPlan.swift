//
//  LaunchSplashHapticsPlan.swift
//  millio
//
//  Created by Codex on 05.03.2026.
//

import Foundation

enum LaunchSplashHapticKind: Equatable {
    case mediumImpact
    case rigidImpact
    case strongVibration
    case successNotification
}

struct LaunchSplashHapticEvent: Equatable {
    let delayNanoseconds: UInt64
    let kind: LaunchSplashHapticKind
}

enum LaunchSplashHapticsPlan {
    static func events(reduceMotion: Bool) -> [LaunchSplashHapticEvent] {
        if reduceMotion {
            return [
                LaunchSplashHapticEvent(delayNanoseconds: 0, kind: .strongVibration)
            ]
        }

        return [
            LaunchSplashHapticEvent(delayNanoseconds: 120_000_000, kind: .mediumImpact),
            LaunchSplashHapticEvent(delayNanoseconds: 360_000_000, kind: .rigidImpact),
            LaunchSplashHapticEvent(delayNanoseconds: 460_000_000, kind: .strongVibration),
            LaunchSplashHapticEvent(delayNanoseconds: 780_000_000, kind: .successNotification)
        ]
    }
}
