//
//  ProfileMenuStructure.swift
//  millio
//
//  Created by Codex on 06.03.2026.
//

import SwiftUI

enum ProfileMenuIconTone: String {
    case blue
    case cyan
    case green
    case orange
    case purple
    case pink
    case red
    case gray
    case teal
}

enum ProfileMenuSectionID: String, Identifiable {
    case general
    case settings
    case experience
    case support
    case about
    case contacts
    case debug

    var id: String { rawValue }

    var localizationKey: String {
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

    var fallbackTitle: String {
        switch self {
        case .general:
            return "General"
        case .settings:
            return "Settings"
        case .experience:
            return "Experience"
        case .support:
            return "Support & tools"
        case .about:
            return "About"
        case .contacts:
            return "Contacts"
        case .debug:
            return "Debug"
        }
    }

    var titleKey: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
    }
}

enum ProfileMenuItemID: String, Identifiable {
    case language
    case primaryCurrency
    case rateSource
    case backup
    case googleSheets
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
    case premiumAccess
    case trialDisabled
    case premiumDiagnostics
    case showOnboarding
#if DEBUG
    case adminStats
#endif

    var id: String { rawValue }

    var iconSystemName: String {
        switch self {
        case .language:
            return "globe"
        case .primaryCurrency:
            return "dollarsign"
        case .rateSource:
            return "arrow.triangle.2.circlepath"
        case .backup:
            return "arrow.clockwise.icloud"
        case .googleSheets:
            return "tablecells"
        case .security:
            return "lock.shield"
        case .dailyReminders:
            return "bell"
        case .quickSetup:
            return "sparkles.rectangle.stack"
        case .launchSplash:
            return "sparkles.tv"
        case .faq:
            return "questionmark.circle"
        case .smartDataReset:
            return "trash"
        case .version:
            return "info.circle"
        case .privacy:
            return "hand.raised"
        case .terms:
            return "doc.text"
        case .contactUs:
            return "message"
        case .premiumAccess:
            return "crown"
        case .trialDisabled:
            return "pause.circle"
        case .premiumDiagnostics:
            return "flag"
        case .showOnboarding:
            return "sparkles"
#if DEBUG
        case .adminStats:
            return "chart.bar.xaxis"
#endif
        }
    }

    var iconTone: ProfileMenuIconTone {
        switch self {
        case .language:
            return .blue
        case .primaryCurrency:
            return .green
        case .rateSource:
            return .teal
        case .backup:
            return .cyan
        case .googleSheets:
            return .green
        case .security:
            return .green
        case .dailyReminders:
            return .orange
        case .quickSetup:
            return .purple
        case .launchSplash:
            return .pink
        case .faq:
            return .blue
        case .smartDataReset:
            return .red
        case .version:
            return .cyan
        case .privacy:
            return .orange
        case .terms:
            return .blue
        case .contactUs:
            return .teal
        case .premiumAccess:
            return .orange
        case .trialDisabled:
            return .pink
        case .premiumDiagnostics:
            return .purple
        case .showOnboarding:
            return .cyan
#if DEBUG
        case .adminStats:
            return .teal
#endif
        }
    }
}

struct ProfileMenuSection: Identifiable, Equatable {
    let id: ProfileMenuSectionID
    let items: [ProfileMenuItemID]
}

enum ProfileMenuStructure {
    static let debugItems: [ProfileMenuItemID] = {
        var items: [ProfileMenuItemID] = [
            .premiumAccess,
            .trialDisabled,
            .premiumDiagnostics,
            .showOnboarding,
            .smartDataReset
        ]
#if DEBUG
        items.append(.adminStats)
#endif
        return items
    }()

    // Keep section grouping in one place so screen order stays testable.
    static let sections: [ProfileMenuSection] = {
        var sections: [ProfileMenuSection] = [
            ProfileMenuSection(
                id: .general,
                items: [
                    .language,
                    .primaryCurrency,
                    .rateSource
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
                    .faq
                ]
            ),
            ProfileMenuSection(
                id: .about,
                items: [
                    .version,
                    .privacy,
                    .terms
                ]
            )
        ]
#if DEBUG
        sections.append(
            ProfileMenuSection(
                id: .debug,
                items: debugItems
            )
        )
#endif
        sections.append(
            ProfileMenuSection(
                id: .contacts,
                items: [
                    .contactUs
                ]
            )
        )
        return sections
    }()
}
