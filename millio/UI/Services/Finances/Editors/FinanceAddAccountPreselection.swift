//
//  FinanceAddAccountPreselection.swift
//  millio
//

import Foundation

enum FinanceAddAccountPreselection {
    static func productTitle(for accountType: FinanceAccountType) -> String {
        switch accountType {
        case .card:
            return FinanceAccountType.card.displayName
        case .credit:
            return FinanceAccountType.credit.displayName
        case .investment:
            return String(localized: "finances.account.type.investment")
        }
    }
}
