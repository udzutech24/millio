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
        profileTitle(locale: Locale.current)
    }

    func profileTitle(locale: Locale) -> String {
        switch self {
        case .always:
            return AppLocalization.string("profile.launch_splash.mode.always", locale: locale)
        case .oncePerDay:
            return AppLocalization.string("profile.launch_splash.mode.once_per_day", locale: locale)
        case .disabled:
            return AppLocalization.string("profile.launch_splash.mode.off", locale: locale)
        }
    }
}

protocol LaunchSplashPreferences: AnyObject {
    var launchSplashDisplayMode: LaunchSplashDisplayMode { get set }
    var lastLaunchSplashShownAt: Date? { get set }
}
