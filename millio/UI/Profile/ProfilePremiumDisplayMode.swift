//
//  ProfilePremiumDisplayMode.swift
//  millio
//
//  Created by Codex on 26.03.2026.
//

import Foundation

/// Keeps Profile premium presentation logic explicit: upsell stays promotional
/// only while the user does not have premium access yet.
enum ProfilePremiumDisplayMode: Equatable {
    case promotional
    case compact(ProfilePremiumCompactStatus)

    static func resolve(for accessSource: SubscriptionAccessSource) -> Self {
        switch accessSource {
        case .free:
            return .promotional
        case .trial:
            return .compact(.trial)
        case .subscription, .debug:
            return .compact(.enabled)
        }
    }
}

enum ProfilePremiumCompactStatus: Equatable {
    case trial
    case enabled

    var localizationKey: String {
        switch self {
        case .trial:
            return "profile.premium.status.trial"
        case .enabled:
            return "profile.status.enabled"
        }
    }
}
