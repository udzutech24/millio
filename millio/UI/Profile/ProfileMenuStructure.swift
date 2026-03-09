//
//  ProfileMenuStructure.swift
//  millio
//
//  Created by Codex on 06.03.2026.
//

import SwiftUI

enum ProfileMenuSectionID: String, Identifiable {
    case general
    case settings
    case experience
    case support
    case about
    case contacts
    case debug

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .general:
            return "profile.section.general"
        case .settings:
            return "profile.section.settings"
        case .experience:
            return "profile.section.experience"
        case .support:
            return "profile.section.support"
        case .about:
            return "profile.section.about"
        case .contacts:
            return "profile.section.contacts"
        case .debug:
            return "profile.section.debug"
        }
    }
}

enum ProfileMenuItemID: String, Identifiable {
    case language
    case primaryCurrency
    case backup
    case security
    case dailyReminders
    case quickSetup
    case launchSplash
    case faq
    case smartDataReset
    case version
    case privacy
    case terms
    case contactUs
    case rateApp
    case premiumAccess
    case trialDisabled
    case premiumDiagnostics
    case showOnboarding

    var id: String { rawValue }
}

struct ProfileMenuSection: Identifiable, Equatable {
    let id: ProfileMenuSectionID
    let items: [ProfileMenuItemID]
}

enum ProfileMenuStructure {
    // Keep section grouping in one place so screen order stays testable.
    static let sections: [ProfileMenuSection] = [
        ProfileMenuSection(
            id: .general,
            items: [
                .language,
                .primaryCurrency
            ]
        ),
        ProfileMenuSection(
            id: .settings,
            items: [
                .backup,
                .security,
                .dailyReminders
            ]
        ),
        ProfileMenuSection(
            id: .experience,
            items: [
                .quickSetup,
                .launchSplash
            ]
        ),
        ProfileMenuSection(
            id: .support,
            items: [
                .faq,
                .smartDataReset
            ]
        ),
        ProfileMenuSection(
            id: .about,
            items: [
                .version,
                .privacy,
                .terms
            ]
        ),
        ProfileMenuSection(
            id: .debug,
            items: [
                .premiumAccess,
                .trialDisabled,
                .premiumDiagnostics,
                .showOnboarding
            ]
        ),
        ProfileMenuSection(
            id: .contacts,
            items: [
                .contactUs,
                .rateApp
            ]
        )
    ]
}
