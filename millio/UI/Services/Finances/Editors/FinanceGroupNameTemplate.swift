//
//  FinanceGroupNameTemplate.swift
//  millio
//

import Foundation

/// One-tap presets for a Finance Group name on the group creation screen.
enum FinanceGroupNameTemplate: String, CaseIterable, Identifiable {
    case debitCards
    case stocks
    case myRealEstate
    case credits
    case deposits
    case foreignCards

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .debitCards:
            "finances.group_editor.name_template.debit_cards"
        case .stocks:
            "finances.group_editor.name_template.stocks"
        case .myRealEstate:
            "finances.group_editor.name_template.my_real_estate"
        case .credits:
            "finances.group_editor.name_template.credits"
        case .deposits:
            "finances.group_editor.name_template.deposits"
        case .foreignCards:
            "finances.group_editor.name_template.foreign_cards"
        }
    }

    var title: String {
        FinancesL10n.tr(localizationKey)
    }
}
