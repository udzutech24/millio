//
//  LaunchSplashDisplayMode.swift
//  millio
//
//  Created by Codex on 05.03.2026.
//

import Foundation

enum LaunchSplashDisplayMode: String, CaseIterable {
    case always
    case oncePerDay
    case disabled

    var profileTitle: String {
        switch self {
        case .always:
            return "Always"
        case .oncePerDay:
            return "Once per day"
        case .disabled:
            return "Off"
        }
    }
}

protocol LaunchSplashPreferences: AnyObject {
    var launchSplashDisplayMode: LaunchSplashDisplayMode { get set }
    var lastLaunchSplashShownAt: Date? { get set }
}
